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
    # Test that the framework handles multi-line output (~10KB) without:
    # - Crashing
    # - Hanging
    # - Losing data (at least the markers should be present)

    config = {
        max_workers: 1,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 60_000,
        quiet: Bool.true,
    }

    results = Spec.run!("tests/large_output_fixtures", config)?

    when List.first(results) is
        Err(_) ->
            Stdout.line!("FAIL: Expected 1 test result, got none")?
            Err(NoResults)

        Ok(result) ->
            passed = result.passed
            output_len = Str.count_utf8_bytes(result.output)
            has_start = Str.contains(result.output, "START_MARKER")
            has_end = Str.contains(result.output, "END_MARKER")

            # Output should be substantial (at least 5KB)
            is_large = output_len > 5_000

            if passed && has_start && has_end && is_large then
                Stdout.line!("PASS: Multi-line output handled ($(Num.to_str(output_len)) bytes captured with start/end markers)")
            else if !passed then
                Stdout.line!("FAIL: Test should have passed")?
                Err(TestShouldHavePassed)
            else if !has_start then
                Stdout.line!("FAIL: START_MARKER not found in output")?
                Err(StartMarkerMissing)
            else if !has_end then
                Stdout.line!("FAIL: END_MARKER not found in output (possible truncation)")?
                Err(EndMarkerMissing)
            else
                Stdout.line!("FAIL: Output too small: $(Num.to_str(output_len)) bytes (expected > 5KB)")?
                Err(OutputTooSmall)
