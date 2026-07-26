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

pass_marker = "QUIET_TEST_STDOUT_MARKER"

fail_marker = "QUIET_TEST_FAIL_MARKER"

main! = |_args| {
	# Test 1: quiet mode still captures output in result.output
	config_quiet = {
		max_workers: 2,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results_quiet = Spec.run!(effects, "tests/quiet_fixtures", config_quiet)?

	# Test 2: non-quiet mode also captures output
	config_verbose = {
		max_workers: 2,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.False,
		fail_fast: Bool.False,
	}

	results_verbose = Spec.run!(effects, "tests/quiet_fixtures", config_verbose)?

	# Verify both runs captured the output correctly
	result_pass_quiet = results_quiet.find_first(|r| r.name.contains("verbose_pass"))
	result_fail_quiet = results_quiet.find_first(|r| r.name.contains("verbose_fail"))
	result_pass_verbose = results_verbose.find_first(|r| r.name.contains("verbose_pass"))
	result_fail_verbose = results_verbose.find_first(|r| r.name.contains("verbose_fail"))

	match (result_pass_quiet, result_fail_quiet, result_pass_verbose, result_fail_verbose) {
		(Ok(pq), Ok(fq), Ok(pv), Ok(fv)) => {
			# Verify pass/fail status
			pass_status_ok = pq.passed and pv.passed and !fq.passed and !fv.passed

			# Verify output captured in both modes
			quiet_pass_has_output = pq.output.contains(pass_marker)
			quiet_fail_has_output = fq.output.contains(fail_marker)
			verbose_pass_has_output = pv.output.contains(pass_marker)
			verbose_fail_has_output = fv.output.contains(fail_marker)

			all_output_captured = quiet_pass_has_output and quiet_fail_has_output and verbose_pass_has_output and verbose_fail_has_output

			if pass_status_ok and all_output_captured {
				Stdout.line!("PASS: quiet mode works correctly (output captured in both modes)")
			} else if !pass_status_ok {
				Stdout.line!("FAIL: Unexpected pass/fail status")?
				Err(WrongPassFailStatus)
			} else {
				Stdout.line!("FAIL: Output not captured correctly")?
				Stdout.line!("  quiet_pass: ${pq.output.trim()}")?
				Stdout.line!("  quiet_fail: ${fq.output.trim()}")?
				Stdout.line!("  verbose_pass: ${pv.output.trim()}")?
				Stdout.line!("  verbose_fail: ${fv.output.trim()}")?
				Err(OutputNotCaptured)
			}
		}

		_ => {
			Stdout.line!("FAIL: Could not find all test results")?
			Err(ResultsNotFound)
		}
	}
}
