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
	# Run sequentially so we can compare durations
	config = {
		max_workers: 1,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results = Spec.run!(effects, "tests/duration_fixtures", config)?

	if results.len() != 2 {
		Stdout.line!("FAIL: Expected 2 test results, got ${results.len().to_str()}")?
		Err(WrongResultCount)
	} else {
		# Find each result by name
		result_100 = results.find_first(|r| r.name.contains("sleep_100"))
		result_300 = results.find_first(|r| r.name.contains("sleep_600"))

		match (result_100, result_300) {
			(Ok(r100), Ok(r300)) => {
				all_passed = r100.passed and r300.passed
				duration_100 = r100.duration_ms
				duration_600 = r300.duration_ms

				# The 600ms test should take significantly longer than the 100ms test
				# Difference should be at least 150ms (accounting for overhead variance)
				difference = duration_600.minus_saturated(duration_100)
				has_expected_difference = difference >= 300

				# The 600ms test should be longer than 100ms test
				longer_is_longer = duration_600 > duration_100

				if all_passed and longer_is_longer and has_expected_difference {
					Stdout.line!("PASS: duration_ms reflects actual execution (100ms:${duration_100.to_str()}, 600ms:${duration_600.to_str()}, diff:${difference.to_str()})")
				} else if !all_passed {
					Stdout.line!("FAIL: Tests should have passed")?
					Err(TestShouldHavePassed)
				} else if !longer_is_longer {
					Stdout.line!("FAIL: 600ms test (${duration_600.to_str()}) should take longer than 100ms test (${duration_100.to_str()})")?
					Err(DurationOrderWrong)
				} else {
					Stdout.line!("FAIL: Difference ${difference.to_str()}ms too small (expected >= 300ms)")?
					Err(DifferenceTooSmall)
				}
			}

			_ => {
				Stdout.line!("FAIL: Could not find both test results by name")?
				Err(ResultsNotFound)
			}
		}
	}
}
