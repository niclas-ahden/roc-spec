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

now_ms! : {} => U64
now_ms! = |{}| Utc.to_millis_since_epoch(Utc.now!()).to_u64_wrap()

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

run_with_workers! = |max_workers| {
	config = {
		max_workers,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	start = now_ms!({})
	results = Spec.run!(effects, "tests/parallel_fixtures", config)?
	end = now_ms!({})

	Ok({
		count: results.len(),
		ms: end.minus_saturated(start),
		all_passed: results.all(|r| r.passed),
	})
}

main! = |_args| {
	# 6 tests each sleeping 200ms
	# Test three scenarios:
	# 1. Sequential (1 worker)
	# 2. Rolling window (2 workers < 6 tests) - exercises queuing
	# 3. Full parallel (6 workers >= 6 tests) - all at once

	# Run sequential
	Stdout.line!("Running with max_workers: 1 (sequential)...")?
	seq = run_with_workers!(1)?
	Stdout.line!("  Took ${seq.ms.to_str()}ms")?

	# Run with rolling window (workers < tests)
	Stdout.line!("Running with max_workers: 2 (rolling window)...")?
	rolling = run_with_workers!(2)?
	Stdout.line!("  Took ${rolling.ms.to_str()}ms")?

	# Run full parallel (workers >= tests)
	Stdout.line!("Running with max_workers: 6 (full parallel)...")?
	full = run_with_workers!(6)?
	Stdout.line!("  Took ${full.ms.to_str()}ms")?

	# Verify counts
	if seq.count != 6 {
		Stdout.line!("FAIL: Sequential expected 6 results, got ${seq.count.to_str()}")?
		Err(WrongSequentialCount)
	} else if rolling.count != 6 {
		Stdout.line!("FAIL: Rolling expected 6 results, got ${rolling.count.to_str()}")?
		Err(WrongRollingCount)
	} else if full.count != 6 {
		Stdout.line!("FAIL: Full parallel expected 6 results, got ${full.count.to_str()}")?
		Err(WrongFullCount)
		# Verify all passed
	} else if !seq.all_passed {
		Stdout.line!("FAIL: Not all sequential tests passed")?
		Err(SequentialTestsFailed)
	} else if !rolling.all_passed {
		Stdout.line!("FAIL: Not all rolling window tests passed")?
		Err(RollingTestsFailed)
	} else if !full.all_passed {
		Stdout.line!("FAIL: Not all full parallel tests passed")?
		Err(FullTestsFailed)
		# Verify timing: sequential > rolling > full
	} else if rolling.ms >= seq.ms {
		Stdout.line!("FAIL: Rolling (${rolling.ms.to_str()}ms) should be faster than sequential (${seq.ms.to_str()}ms)")?
		Err(RollingNotFaster)
	} else if full.ms >= rolling.ms {
		Stdout.line!("FAIL: Full parallel (${full.ms.to_str()}ms) should be faster than rolling (${rolling.ms.to_str()}ms)")?
		Err(FullNotFaster)
	} else {
		Stdout.line!("PASS: Parallel execution works (seq:${seq.ms.to_str()}ms > rolling:${rolling.ms.to_str()}ms > full:${full.ms.to_str()}ms)")
	}
}
