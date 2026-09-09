app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst",
	spec: "../package/main.roc",
}

import pf.Stdout
import spec.Spec
import Effects

no_envs = |_index| []

main! = |_args| {
	# Tests are started in sorted order, not in whatever order the filesystem
	# lists them. One worker plus fail_fast makes that observable: a_first_test
	# passes, b_fails_test stops the run, and c_never_runs_test never starts.
	# Without sorted discovery, which tests get to run varies by machine.
	config = {
		max_workers: 1,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.True,
	}

	results = Spec.run!(Effects.spec, "tests/order_fixtures", config)?

	names = results.map(|r| r.name)
	ran_expected_tests = names == ["a_first_test", "b_fails_test"]
	stopped_on_failure = results.count_if(|r| r.passed) == 1

	if ran_expected_tests and stopped_on_failure {
		Stdout.line!("PASS: discovery is sorted, so fail_fast stops after the same tests every run")
	} else if !ran_expected_tests {
		Stdout.line!("FAIL: expected [a_first_test, b_fails_test] in that order")?
		Stdout.line!("  Got: ${Str.inspect(names)}")?
		Err(WrongTestsRan)
	} else {
		Stdout.line!("FAIL: expected exactly one passing test before the stop")?
		Err(WrongPassCount)
	}
}
