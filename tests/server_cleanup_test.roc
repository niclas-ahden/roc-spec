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

# Test: Server is killed even when callback fails
# Expected: After Server.with! returns (with callback error), the port should be free
#
# Strategy: Run Server.with! with a failing callback, then immediately try to
# spawn another server on the same port. If cleanup worked, the second server
# should start successfully.
main! = |_args| {
	# First call - callback fails
	result1 = Server.with_timeout!(
		server_effects,
		working_server_cmd(),
		{ max_attempts: 50, delay_ms: 200 },
		|_base_url| {
			Stdout.line!("first server up; failing callback on purpose")?
			Err(IntentionalCallbackError)
		},
	)

	# Verify first call returned our error
	match result1 {
		Err(IntentionalCallbackError) => {
			# Good - now verify cleanup by starting another server on same port
			# Small delay to ensure cleanup completed
			Sleep.millis!(100)

			result2 = Server.with_timeout!(
				server_effects,
				working_server_cmd(),
				{ max_attempts: 50, delay_ms: 200 },
				|base_url|
				# If we get here, cleanup worked - the port was free
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
					Stdout.line!("PASS: Cleanup verified - second server started on same port")

				Err(ServerCrashed({ stderr, exit_code: _ })) => {
					Stdout.line!("FAIL: Second server crashed - port still in use (cleanup failed)")?
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

		Err(e) => {
			Stdout.line!("FAIL: First call should have returned IntentionalCallbackError, got: ${Str.inspect(e)}")?
			Err(WrongFirstError)
		}

		Ok(_) => {
			Stdout.line!("FAIL: First call should have failed")?
			Err(ShouldHaveFailed)
		}
	}
}
