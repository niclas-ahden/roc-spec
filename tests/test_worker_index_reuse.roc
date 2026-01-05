app [main!] {
    pf: platform "../../growthagent/basic-cli/platform/main.roc",
    spec: "../package/main.roc",
}

import pf.Arg
import pf.Stdout
import pf.Cmd
import pf.Dir
import pf.Path
import pf.Utc
import pf.Sleep

dir_list! : Str => Result (List Str) _
dir_list! = |path|
    Dir.list!(path)
    |> Result.map_ok(|paths| List.map(paths, Path.display))

utc_now! : {} => I128
utc_now! = |{}|
    Utc.now!({}) |> Utc.to_millis_since_epoch

# Pass worker index as env var
with_worker_index : U64 -> List (Str, Str)
with_worker_index = |index| [("WORKER_INDEX", Num.to_str(index))]

import spec.Spec {
    cmd_new: Cmd.new,
    cmd_args: Cmd.args,
    cmd_envs: Cmd.envs,
    cmd_spawn_grouped!: Cmd.spawn_grouped!,
    stdout_line!: Stdout.line!,
    dir_list!: dir_list!,
    utc_now!: utc_now!,
    sleep_millis!: Sleep.millis!,
}

main! : List Arg.Arg => Result {} _
main! = |_args|
    # Run 4 tests with only 2 workers
    # This means worker indices 0 and 1 must each be reused at least once
    config = {
        max_workers: 2,
        worker_envs: with_worker_index,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results = Spec.run!("tests/worker_reuse_fixtures", config)?

    if List.len(results) != 4 then
        Stdout.line!("FAIL: Expected 4 test results, got $(Num.to_str(List.len(results)))")?
        Err(WrongResultCount)
    else
        # Extract worker indices from each test's output
        indices = List.map(results, |r|
            # Parse "WORKER_INDEX=N" from output
            when Str.split_first(r.output, "WORKER_INDEX=") is
                Ok({ after }) -> Str.trim(after)
                Err(_) -> "parse_error"
        )

        # Count how many times each index appears
        count_0 = List.count_if(indices, |i| i == "0")
        count_1 = List.count_if(indices, |i| i == "1")

        # With 4 tests and 2 workers, each index should be used at least twice
        # (indices should be reused when workers become free)
        all_passed = List.all(results, |r| r.passed)
        index_0_reused = count_0 >= 2
        index_1_reused = count_1 >= 2
        total_correct = count_0 + count_1 == 4

        if all_passed && index_0_reused && index_1_reused && total_correct then
            Stdout.line!("PASS: Worker indices correctly reused (0 used $(Num.to_str(count_0))x, 1 used $(Num.to_str(count_1))x)")
        else if !all_passed then
            Stdout.line!("FAIL: Not all tests passed")?
            Err(TestsFailed)
        else if !total_correct then
            Stdout.line!("FAIL: Expected 4 total index uses, got $(Num.to_str(count_0 + count_1)). Indices: $(Inspect.to_str(indices))")?
            Err(WrongIndexCount)
        else
            Stdout.line!("FAIL: Worker indices not reused. Index 0: $(Num.to_str(count_0))x, Index 1: $(Num.to_str(count_1))x (expected each >= 2)")?
            Stdout.line!("  Indices: $(Inspect.to_str(indices))")?
            Err(IndicesNotReused)
