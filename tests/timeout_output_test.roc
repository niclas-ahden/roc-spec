app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst",
	spec: "../package/main.roc",
}

import pf.Stdout
import spec.Spec
import Effects

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

	results = Spec.run!(Effects.spec, "tests/timeout_output_fixtures", config)?

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
