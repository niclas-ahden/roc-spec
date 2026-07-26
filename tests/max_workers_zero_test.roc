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
	# Test edge case: max_workers: 0
	# Expected behavior: rejected outright. No worker can ever run a test, and
	# an empty Ok would be a green run that tested nothing.

	config = {
		max_workers: 0,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 5_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	# Use a directory with a single simple test
	match Spec.run!(effects, "tests/ignore_fixtures", config) {
		Err(MaxWorkersIsZero) =>
			Stdout.line!("PASS: max_workers: 0 is rejected instead of reporting a green run")

		Ok(results) => {
			Stdout.line!("FAIL: max_workers: 0 returned Ok with ${results.len().to_str()} results")?
			Err(ShouldHaveErrored)
		}

		Err(other) => {
			Stdout.line!("FAIL: expected MaxWorkersIsZero, got ${Str.inspect(other)}")?
			Err(WrongError)
		}
	}
}
