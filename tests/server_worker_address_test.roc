app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
	spec: "../package/main.roc",
}

import pf.Stdout
import spec.Server

# Every effect is stubbed, so this pins the address `Server` derives without
# spawning anything: `spawn_server!` hands back a fake child that `poll!` and
# `kill!` accept, and `http_get!` reports ready on the first probe.
stub_effects = |env| {
	env_var!: env,
	spawn_server!: |_cmd, port| Ok(FakeChild(port)),
	kill!: |_child| Ok({}),
	poll!: |_child| Ok(Running),
	http_get!: |_url| Ok("ready"),
	sleep!: |_millis| {},
}

# The worker environment a runner sets up: worker 2 of a run based at 9300,
# answering to a hostname that is not localhost.
worker_env = |name|
	match name {
		"ROC_SPEC_BASE_PORT" => Ok("9300")
		"WORKER_INDEX" => Ok("2")
		"ROC_SPEC_HOST" => Ok("example.test")
		_ => Err(VarNotFound)
	}

# No runner: the sequential case reads PORT.
sequential_env = |name|
	match name {
		"PORT" => Ok("8123")
		_ => Err(VarNotFound)
	}

# Neither convention set.
bare_env = |_name| Err(VarNotFound)

run! = |env| Server.with_timeout!(stub_effects(env), FakeCmd, { max_attempts: 1, delay_ms: 1 }, |base_url| Ok(base_url))

# Test: the address comes from the worker convention, falling back to PORT
# Expected: worker index shifts the base port, ROC_SPEC_HOST sets the host,
# and a run with no runner takes its port from PORT
main! = |_args| {
	checks = [
		("worker convention", run!(worker_env), "http://example.test:9302"),
		("PORT fallback", run!(sequential_env), "http://localhost:8123"),
		("no configuration", run!(bare_env), "http://localhost:8000"),
	]

	failures = checks.keep_if(|(_name, actual, expected)| actual != Ok(expected))

	_ = failures.map_try!(
		|(name, actual, expected)| {
			Stdout.line!("FAIL: ${name} gave ${Str.inspect(actual)}, expected ${expected}")
		},
	)?

	if failures.is_empty() {
		Stdout.line!("PASS: Server address follows the worker convention")
	} else {
		Err(WrongAddress)
	}
}
