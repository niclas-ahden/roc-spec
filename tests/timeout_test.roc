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

now_ms! : {} => U64
now_ms! = |{}| Utc.to_millis_since_epoch(Utc.now!()).to_u64_wrap()

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
		max_workers: 1,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 4_000, # 4 second timeout (compile takes ~2s), test sleeps for 10
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	start_time = now_ms!({})
	results = Spec.run!(effects, "tests/timeout_fixtures", config)?
	end_time = now_ms!({})

	elapsed_ms = end_time.minus_saturated(start_time)

	# Should have 1 result
	match results.first() {
		Err(_) => {
			Stdout.line!("FAIL: Expected 1 test result, got none")?
			Err(NoResults)
		}

		Ok(result) => {
			# Test should have failed (timeout)
			# Elapsed time should be ~4 seconds (timeout), not 10+ seconds (full sleep)
			# Error message should contain "Test timed out"
			failed = !result.passed
			fast_enough = elapsed_ms < 8000
			has_timeout_message = result.error.contains("Test timed out")

			if failed and fast_enough and has_timeout_message {
				Stdout.line!("PASS: Test timed out correctly in ${elapsed_ms.to_str()}ms with correct error message")
			} else if result.passed {
				Stdout.line!("FAIL: Test should have failed due to timeout")?
				Err(TestShouldHaveFailed)
			} else if !fast_enough {
				Stdout.line!("FAIL: Test failed but took ${elapsed_ms.to_str()}ms (expected < 8000ms)")?
				Err(TimeoutTookTooLong)
			} else {
				Stdout.line!("FAIL: Error message should contain 'Test timed out'")?
				Stdout.line!("  Got: ${result.error}")?
				Err(WrongErrorMessage)
			}
		}
	}
}
