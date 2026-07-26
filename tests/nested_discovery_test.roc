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
	config = {
		max_workers: 4,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results = Spec.run!(effects, "tests/nested_fixtures", config)?

	# Should find 4 test files: root, level1, level2, level3
	count = results.len()
	all_passed = results.all(|r| r.passed)

	# Check that names keep the subdirectories below the directory that was
	# passed to run! (not just basenames)
	# Expected format: "level1/level2/level2_test" etc.
	names = results.map(|r| r.name)
	has_root = names.any(|n| n == "root_test")
	has_level1 = names.any(|n| n == "level1/level1_test")
	has_level2 = names.any(|n| n == "level1/level2/level2_test")
	has_level3 = names.any(|n| n == "level1/level2/level3/level3_test")

	if count == 4 and all_passed and has_root and has_level1 and has_level2 and has_level3 {
		Stdout.line!("PASS: Recursive discovery found all 4 nested test files with correct paths")
	} else if count != 4 {
		Stdout.line!("FAIL: Expected 4 tests, found ${count.to_str()}")?
		Err(WrongTestCount)
	} else if !all_passed {
		Stdout.line!("FAIL: Not all tests passed")?
		Err(TestsFailed)
	} else {
		# Show actual names to help debug
		names_str = Str.join_with(names, ", ")
		Stdout.line!("FAIL: Test names don't include nested directory paths. Got: ${names_str}")?
		Err(MissingNestedPaths)
	}
}
