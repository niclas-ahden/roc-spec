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

marker_a = "CAPTURED_OUTPUT_MARKER_12345"

marker_b = "DIFFERENT_MARKER_ZYXWV"

main! = |_args| {
	config = {
		max_workers: 2,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results = Spec.run!(effects, "tests/output_fixtures", config)?

	if results.len() != 2 {
		Stdout.line!("FAIL: Expected 2 test results, got ${results.len().to_str()}")?
		Err(WrongResultCount)
	} else {
		# Find result for each test by name
		result_a = results.find_first(|r| r.name.contains("stdout") and !r.name.contains("stdout_b"))
		result_b = results.find_first(|r| r.name.contains("stdout_b"))

		match (result_a, result_b) {
			(Ok(a), Ok(b)) => {
				# Verify each result has ONLY its own marker
				a_has_own = a.output.contains(marker_a)
				a_has_other = a.output.contains(marker_b)
				b_has_own = b.output.contains(marker_b)
				b_has_other = b.output.contains(marker_a)

				all_passed = a.passed and b.passed
				output_isolated = a_has_own and !a_has_other and b_has_own and !b_has_other

				if all_passed and output_isolated {
					Stdout.line!("PASS: stdout captured and isolated per test")
				} else if !all_passed {
					Stdout.line!("FAIL: Tests should have passed")?
					Err(TestShouldHavePassed)
				} else if !a_has_own {
					Stdout.line!("FAIL: Test A output missing its marker")?
					Err(MissingOwnMarker)
				} else if a_has_other {
					Stdout.line!("FAIL: Test A output contains Test B's marker (not isolated)")?
					Err(OutputNotIsolated)
				} else if !b_has_own {
					Stdout.line!("FAIL: Test B output missing its marker")?
					Err(MissingOwnMarker)
				} else {
					Stdout.line!("FAIL: Test B output contains Test A's marker (not isolated)")?
					Err(OutputNotIsolated)
				}
			}

			_ => {
				Stdout.line!("FAIL: Could not find both test results by name")?
				Err(ResultsNotFound)
			}
		}
	}
}
