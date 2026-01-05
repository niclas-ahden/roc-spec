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
        max_workers: 4,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results = Spec.run!("tests/nested_fixtures", config)?

    # Should find 4 test files: root, level1, level2, level3
    count = List.len(results)
    all_passed = List.all(results, |r| r.passed)

    # Check that names include full nested directory paths (not just basenames)
    # Expected format: "nested_fixtures/level1/level2/test_level2" etc.
    names = List.map(results, |r| r.name)
    has_root = List.any(names, |n| n == "nested_fixtures/test_root")
    has_level1 = List.any(names, |n| n == "nested_fixtures/level1/test_level1")
    has_level2 = List.any(names, |n| n == "nested_fixtures/level1/level2/test_level2")
    has_level3 = List.any(names, |n| n == "nested_fixtures/level1/level2/level3/test_level3")

    if count == 4 && all_passed && has_root && has_level1 && has_level2 && has_level3 then
        Stdout.line!("PASS: Recursive discovery found all 4 nested test files with correct paths")
    else if count != 4 then
        Stdout.line!("FAIL: Expected 4 tests, found $(Num.to_str(count))")?
        Err(WrongTestCount)
    else if !all_passed then
        Stdout.line!("FAIL: Not all tests passed")?
        Err(TestsFailed)
    else
        # Show actual names to help debug
        names_str = Str.join_with(names, ", ")
        Stdout.line!("FAIL: Test names don't include nested directory paths. Got: $(names_str)")?
        Err(MissingNestedPaths)
