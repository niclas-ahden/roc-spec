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
    # - test_valid.roc (should run)
    # - helper.roc (should be ignored - no test_ prefix)
    # - my_test.roc (should be ignored - no test_ prefix)
    # - test_wrong.txt (should be ignored - wrong extension)
    #
    # Only test_valid.roc should be discovered and run

    config = {
        max_workers: 4,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results = Spec.run!("tests/discovery_fixtures", config)?

    count = List.len(results)

    if count != 1 then
        names = List.map(results, |r| r.name)
        Stdout.line!("FAIL: Expected 1 test (test_valid), got $(Num.to_str(count)): $(Inspect.to_str(names))")?
        Err(WrongTestCount)
    else
        when List.first(results) is
            Ok(result) ->
                is_valid_test = Str.contains(result.name, "test_valid")
                passed = result.passed
                has_correct_output = Str.contains(result.output, "valid test ran")

                if is_valid_test && passed && has_correct_output then
                    Stdout.line!("PASS: Only test_valid.roc was run (helper.roc, my_test.roc, test_wrong.txt ignored)")
                else if !is_valid_test then
                    Stdout.line!("FAIL: Wrong test ran: $(result.name)")?
                    Err(WrongTestRan)
                else if !passed then
                    Stdout.line!("FAIL: test_valid should have passed")?
                    Err(TestShouldHavePassed)
                else
                    Stdout.line!("FAIL: test_valid output incorrect")?
                    Err(WrongOutput)

            Err(_) ->
                Stdout.line!("FAIL: Could not get first result")?
                Err(NoResults)
