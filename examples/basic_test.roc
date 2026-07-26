## A fuller example: parallel workers, worker-specific env vars, a
## before_each! hook, and filtered runs.
##
## Run from the repository root:
## ```
## roc examples/basic_test.roc
## ```
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
import spec.Assert
import spec.Spec

# Place this in a helper module which you import in all tests:
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

config = {
	max_workers: 2.U16,
	worker_envs: |index| [("ROC_SPEC_EXAMPLE_WORKER", index.to_str())],
	before_each!: |_index| Ok({}),
	per_test_timeout_ms: 120_000.U64,
	quiet: Bool.False,
	fail_fast: Bool.False,
}

main! = |_args| {
	# Run every *_test.roc file under examples/tests on 2 parallel workers
	Stdout.line!("--- All tests")?
	results = Spec.run!(effects, "examples/tests", config)?

	passed = results.count_if(|r| r.passed)
	total = results.len()
	Stdout.line!("${passed.to_str()}/${total.to_str()} tests passed")?

	Assert.eq(total, 2) ? |e| UnexpectedTestCount(e)
	Assert.eq(passed, total) ? |e| SomeTestsFailed(e)

	# Run only the tests whose filename contains "math"
	Stdout.line!("--- Filtered: math")?
	filtered = Spec.run_filtered!(effects, "examples/tests", config, "math")?

	Assert.eq(filtered.len(), 1) ? |e| UnexpectedFilteredCount(e)
	names = filtered.map(|r| r.name)
	Assert.contains(names, "math_test") ? |e| UnexpectedFilteredName(e)

	Stdout.line!("basic example OK")
}
