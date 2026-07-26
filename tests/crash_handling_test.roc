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
	# Directory contains:
	# - crashes_test.roc (uses `crash` - should be marked as failed)
	# - normal_test.roc (normal test - should pass)
	#
	# The test framework should handle crashes gracefully:
	# - Not hang or crash itself
	# - Mark the crashing test as failed
	# - Continue running other tests

	config = {
		max_workers: 2,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results = Spec.run!(effects, "tests/crash_fixtures", config)?

	if results.len() != 2 {
		Stdout.line!("FAIL: Expected 2 test results, got ${results.len().to_str()}")?
		Err(WrongResultCount)
	} else {
		result_crash = results.find_first(|r| r.name.contains("crashes"))
		result_normal = results.find_first(|r| r.name.contains("normal"))

		match (result_crash, result_normal) {
			(Ok(crash_r), Ok(normal_r)) => {
				crash_failed = !crash_r.passed
				normal_passed = normal_r.passed
				crash_has_output = crash_r.output.contains("About to crash")

				if crash_failed and normal_passed and crash_has_output {
					Stdout.line!("PASS: Crash handled gracefully (crashed test failed, normal test passed)")
				} else if !crash_failed {
					Stdout.line!("FAIL: Crashing test should have failed")?
					Err(CrashShouldFail)
				} else if !normal_passed {
					Stdout.line!("FAIL: Normal test should have passed")?
					Err(NormalShouldPass)
				} else {
					Stdout.line!("FAIL: Crash output not captured")?
					Err(CrashOutputMissing)
				}
			}

			_ => {
				Stdout.line!("FAIL: Could not find both test results")?
				Err(ResultsNotFound)
			}
		}
	}
}
