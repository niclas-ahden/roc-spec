app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
	spec: "../package/main.roc",
}

import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stdout
import pf.Utc
import spec.Spec

effects = {
	spawn_test!: |file, envs|
		Cmd.new(OsStr.utf8("roc"))
			.args_str(["--opt=speed", file])
			.envs_str(envs)
			.spawn_grouped!(),
	poll!: Cmd.Child.poll!,
	kill_wait!: Cmd.Child.kill_wait!,
	list_dir!: |dir| Path.list!(Path.utf8(dir)).map_ok(|entries| entries.map(Path.display)),
	print!: Stdout.line!,
	utc_now!: Utc.now!,
	sleep_millis!: Sleep.millis!,
}

no_envs = |_index| []

main! = |_args| {
	# Test that result.name is correctly extracted from file paths.
	# Uses nested_fixtures which has tests at different directory levels, named
	# relative to the directory passed to run! (here "tests/nested_fixtures"):
	# - tests/nested_fixtures/root_test.roc -> "root_test"
	# - tests/nested_fixtures/level1/level1_test.roc -> "level1/level1_test"
	# - etc.

	config = {
		max_workers: 4,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results = Spec.run!(effects, "tests/nested_fixtures", config)?

	# Expected names (sorted for comparison)
	expected_names = [
		"level1/level2/level3/level3_test",
		"level1/level2/level2_test",
		"level1/level1_test",
		"root_test",
	]

	# Get actual names
	actual_names = results.map(|r| r.name)

	# Check that all expected names are present
	all_present = expected_names.all(|name| actual_names.contains(name))
	correct_count = actual_names.len() == expected_names.len()

	if all_present and correct_count {
		Stdout.line!("PASS: result.name correctly extracted for all nesting levels")
	} else {
		Stdout.line!("FAIL: result.name mismatch")?
		Stdout.line!("  Expected: ${Str.inspect(expected_names)}")?
		Stdout.line!("  Actual:   ${Str.inspect(actual_names)}")?
		Err(NameMismatch)
	}
}
