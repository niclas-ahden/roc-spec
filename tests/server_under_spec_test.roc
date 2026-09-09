app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst",
	spec: "../package/main.roc",
}

import pf.Stdout
import spec.Spec
import Effects

## The other server tests run `Server.with!` directly, so they only ever
## exercise it interpreted. This one goes through `Spec.run!`, which spawns
## the fixture with `roc --opt=speed`, and is therefore the only coverage of
## `Server.with!` in a compiled app. That combination used to hit
## roc-lang/roc#10370 (effects stored as bare record-field references ran at
## spawn time), so the fixture passes `close!` as a bare reference on purpose.
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

	results = Spec.run!(Effects.spec, "tests/server_spec_fixtures", config)?

	match results.first() {
		Ok(result) =>
			if result.passed {
				Stdout.line!("PASS: Server.with! works compiled with close! as a bare reference")
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
