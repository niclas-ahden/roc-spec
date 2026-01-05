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
    # - test_syntax_error.roc (has syntax error - should fail to compile)
    # - test_compiles_ok.roc (normal test - should pass)
    #
    # The test framework should handle compilation errors gracefully:
    # - Not hang or crash itself
    # - Mark the non-compiling test as failed
    # - Continue running other tests

    config = {
        max_workers: 2,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 60_000, # Longer timeout for compilation
        quiet: Bool.true,
    }

    results = Spec.run!("tests/compile_error_fixtures", config)?

    if List.len(results) != 2 then
        Stdout.line!("FAIL: Expected 2 test results, got $(Num.to_str(List.len(results)))")?
        Err(WrongResultCount)
    else
        result_error = List.find_first(results, |r| Str.contains(r.name, "syntax_error"))
        result_ok = List.find_first(results, |r| Str.contains(r.name, "compiles_ok"))

        when (result_error, result_ok) is
            (Ok(error_r), Ok(ok_r)) ->
                error_failed = !error_r.passed
                ok_passed = ok_r.passed

                if error_failed && ok_passed then
                    Stdout.line!("PASS: Compile error handled gracefully (syntax error failed, valid test passed)")
                else if !error_failed then
                    Stdout.line!("FAIL: Test with syntax error should have failed")?
                    Err(SyntaxErrorShouldFail)
                else
                    Stdout.line!("FAIL: Valid test should have passed")?
                    Err(ValidShouldPass)

            _ ->
                Stdout.line!("FAIL: Could not find both test results")?
                Err(ResultsNotFound)
