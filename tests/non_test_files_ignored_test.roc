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
	# Directory contains:
	# - valid_test.roc (should run)
	# - helper.roc (should be ignored - no _test suffix)
	# - test_prefix_only.roc (should be ignored - old test_ prefix, no _test suffix)
	# - wrong_test.txt (should be ignored - wrong extension)
	#
	# Only valid_test.roc should be discovered and run

	config = {
		max_workers: 4,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results = Spec.run!(effects, "tests/discovery_fixtures", config)?

	count = results.len()

	if count != 1 {
		names = results.map(|r| r.name)
		Stdout.line!("FAIL: Expected 1 test (valid_test), got ${count.to_str()}: ${Str.inspect(names)}")?
		Err(WrongTestCount)
	} else {
		match results.first() {
			Ok(result) => {
				is_valid_test = result.name.contains("valid_test")
				passed = result.passed
				has_correct_output = result.output.contains("valid test ran")

				if is_valid_test and passed and has_correct_output {
					Stdout.line!("PASS: Only valid_test.roc was run (helper.roc, test_prefix_only.roc, wrong_test.txt ignored)")
				} else if !is_valid_test {
					Stdout.line!("FAIL: Wrong test ran: ${result.name}")?
					Err(WrongTestRan)
				} else if !passed {
					Stdout.line!("FAIL: valid_test should have passed")?
					Err(TestShouldHavePassed)
				} else {
					Stdout.line!("FAIL: valid_test output incorrect")?
					Err(WrongOutput)
				}
			}

			Err(_) => {
				Stdout.line!("FAIL: Could not get first result")?
				Err(NoResults)
			}
		}
	}
}
