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
    # Run sequentially so we can compare durations
    config = {
        max_workers: 1,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results = Spec.run!("tests/duration_fixtures", config)?

    if List.len(results) != 2 then
        Stdout.line!("FAIL: Expected 2 test results, got $(Num.to_str(List.len(results)))")?
        Err(WrongResultCount)
    else
        # Find each result by name
        result_100 = List.find_first(results, |r| Str.contains(r.name, "sleep_100"))
        result_300 = List.find_first(results, |r| Str.contains(r.name, "sleep_300"))

        when (result_100, result_300) is
            (Ok(r100), Ok(r300)) ->
                all_passed = r100.passed && r300.passed
                duration_100 = r100.duration_ms
                duration_300 = r300.duration_ms

                # The 300ms test should take significantly longer than the 100ms test
                # Difference should be at least 150ms (accounting for overhead variance)
                difference = duration_300 - duration_100
                has_expected_difference = difference >= 150

                # The 300ms test should be longer than 100ms test
                longer_is_longer = duration_300 > duration_100

                if all_passed && longer_is_longer && has_expected_difference then
                    Stdout.line!("PASS: duration_ms reflects actual execution (100ms:$(Num.to_str(duration_100)), 300ms:$(Num.to_str(duration_300)), diff:$(Num.to_str(difference)))")
                else if !all_passed then
                    Stdout.line!("FAIL: Tests should have passed")?
                    Err(TestShouldHavePassed)
                else if !longer_is_longer then
                    Stdout.line!("FAIL: 300ms test ($(Num.to_str(duration_300))) should take longer than 100ms test ($(Num.to_str(duration_100)))")?
                    Err(DurationOrderWrong)
                else
                    Stdout.line!("FAIL: Difference $(Num.to_str(difference))ms too small (expected >= 150ms)")?
                    Err(DifferenceTooSmall)

            _ ->
                Stdout.line!("FAIL: Could not find both test results by name")?
                Err(ResultsNotFound)
