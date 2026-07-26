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
	# Test 1: with worker_envs -> test should pass
	config_with_env = {
		max_workers: 1,
		worker_envs: with_worker_id,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results_with_env = Spec.run!(effects, "tests/env_fixtures", config_with_env)?

	passed_with_env =
		match results_with_env.first() {
			Ok(r) => r.passed
			Err(_) => Bool.False
		}

	# Test 2: without worker_envs -> test should fail
	config_no_env = {
		max_workers: 1,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True, # Suppress output for expected failures
		fail_fast: Bool.False,
	}

	results_no_env = Spec.run!(effects, "tests/env_fixtures", config_no_env)?

	failed_without_env =
		match results_no_env.first() {
			Ok(r) => !r.passed
			Err(_) => Bool.False
		}

	# Test 3: with max_workers:2, verify both workers get different indices
	config_multi = {
		max_workers: 2,
		worker_envs: with_worker_id,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results_multi = Spec.run!(effects, "tests/env_fixtures", config_multi)?

	all_multi_passed = results_multi.all(|r| r.passed)
	indices = results_multi.map(
		|r|
			match r.output.split_first("Worker ID: ") {
				Ok({ before: _, after }) => after.trim()
				Err(_) => "parse_error"
			},
	)
	has_index_0 = indices.contains("0")
	has_index_1 = indices.contains("1")
	indices_correct = has_index_0 and has_index_1 and indices.len() == 2

	if passed_with_env and failed_without_env and all_multi_passed and indices_correct {
		Stdout.line!("PASS: worker_envs behavior verified")
	} else if !passed_with_env {
		Stdout.line!("FAIL: Test should pass when worker_envs sets TEST_WORKER_ID")?
		Err(ShouldHavePassed)
	} else if !failed_without_env {
		Stdout.line!("FAIL: Test should fail when TEST_WORKER_ID is not set")?
		Err(ShouldHaveFailed)
	} else if !all_multi_passed {
		Stdout.line!("FAIL: Tests should pass with 2 workers")?
		Err(MultiWorkerFailed)
	} else {
		Stdout.line!("FAIL: worker indices incorrect. Indices: ${Str.inspect(indices)}")?
		Err(IndicesWrong)
	}
}
