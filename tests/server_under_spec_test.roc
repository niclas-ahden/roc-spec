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

## The other server tests run `Server.with!` directly, so they only ever
## exercise it interpreted. This one goes through `Spec.run!`, which spawns
## the fixture with `roc --opt=speed`, and is therefore the only coverage of
## `Server.with!` in a compiled app. That combination used to hit
## roc-lang/roc#10370 (effects stored as bare record-field references ran at
## spawn time), so the fixture passes `kill!` as a bare reference on purpose.
main! = |_args| {
	# One fixture, so one worker. The port comes from the worker convention:
	# worker 0 gets 9100.
	config = {
		max_workers: 1,
		worker_envs: |index| [
			("WORKER_INDEX", index.to_str()),
			("ROC_SPEC_BASE_PORT", "9100"),
		],
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 60_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	results = Spec.run!(effects, "tests/server_spec_fixtures", config)?

	match results.first() {
		Ok(result) =>
			if result.passed {
				Stdout.line!("PASS: Server.with! works compiled with kill! as a bare reference")
			} else {
				Stdout.line!("FAIL: The server spec failed (has roc-lang/roc#10370 regressed?):")?
				Stdout.line!(result.output)?
				Stdout.line!(result.error)?
				Err(ServerSpecFailed)
			}

		Err(_) => {
			Stdout.line!("FAIL: No test was discovered in tests/server_spec_fixtures")?
			Err(NoResults)
		}
	}
}
