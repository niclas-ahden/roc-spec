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

no_envs : U64 -> List (Str, Str)
no_envs = |_index| []

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
    # Test 1: before_each! succeeds -> test should pass
    config_ok = {
        max_workers: 1,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results_ok = Spec.run!("tests/before_each_fixtures", config_ok)?

    passed_when_hook_ok =
        when List.first(results_ok) is
            Ok(r) -> r.passed
            Err(_) -> Bool.false

    # Test 2: before_each! fails -> test should fail
    config_fail = {
        max_workers: 1,
        worker_envs: no_envs,
        before_each!: |_index| Err(HookFailed),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results_fail = Spec.run!("tests/before_each_fixtures", config_fail)?

    failed_when_hook_fails =
        when List.first(results_fail) is
            Ok(r) -> !r.passed
            Err(_) -> Bool.false

    # Test 3: before_each! receives correct worker_index
    # Use 2 workers, 2 tests - verify each gets index 0 or 1
    # We pass the index via env var and have the test output it
    with_worker_id : U64 -> List (Str, Str)
    with_worker_id = |index| [("TEST_WORKER_ID", Num.to_str(index))]

    config_index = {
        max_workers: 2,
        worker_envs: with_worker_id,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results_index = Spec.run!("tests/env_fixtures", config_index)?

    # Both tests should pass and have different indices
    all_index_passed = List.all(results_index, |r| r.passed)
    indices = List.map(results_index, |r|
        when Str.split_first(r.output, "Worker ID: ") is
            Ok({ after }) -> Str.trim(after)
            Err(_) -> "parse_error"
    )
    has_index_0 = List.contains(indices, "0")
    has_index_1 = List.contains(indices, "1")
    indices_correct = has_index_0 && has_index_1 && List.len(indices) == 2

    if passed_when_hook_ok && failed_when_hook_fails && all_index_passed && indices_correct then
        Stdout.line!("PASS: before_each! hook behavior verified")
    else if !passed_when_hook_ok then
        Stdout.line!("FAIL: Test should pass when before_each! succeeds")?
        Err(ShouldHavePassed)
    else if !failed_when_hook_fails then
        Stdout.line!("FAIL: Test should fail when before_each! returns error")?
        Err(ShouldHaveFailed)
    else if !all_index_passed then
        Stdout.line!("FAIL: Tests should pass with worker_index verification")?
        Err(IndexTestsFailed)
    else
        Stdout.line!("FAIL: before_each! worker_index incorrect. Indices: $(Inspect.to_str(indices))")?
        Err(IndicesWrong)
