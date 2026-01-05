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

stdout_marker = "STDOUT_MARKER_11111"
stderr_marker = "STDERR_MARKER_67890"

main! : List Arg.Arg => Result {} _
main! = |_args|
    config = {
        max_workers: 1,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results = Spec.run!("tests/stderr_fixtures", config)?

    when List.first(results) is
        Err(_) ->
            Stdout.line!("FAIL: Expected 1 test result, got none")?
            Err(NoResults)

        Ok(result) ->
            failed = !result.passed

            # Verify stdout marker is in output field, NOT in error field
            stdout_in_output = Str.contains(result.output, stdout_marker)
            stdout_in_error = Str.contains(result.error, stdout_marker)

            # Verify stderr marker is in error field, NOT in output field
            stderr_in_error = Str.contains(result.error, stderr_marker)
            stderr_in_output = Str.contains(result.output, stderr_marker)

            correctly_separated = stdout_in_output && !stdout_in_error && stderr_in_error && !stderr_in_output

            if failed && correctly_separated then
                Stdout.line!("PASS: stdout -> output, stderr -> error (correctly separated)")
            else if result.passed then
                Stdout.line!("FAIL: Test should have failed")?
                Err(TestShouldHaveFailed)
            else if !stdout_in_output then
                Stdout.line!("FAIL: stdout marker not in result.output")?
                Err(StdoutNotInOutput)
            else if stdout_in_error then
                Stdout.line!("FAIL: stdout marker incorrectly in result.error")?
                Err(StdoutInWrongField)
            else if !stderr_in_error then
                Stdout.line!("FAIL: stderr marker not in result.error")?
                Err(StderrNotInError)
            else
                Stdout.line!("FAIL: stderr marker incorrectly in result.output")?
                Err(StderrInWrongField)
