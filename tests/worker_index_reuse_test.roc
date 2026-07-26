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

# Pass worker index as env var
with_worker_index = |index| [("WORKER_INDEX", index.to_str())]

main! = |_args| {
	# Run 4 tests with only 2 workers
	# This means worker indices 0 and 1 must each be reused at least once
	config = {
		max_workers: 2,
		worker_envs: with_worker_index,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results = Spec.run!(effects, "tests/worker_reuse_fixtures", config)?

	if results.len() != 4 {
		Stdout.line!("FAIL: Expected 4 test results, got ${results.len().to_str()}")?
		Err(WrongResultCount)
	} else {
		# Extract worker indices from each test's output
		indices = results.map(
			|r|
			# Parse "WORKER_INDEX=N" from output
				match r.output.split_first("WORKER_INDEX=") {
					Ok({ before: _, after }) => after.trim()
					Err(_) => "parse_error"
				},
		)

		# Count how many times each index appears
		count_0 = indices.count_if(|i| i == "0")
		count_1 = indices.count_if(|i| i == "1")

		# With 4 tests and 2 workers, each index should be used at least twice
		# (indices should be reused when workers become free)
		all_passed = results.all(|r| r.passed)
		index_0_reused = count_0 >= 2
		index_1_reused = count_1 >= 2
		total_correct = count_0 + count_1 == 4

		if all_passed and index_0_reused and index_1_reused and total_correct {
			Stdout.line!("PASS: Worker indices correctly reused (0 used ${count_0.to_str()}x, 1 used ${count_1.to_str()}x)")
		} else if !all_passed {
			Stdout.line!("FAIL: Not all tests passed")?
			Err(TestsFailed)
		} else {
			Stdout.line!("FAIL: Worker indices not reused correctly (0:${count_0.to_str()}, 1:${count_1.to_str()}, indices:${Str.inspect(indices)})")?
			Err(IndicesNotReused)
		}
	}
}
