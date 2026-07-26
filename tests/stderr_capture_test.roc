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

stdout_marker = "STDOUT_MARKER_11111"

stderr_marker = "STDERR_MARKER_67890"

main! = |_args| {
	config = {
		max_workers: 1,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results = Spec.run!(effects, "tests/stderr_fixtures", config)?

	match results.first() {
		Err(_) => {
			Stdout.line!("FAIL: Expected 1 test result, got none")?
			Err(NoResults)
		}

		Ok(result) => {
			failed = !result.passed

			# Verify stdout marker is in output field, NOT in error field
			stdout_in_output = result.output.contains(stdout_marker)
			stdout_in_error = result.error.contains(stdout_marker)

			# Verify stderr marker is in error field, NOT in output field
			stderr_in_error = result.error.contains(stderr_marker)
			stderr_in_output = result.output.contains(stderr_marker)

			correctly_separated = stdout_in_output and !stdout_in_error and stderr_in_error and !stderr_in_output

			if failed and correctly_separated {
				Stdout.line!("PASS: stdout -> output, stderr -> error (correctly separated)")
			} else if result.passed {
				Stdout.line!("FAIL: Test should have failed")?
				Err(TestShouldHaveFailed)
			} else if !stdout_in_output {
				Stdout.line!("FAIL: stdout marker not in result.output")?
				Err(StdoutNotInOutput)
			} else if stdout_in_error {
				Stdout.line!("FAIL: stdout marker incorrectly in result.error")?
				Err(StdoutInError)
			} else if !stderr_in_error {
				Stdout.line!("FAIL: stderr marker not in result.error")?
				Err(StderrNotInError)
			} else {
				Stdout.line!("FAIL: stderr marker incorrectly in result.output")?
				Err(StderrInOutput)
			}
		}
	}
}
