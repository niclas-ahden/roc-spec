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
		max_workers: 1,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		# 4 second timeout (compile takes ~2s), the fixture sleeps for 10
		per_test_timeout_ms: 4_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results = Spec.run!(effects, "tests/timeout_output_fixtures", config)?

	match results.first() {
		Err(_) => {
			Stdout.line!("FAIL: Expected 1 test result, got none")?
			Err(NoResults)
		}

		Ok(result) => {
			# Killing the test must not cost us what it printed before it hung
			failed = !result.passed
			timed_out = result.error.contains("Test timed out")
			kept_output = result.output.contains("chatty stdout before hanging")

			if failed and timed_out and kept_output {
				Stdout.line!("PASS: Timed-out test reported its output")
			} else if !failed {
				Stdout.line!("FAIL: Test should have failed due to timeout")?
				Err(TestShouldHaveFailed)
			} else if !timed_out {
				Stdout.line!("FAIL: Error should contain 'Test timed out'")?
				Stdout.line!("  Got: ${result.error}")?
				Err(WrongErrorMessage)
			} else {
				Stdout.line!("FAIL: Output from before the timeout was lost")?
				Stdout.line!("  Got: ${Str.inspect(result.output)}")?
				Err(OutputNotCaptured)
			}
		}
	}
}
