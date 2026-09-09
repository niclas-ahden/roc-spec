app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst",
	spec: "../package/main.roc",
}

import pf.Stdout
import spec.Spec
import Effects

no_envs = |_index| []

main! = |_args| {
	# Test that the framework handles multi-line output (~10KB) without:
	# - Crashing
	# - Hanging
	# - Losing data (at least the markers should be present)

	config = {
		max_workers: 1,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 60_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results = Spec.run!(Effects.spec, "tests/large_output_fixtures", config)?

	match results.first() {
		Err(_) => {
			Stdout.line!("FAIL: Expected 1 test result, got none")?
			Err(NoResults)
		}

		Ok(result) => {
			passed = result.passed
			output_len = result.output.count_utf8_bytes()
			has_start = result.output.contains("START_MARKER")
			has_end = result.output.contains("END_MARKER")

			# Output should be substantial (at least 5KB)
			is_large = output_len > 5_000

			if passed and has_start and has_end and is_large {
				Stdout.line!("PASS: Multi-line output handled (${output_len.to_str()} bytes captured with start/end markers)")
			} else if !passed {
				Stdout.line!("FAIL: Test should have passed")?
				Err(TestShouldHavePassed)
			} else if !has_start {
				Stdout.line!("FAIL: START_MARKER not found in output")?
				Err(StartMarkerMissing)
			} else if !has_end {
				Stdout.line!("FAIL: END_MARKER not found in output (possible truncation)")?
				Err(EndMarkerMissing)
			} else {
				Stdout.line!("FAIL: Output too small: ${output_len.to_str()} bytes (expected > 5KB)")?
				Err(OutputTooSmall)
			}
		}
	}
}
