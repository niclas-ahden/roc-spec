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

# Test: Another server is already running on the same port
# Expected: Server.with! returns ServerCrashed because our server crashed,
#           even though HTTP responded (from the other server)
#
# Strategy: Use nested Server.with! calls. The outer one starts a server on
# port 8000, then the inner one tries the same port, causing a conflict.
main! = |_args| {
	# Outer server starts on port 8000 (default)
	outer_result = Server.with_timeout!(
		server_effects,
		working_server_cmd(),
		{ max_attempts: 50, delay_ms: 200 },
		|_outer_base_url| {
			# Inner server tries same port - should fail with port conflict
			inner_result = Server.with!(
				server_effects,
				working_server_cmd(),
				|_inner_base_url| {
					# This callback should never run - inner server should crash
					Stdout.line!("FAIL: Inner callback ran but the inner server should crash")?
					Err(CallbackShouldNotRun)
				},
			)

			match inner_result {
				Err(ServerCrashed({ stderr, exit_code: _ })) =>
				# Verify stderr contains port binding error
				# (node reports EADDRINUSE; other servers say "Address already in use")
					if stderr.contains("EADDRINUSE") or stderr.contains("Address already in use") or stderr.contains("address already in use") or stderr.contains("error binding") {
						Ok(PortConflictDetected)
					} else {
						Stdout.line!("FAIL: ServerCrashed but stderr doesn't contain expected port error")?
						Stdout.line!("stderr: ${stderr}")?
						Err(WrongStderr)
					}

				Err(ServerNotReady(_)) => {
					Stdout.line!("FAIL: Got ServerNotReady instead of ServerCrashed")?
					Err(WrongError)
				}

				Err(e) => {
					Stdout.line!("FAIL: Got unexpected error: ${Str.inspect(e)}")?
					Err(UnexpectedError)
				}

				Ok(_) => {
					Stdout.line!("FAIL: Inner Server.with! should have detected the port conflict")?
					Err(ShouldHaveFailed)
				}
			}
		},
	)

	match outer_result {
		Ok(PortConflictDetected) =>
			Stdout.line!("PASS: Port conflict detected with correct error message")

		Err(e) => {
			Stdout.line!("FAIL: Outer server failed: ${Str.inspect(e)}")?
			Err(OuterServerFailed)
		}

		Ok(_) => {
			Stdout.line!("FAIL: Unexpected Ok value")?
			Err(UnexpectedOk)
		}
	}
}
