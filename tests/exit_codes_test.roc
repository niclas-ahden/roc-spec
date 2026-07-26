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
		max_workers: 2,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results = Spec.run!(effects, "tests/exit_fixtures", config)?

	# Should have 2 results
	if results.len() != 2 {
		Stdout.line!("FAIL: Expected 2 test results, got ${results.len().to_str()}")?
		Err(WrongResultCount)
	} else {
		# Find each result by name
		result_exit_0 = results.find_first(|r| r.name.contains("exit_0"))
		result_exit_1 = results.find_first(|r| r.name.contains("exit_1"))

		match (result_exit_0, result_exit_1) {
			(Ok(r0), Ok(r1)) => {
				# Verify exit_0 passed and exit_1 failed
				exit_0_passed = r0.passed
				exit_1_failed = !r1.passed

				if exit_0_passed and exit_1_failed {
					Stdout.line!("PASS: exit_0_test passed, exit_1_test failed (exit codes work)")
				} else if !exit_0_passed {
					Stdout.line!("FAIL: exit_0_test should have passed (exit code 0)")?
					Err(Exit0ShouldPass)
				} else {
					Stdout.line!("FAIL: exit_1_test should have failed (exit code 1)")?
					Err(Exit1ShouldFail)
				}
			}

			_ => {
				Stdout.line!("FAIL: Could not find both test results by name")?
				Err(ResultsNotFound)
			}
		}
	}
}
