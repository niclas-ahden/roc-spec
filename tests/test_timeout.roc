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
        max_workers: 1,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 2_000, # 2 second timeout, test sleeps for 10
        quiet: Bool.true,
    }

    start_time = utc_now!({})
    results = Spec.run!("tests/timeout_fixtures", config)?
    end_time = utc_now!({})

    elapsed_ms = end_time - start_time

    # Should have 1 result
    when List.first(results) is
        Err(_) ->
            Stdout.line!("FAIL: Expected 1 test result, got none")?
            Err(NoResults)

        Ok(result) ->
            # Test should have failed (timeout)
            # Elapsed time should be ~2 seconds (timeout), not 10 seconds (full sleep)
            # Error message should contain "Test timed out"
            failed = !result.passed
            fast_enough = elapsed_ms < 5000
            has_timeout_message = Str.contains(result.error, "Test timed out")

            if failed && fast_enough && has_timeout_message then
                Stdout.line!("PASS: Test timed out correctly in $(Num.to_str(elapsed_ms))ms with correct error message")
            else if result.passed then
                Stdout.line!("FAIL: Test should have failed due to timeout")?
                Err(TestShouldHaveFailed)
            else if !fast_enough then
                Stdout.line!("FAIL: Test failed but took $(Num.to_str(elapsed_ms))ms (expected < 5000ms)")?
                Err(TimeoutTookTooLong)
            else
                Stdout.line!("FAIL: Error message should contain 'Test timed out'")?
                Stdout.line!("  Got: $(result.error)")?
                Err(WrongErrorMessage)
