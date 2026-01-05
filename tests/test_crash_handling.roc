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
    # Directory contains:
    # - test_crashes.roc (uses `crash` - should be marked as failed)
    # - test_normal.roc (normal test - should pass)
    #
    # The test framework should handle crashes gracefully:
    # - Not hang or crash itself
    # - Mark the crashing test as failed
    # - Continue running other tests

    config = {
        max_workers: 2,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results = Spec.run!("tests/crash_fixtures", config)?

    if List.len(results) != 2 then
        Stdout.line!("FAIL: Expected 2 test results, got $(Num.to_str(List.len(results)))")?
        Err(WrongResultCount)
    else
        result_crash = List.find_first(results, |r| Str.contains(r.name, "crashes"))
        result_normal = List.find_first(results, |r| Str.contains(r.name, "normal"))

        when (result_crash, result_normal) is
            (Ok(crash_r), Ok(normal_r)) ->
                crash_failed = !crash_r.passed
                normal_passed = normal_r.passed
                crash_has_output = Str.contains(crash_r.output, "About to crash")

                if crash_failed && normal_passed && crash_has_output then
                    Stdout.line!("PASS: Crash handled gracefully (crashed test failed, normal test passed)")
                else if !crash_failed then
                    Stdout.line!("FAIL: Crashing test should have failed")?
                    Err(CrashShouldFail)
                else if !normal_passed then
                    Stdout.line!("FAIL: Normal test should have passed")?
                    Err(NormalShouldPass)
                else
                    Stdout.line!("FAIL: Crash output not captured")?
                    Err(CrashOutputMissing)

            _ ->
                Stdout.line!("FAIL: Could not find both test results")?
                Err(ResultsNotFound)
