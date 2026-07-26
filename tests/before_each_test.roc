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

with_worker_id = |index| [("TEST_WORKER_ID", index.to_str())]

main! = |_args| {
	# Test 1: before_each! succeeds -> test should pass
	config_ok = {
		max_workers: 1,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results_ok = Spec.run!(effects, "tests/before_each_fixtures", config_ok)?

	passed_when_hook_ok =
		match results_ok.first() {
			Ok(r) => r.passed
			Err(_) => Bool.False
		}

	# Test 2: before_each! fails -> test should fail
	config_fail = {
		max_workers: 1,
		worker_envs: no_envs,
		before_each!: |_index| Err(HookFailed),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results_fail = Spec.run!(effects, "tests/before_each_fixtures", config_fail)?

	failed_when_hook_fails =
		match results_fail.first() {
			Ok(r) => !r.passed
			Err(_) => Bool.False
		}

	# Test 3: before_each! receives correct worker_index
	# Use 2 workers, 2 tests - verify each gets index 0 or 1
	# We pass the index via env var and have the test output it
	config_index = {
		max_workers: 2,
		worker_envs: with_worker_id,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results_index = Spec.run!(effects, "tests/env_fixtures", config_index)?

	# Both tests should pass and have different indices
	all_index_passed = results_index.all(|r| r.passed)
	indices = results_index.map(
		|r|
			match r.output.split_first("Worker ID: ") {
				Ok({ before: _, after }) => after.trim()
				Err(_) => "parse_error"
			},
	)
	has_index_0 = indices.contains("0")
	has_index_1 = indices.contains("1")
	indices_correct = has_index_0 and has_index_1 and indices.len() == 2

	if passed_when_hook_ok and failed_when_hook_fails and all_index_passed and indices_correct {
		Stdout.line!("PASS: before_each! hook behavior verified")
	} else if !passed_when_hook_ok {
		Stdout.line!("FAIL: Test should pass when before_each! succeeds")?
		Err(ShouldHavePassed)
	} else if !failed_when_hook_fails {
		Stdout.line!("FAIL: Test should fail when before_each! returns error")?
		Err(ShouldHaveFailed)
	} else if !all_index_passed {
		Stdout.line!("FAIL: Tests should pass with worker_index verification")?
		Err(IndexTestsFailed)
	} else {
		Stdout.line!("FAIL: before_each! worker_index incorrect. Indices: ${Str.inspect(indices)}")?
		Err(IndicesWrong)
	}
}
