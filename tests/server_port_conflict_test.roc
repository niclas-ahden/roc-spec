app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst",
	spec: "../package/main.roc",
}

import pf.Cmd
import pf.Stdout
import spec.Server
import Effects

# The working server fixture is a node script (there is no basic-webserver
# platform for the new compiler yet).
working_server_cmd = || Cmd.new("node").args_str(["tests/server_fixtures/working_server.mjs"])

# The same server, but it waits before binding, so it is still alive and
# still silent for a while after it is spawned.
slow_bind_server_cmd = || Cmd.new("node").args_str(["tests/server_fixtures/slow_bind_server.mjs"])

# Start a server on a port that is already taken, and expect Server.with! to
# report the conflict rather than the answer the other server gives.
expect_port_conflict! = |cmd, label| {
	inner_result = Server.with!(
		Effects.server,
		cmd,
		|_inner_base_url| {
			# This callback should never run - inner server should crash
			Stdout.line!("FAIL: ${label}: inner callback ran but the inner server should crash")?
			Err(CallbackShouldNotRun)
		},
	)

	match inner_result {
		Err(ServerCrashed({ stderr, status: _ })) =>
		# Verify stderr contains port binding error
		# (node reports EADDRINUSE; other servers say "Address already in use")
			if stderr.contains("EADDRINUSE") or stderr.contains("Address already in use") or stderr.contains("address already in use") or stderr.contains("error binding") {
				Ok({})
			} else {
				Stdout.line!("FAIL: ${label}: ServerCrashed but stderr doesn't contain expected port error")?
				Stdout.line!("stderr: ${stderr}")?
				Err(WrongStderr)
			}

		Err(ServerNotReady(_)) => {
			Stdout.line!("FAIL: ${label}: got ServerNotReady instead of ServerCrashed")?
			Err(WrongError)
		}

		Err(e) => {
			Stdout.line!("FAIL: ${label}: got unexpected error: ${Str.inspect(e)}")?
			Err(UnexpectedError)
		}

		Ok(_) => {
			Stdout.line!("FAIL: ${label}: Server.with! should have detected the port conflict")?
			Err(ShouldHaveFailed)
		}
	}
}

# Test: Another server is already running on the same port
# Expected: Server.with! returns ServerCrashed because our server crashed,
#           even though HTTP responded (from the other server)
#
# Strategy: Use nested Server.with! calls. The outer one starts a server on
# port 8000, then the inner one tries the same port, causing a conflict.
#
# Twice over, because how long the inner server takes to reach its `listen`
# call is what makes this hard: a server that conflicts immediately is caught
# by any guard, while one that takes a moment slips past a guard that only
# waits a polling interval.
main! = |_args| {
	# Outer server starts on port 8000 (default)
	outer_result = Server.with_timeout!(
		Effects.server,
		working_server_cmd(),
		{ max_attempts: 50, delay_ms: 200 },
		|_outer_base_url| {
			expect_port_conflict!(working_server_cmd(), "immediate bind")?
			expect_port_conflict!(slow_bind_server_cmd(), "delayed bind")?

			Ok(PortConflictDetected)
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
