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

pass_marker = "QUIET_TEST_STDOUT_MARKER"
fail_marker = "QUIET_TEST_FAIL_MARKER"

main! : List Arg.Arg => Result {} _
main! = |_args|
    # Test 1: quiet mode still captures output in result.output
    config_quiet = {
        max_workers: 2,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results_quiet = Spec.run!("tests/quiet_fixtures", config_quiet)?

    # Test 2: non-quiet mode also captures output
    config_verbose = {
        max_workers: 2,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.false,
    }

    results_verbose = Spec.run!("tests/quiet_fixtures", config_verbose)?

    # Verify both runs captured the output correctly
    result_pass_quiet = List.find_first(results_quiet, |r| Str.contains(r.name, "verbose_pass"))
    result_fail_quiet = List.find_first(results_quiet, |r| Str.contains(r.name, "verbose_fail"))
    result_pass_verbose = List.find_first(results_verbose, |r| Str.contains(r.name, "verbose_pass"))
    result_fail_verbose = List.find_first(results_verbose, |r| Str.contains(r.name, "verbose_fail"))

    when (result_pass_quiet, result_fail_quiet, result_pass_verbose, result_fail_verbose) is
        (Ok(pq), Ok(fq), Ok(pv), Ok(fv)) ->
            # Verify pass/fail status
            pass_status_ok = pq.passed && pv.passed && !fq.passed && !fv.passed

            # Verify output captured in both modes
            quiet_pass_has_output = Str.contains(pq.output, pass_marker)
            quiet_fail_has_output = Str.contains(fq.output, fail_marker)
            verbose_pass_has_output = Str.contains(pv.output, pass_marker)
            verbose_fail_has_output = Str.contains(fv.output, fail_marker)

            all_output_captured = quiet_pass_has_output && quiet_fail_has_output && verbose_pass_has_output && verbose_fail_has_output

            if pass_status_ok && all_output_captured then
                Stdout.line!("PASS: quiet mode works correctly (output captured in both modes)")
            else if !pass_status_ok then
                Stdout.line!("FAIL: Unexpected pass/fail status")?
                Err(WrongPassFailStatus)
            else
                Stdout.line!("FAIL: Output not captured correctly")?
                Stdout.line!("  quiet_pass: $(Str.trim(pq.output))")?
                Stdout.line!("  quiet_fail: $(Str.trim(fq.output))")?
                Stdout.line!("  verbose_pass: $(Str.trim(pv.output))")?
                Stdout.line!("  verbose_fail: $(Str.trim(fv.output))")?
                Err(OutputNotCaptured)

        _ ->
            Stdout.line!("FAIL: Could not find all test results")?
            Err(ResultsNotFound)
