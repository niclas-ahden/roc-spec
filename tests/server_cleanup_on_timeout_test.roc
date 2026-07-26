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

# Test: Server process is killed even when wait times out (ServerNotReady)
# Expected: After Server.with_timeout! returns ServerNotReady, the port should be free
#           and the slow_start_server process should be killed
#
# Strategy: Run Server.with_timeout! with slow_start_server (never becomes HTTP ready),
# then immediately try to spawn a working server on the same port. If cleanup worked,
# the second server should start successfully.
main! = |_args| {
	# First call - times out waiting for HTTP ready
	result1 = Server.with_timeout!(
		server_effects,
		Cmd.new("tests/server_fixtures/slow_start_server"),
		{ max_attempts: 3, delay_ms: 100 }, # Quick timeout
		|_base_url| {
			# This callback should never run
			Stdout.line!("FAIL: Callback ran but server should never become ready")?
			Err(CallbackShouldNotRun)
		},
	)

	# Verify first call returned ServerNotReady
	match result1 {
		Err(ServerNotReady(_)) => {
			# Good - now verify cleanup by starting a working server on same port
			Sleep.millis!(100)

			result2 = Server.with_timeout!(
				server_effects,
				working_server_cmd(),
				{ max_attempts: 50, delay_ms: 200 },
				|base_url|
				# If we get here, cleanup worked - the slow_start_server was killed
					match Http.get_utf8!(Url.parse(base_url) ? InvalidUrl) {
						Ok(body) =>
							if body == "OK" {
								Ok(SecondServerWorked)
							} else {
								Err(UnexpectedResponse)
							}

						Err(_) =>
							Err(HttpFailed)
						},
			)

			match result2 {
				Ok(SecondServerWorked) =>
					Stdout.line!("PASS: Cleanup on timeout verified - slow_start_server was killed")

				Err(ServerCrashed({ stderr, exit_code: _ })) => {
					# If port still in use, slow_start_server wasn't killed
					Stdout.line!("FAIL: Second server crashed - slow_start_server still running (cleanup failed)")?
					Stdout.line!("stderr: ${stderr}")?
					Err(CleanupFailed)
				}

				Err(ServerNotReady(_)) => {
					Stdout.line!("FAIL: Second server not ready")?
					Err(SecondServerNotReady)
				}

				Err(e) => {
					Stdout.line!("FAIL: Second server failed: ${Str.inspect(e)}")?
					Err(SecondServerFailed)
				}
			}
		}

		Err(ServerCrashed(_)) => {
			Stdout.line!("FAIL: First call returned ServerCrashed instead of ServerNotReady")?
			Err(WrongFirstError)
		}

		Err(e) => {
			Stdout.line!("FAIL: First call should have returned ServerNotReady, got: ${Str.inspect(e)}")?
			Err(WrongFirstError)
		}

		Ok(_) => {
			Stdout.line!("FAIL: First call should have timed out")?
			Err(ShouldHaveTimedOut)
		}
	}
}
