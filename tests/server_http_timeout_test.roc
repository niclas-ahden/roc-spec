app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
	spec: "../package/main.roc",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Http
import pf.Url
import pf.Sleep
import pf.Stdout
import spec.Server

server_effects = {
	env_var!: Env.var_str!,
	spawn_server!: |cmd, port|
		cmd
			->Cmd.env_str("PORT", port)
			->Cmd.env_str("ROC_BASIC_WEBSERVER_PORT", port)
			->Cmd.spawn_grouped!(),
	kill!: Cmd.Child.kill!,
	poll!: Cmd.Child.poll!,
	http_get!: |url| Http.get_utf8!(Url.parse(url) ? InvalidUrl),
	sleep!: Sleep.millis!,
}

# The working server fixture is a node script (there is no basic-webserver
# platform for the new compiler yet).
working_server_cmd = || Cmd.new("node").args_str(["tests/server_fixtures/working_server.mjs"])

# Test: Server process runs but never becomes HTTP ready
# Expected: Server.with_timeout! returns ServerNotReady after timeout
#
# Uses a short timeout (5 attempts x 200ms = 1 second) to keep the test fast.
# The slow_start_server just sleeps and never binds to a port.
main! = |_args| {
	result = Server.with_timeout!(
		server_effects,
		Cmd.new("tests/server_fixtures/slow_start_server"),
		{ max_attempts: 5, delay_ms: 200 },
		|_base_url| {
			# This callback should never run - server never becomes ready
			Stdout.line!("FAIL: Callback was called but server never becomes ready")?
			Err(CallbackShouldNotRun)
		},
	)

	match result {
		Err(ServerNotReady(_)) =>
			Stdout.line!("PASS: ServerNotReady returned for non-HTTP server")

		Err(ServerCrashed(_)) => {
			Stdout.line!("FAIL: Got ServerCrashed instead of ServerNotReady")?
			Err(WrongError)
		}

		Err(ServerSpawnFailed(e)) => {
			Stdout.line!("FAIL: Got ServerSpawnFailed: ${Str.inspect(e)}")?
			Err(WrongError)
		}

		Err(_) => {
			Stdout.line!("FAIL: Got unexpected error")?
			Err(UnexpectedError)
		}

		Ok(_) => {
			Stdout.line!("FAIL: Should have timed out waiting for HTTP")?
			Err(ShouldHaveTimedOut)
		}
	}
}
