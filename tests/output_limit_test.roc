app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst",
	spec: "../package/main.roc",
}

import pf.Cmd
import pf.OsStr
import pf.Stdout
import spec.Spec
import Effects

## The shared effects with a capture budget far below what the fixture prints.
effects = {
	..Effects.spec,
	spawn_test!: |file, envs|
		Cmd.new(OsStr.utf8("roc"))
			.args_str(["--opt=speed", file])
			.envs_str(envs)
			.stdout(Capture)
			.stderr(Capture)
			.output_limit(10_000)
			.spawn_leashed!(),
}

# Test: a test that prints more than its capture budget
# Expected: the platform cancels it, and it is reported as failed with the
# output it managed to print and a note saying how to raise the limit.
main! = |_args| {
	config = {
		max_workers: 1,
		worker_envs: |_index| [],
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 60_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results = Spec.run!(effects, "tests/output_limit_fixtures", config)?

	match results.first() {
		Err(_) => {
			Stdout.line!("FAIL: Expected 1 test result, got none")?
			Err(NoResults)
		}

		Ok(result) => {
			failed = !result.passed
			explained = result.error.contains("output limit")
			kept_output = result.output.contains("START_MARKER")
			cut_off = !result.output.contains("END_MARKER")

			if failed and explained and kept_output and cut_off {
				Stdout.line!("PASS: Over-budget test was cancelled and reported with its partial output")
			} else if !failed {
				Stdout.line!("FAIL: Test should have failed for exceeding its output limit")?
				Err(TestShouldHaveFailed)
			} else if !explained {
				Stdout.line!("FAIL: Error should mention the output limit")?
				Stdout.line!("  Got: ${result.error}")?
				Err(WrongErrorMessage)
			} else if !kept_output {
				Stdout.line!("FAIL: Output from before the cut-off was lost")?
				Err(OutputNotCaptured)
			} else {
				Stdout.line!("FAIL: Output was not cut off at the limit")?
				Err(OutputNotLimited)
			}
		}
	}
}
