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
    config = {
        max_workers: 2,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results = Spec.run!("tests/exit_fixtures", config)?

    # Should have 2 results
    if List.len(results) != 2 then
        Stdout.line!("FAIL: Expected 2 test results, got $(Num.to_str(List.len(results)))")?
        Err(WrongResultCount)
    else
        # Find each result by name
        result_exit_0 = List.find_first(results, |r| Str.contains(r.name, "exit_0"))
        result_exit_1 = List.find_first(results, |r| Str.contains(r.name, "exit_1"))

        when (result_exit_0, result_exit_1) is
            (Ok(r0), Ok(r1)) ->
                # Verify exit_0 passed and exit_1 failed
                exit_0_passed = r0.passed
                exit_1_failed = !r1.passed

                if exit_0_passed && exit_1_failed then
                    Stdout.line!("PASS: test_exit_0 passed, test_exit_1 failed (exit codes work)")
                else if !exit_0_passed then
                    Stdout.line!("FAIL: test_exit_0 should have passed (exit code 0)")?
                    Err(Exit0ShouldPass)
                else
                    Stdout.line!("FAIL: test_exit_1 should have failed (exit code 1)")?
                    Err(Exit1ShouldFail)

            _ ->
                Stdout.line!("FAIL: Could not find both test results by name")?
                Err(ResultsNotFound)
