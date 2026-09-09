app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst",
	spec: "../package/main.roc",
}

import pf.Stdout
import spec.Spec
import Effects

no_envs = |_index| []

main! = |_args| {
	# Directory contains:
	# - syntax_error_test.roc (has syntax error - should fail to compile)
	# - compiles_ok_test.roc (normal test - should pass)
	#
	# The test framework should handle compilation errors gracefully:
	# - Not hang or crash itself
	# - Mark the non-compiling test as failed
	# - Continue running other tests

	config = {
		max_workers: 2,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 60_000, # Longer timeout for compilation
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results = Spec.run!(Effects.spec, "tests/compile_error_fixtures", config)?

	if results.len() != 2 {
		Stdout.line!("FAIL: Expected 2 test results, got ${results.len().to_str()}")?
		Err(WrongResultCount)
	} else {
		result_error = results.find_first(|r| r.name.contains("syntax_error"))
		result_ok = results.find_first(|r| r.name.contains("compiles_ok"))

		match (result_error, result_ok) {
			(Ok(error_r), Ok(ok_r)) => {
				error_failed = !error_r.passed
				ok_passed = ok_r.passed

				if error_failed and ok_passed {
					Stdout.line!("PASS: Compile error handled gracefully (syntax error failed, valid test passed)")
				} else if !error_failed {
					Stdout.line!("FAIL: Test with syntax error should have failed")?
					Err(SyntaxErrorShouldFail)
				} else {
					Stdout.line!("FAIL: Valid test should have passed")?
					Err(ValidShouldPass)
				}
			}

			_ => {
				Stdout.line!("FAIL: Could not find both test results")?
				Err(ResultsNotFound)
			}
		}
	}
}
