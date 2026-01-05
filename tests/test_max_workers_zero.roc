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
    # Test edge case: max_workers: 0
    # Expected behavior: should handle gracefully (not hang or crash)
    # Actual behavior depends on implementation - let's document what happens

    config = {
        max_workers: 0,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 5_000,
        quiet: Bool.true,
    }

    # Use a directory with a single simple test
    results = Spec.run!("tests/ignore_fixtures", config)?

    count = List.len(results)

    # With max_workers: 0, the initial batch is empty, but tests should still run
    # because the rolling window will spawn replacements as "slots free up"
    # Actually, with 0 workers, no tests can ever run - this should return empty or error

    if count == 0 then
        Stdout.line!("PASS: max_workers: 0 returns empty results (no workers to run tests)")
    else
        # If tests somehow ran, that's also acceptable behavior
        all_passed = List.all(results, |r| r.passed)
        if all_passed then
            Stdout.line!("PASS: max_workers: 0 still ran $(Num.to_str(count)) tests (treated as minimum 1?)")
        else
            Stdout.line!("FAIL: max_workers: 0 ran tests but some failed")?
            Err(TestsFailed)
