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
    # Test that result.name is correctly extracted from file paths
    # Uses nested_fixtures which has tests at different directory levels:
    # - nested_fixtures/test_root.roc -> "nested_fixtures/test_root"
    # - nested_fixtures/level1/test_level1.roc -> "nested_fixtures/level1/test_level1"
    # - etc.

    config = {
        max_workers: 4,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results = Spec.run!("tests/nested_fixtures", config)?

    # Expected names (sorted for comparison)
    expected_names = [
        "nested_fixtures/level1/level2/level3/test_level3",
        "nested_fixtures/level1/level2/test_level2",
        "nested_fixtures/level1/test_level1",
        "nested_fixtures/test_root",
    ]

    # Get actual names
    actual_names = List.map(results, |r| r.name)

    # Check that all expected names are present
    all_present = List.all(expected_names, |name| List.contains(actual_names, name))
    correct_count = List.len(actual_names) == List.len(expected_names)

    if all_present && correct_count then
        Stdout.line!("PASS: result.name correctly extracted for all nesting levels")
    else
        Stdout.line!("FAIL: result.name mismatch")?
        Stdout.line!("  Expected: $(Inspect.to_str(expected_names))")?
        Stdout.line!("  Actual:   $(Inspect.to_str(actual_names))")?
        Err(NameMismatch)
