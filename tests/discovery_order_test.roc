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
	# Tests are started in sorted order, not in whatever order the filesystem
	# lists them. One worker plus fail_fast makes that observable: a_first_test
	# passes, b_fails_test stops the run, and c_never_runs_test never starts.
	# Without sorted discovery, which tests get to run varies by machine.
	config = {
		max_workers: 1,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.True,
	}

	results = Spec.run!(effects, "tests/order_fixtures", config)?

	names = results.map(|r| r.name)
	ran_expected_tests = names == ["a_first_test", "b_fails_test"]
	stopped_on_failure = results.count_if(|r| r.passed) == 1

	if ran_expected_tests and stopped_on_failure {
		Stdout.line!("PASS: discovery is sorted, so fail_fast stops after the same tests every run")
	} else if !ran_expected_tests {
		Stdout.line!("FAIL: expected [a_first_test, b_fails_test] in that order")?
		Stdout.line!("  Got: ${Str.inspect(names)}")?
		Err(WrongTestsRan)
	} else {
		Stdout.line!("FAIL: expected exactly one passing test before the stop")?
		Err(WrongPassCount)
	}
}
