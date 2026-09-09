app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst",
	spec: "../package/main.roc",
}

import pf.Stdout
import spec.Spec
import Effects

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
	match Spec.run!(Effects.spec, "tests/ignore_fixtures", config) {
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
