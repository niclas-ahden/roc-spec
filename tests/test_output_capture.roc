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

marker_a = "CAPTURED_OUTPUT_MARKER_12345"
marker_b = "DIFFERENT_MARKER_ZYXWV"

main! : List Arg.Arg => Result {} _
main! = |_args|
    config = {
        max_workers: 2,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results = Spec.run!("tests/output_fixtures", config)?

    if List.len(results) != 2 then
        Stdout.line!("FAIL: Expected 2 test results, got $(Num.to_str(List.len(results)))")?
        Err(WrongResultCount)
    else
        # Find result for each test by name
        result_a = List.find_first(results, |r| Str.contains(r.name, "stdout") && !Str.contains(r.name, "stdout_b"))
        result_b = List.find_first(results, |r| Str.contains(r.name, "stdout_b"))

        when (result_a, result_b) is
            (Ok(a), Ok(b)) ->
                # Verify each result has ONLY its own marker
                a_has_own = Str.contains(a.output, marker_a)
                a_has_other = Str.contains(a.output, marker_b)
                b_has_own = Str.contains(b.output, marker_b)
                b_has_other = Str.contains(b.output, marker_a)

                all_passed = a.passed && b.passed
                output_isolated = a_has_own && !a_has_other && b_has_own && !b_has_other

                if all_passed && output_isolated then
                    Stdout.line!("PASS: stdout captured and isolated per test")
                else if !all_passed then
                    Stdout.line!("FAIL: Tests should have passed")?
                    Err(TestShouldHavePassed)
                else if !a_has_own then
                    Stdout.line!("FAIL: Test A output missing its marker")?
                    Err(MissingOwnMarker)
                else if a_has_other then
                    Stdout.line!("FAIL: Test A output contains Test B's marker (not isolated)")?
                    Err(OutputNotIsolated)
                else if !b_has_own then
                    Stdout.line!("FAIL: Test B output missing its marker")?
                    Err(MissingOwnMarker)
                else
                    Stdout.line!("FAIL: Test B output contains Test A's marker (not isolated)")?
                    Err(OutputNotIsolated)

            _ ->
                Stdout.line!("FAIL: Could not find both test results by name")?
                Err(ResultsNotFound)
