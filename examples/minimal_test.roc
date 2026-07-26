## Minimal example: run all test files in examples/tests with a single worker.
##
## Run from the repository root:
## ```
## roc examples/minimal_test.roc
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

main! = |_args| {
	results = Spec.run!(
		effects,
		"examples/tests",
		{
			max_workers: 1,
			worker_envs: |index| [("ROC_SPEC_EXAMPLE_WORKER", index.to_str())],
			before_each!: |_index| Ok({}),
			per_test_timeout_ms: 120_000,
			quiet: Bool.True,
			fail_fast: Bool.False,
		},
	)?

	passed = results.count_if(|r| r.passed)
	total = results.len()

	Stdout.line!("${passed.to_str()}/${total.to_str()} tests passed")?

	if passed == total {
		Ok({})
	} else {
		Err(TestsFailed)
	}
}
