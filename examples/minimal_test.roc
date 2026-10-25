## Minimal example: run all test files in examples/tests with a single worker.
##
## Run from the repository root:
## ```
## roc examples/minimal_test.roc
## ```
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	spec: "../package/main.roc",
}

import pf.Cmd
import pf.Env
import pf.Http
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stdout
import pf.Utc
import spec.Spec

# basic-cli's own functions, passed as they are. Place this in a helper module
# which you import in all tests:
hooks = {
	new: Cmd.new,
	os_str: OsStr.from_str,
	spawn!: Cmd.Command.spawn_leashed!,
	poll!: Cmd.Child.poll!,
	wait!: Cmd.Child.wait!,
	kill!: Cmd.Child.kill!,
	close!: Cmd.Child.close!,
	path: Path.utf8,
	list!: Path.list!,
	print!: Stdout.line!,
	now!: Utc.now!,
	sleep!: Sleep.millis!,
	env_var!: Env.var_str!,
	http_send!: Http.send!,
	send_options: Http.SendOptions.{},
}

main! = |_args| {
	results = Spec.run!(
		hooks,
		"examples/tests",
		{
			test_command: ["roc", "--opt=speed"],
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
