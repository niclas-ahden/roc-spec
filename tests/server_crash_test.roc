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

# Test: Server crashes before becoming HTTP ready
# Expected: Server.with! returns ServerCrashed error with stderr output
main! = |_args| {
	result = Server.with!(
		Effects.server,
		Cmd.new("tests/server_fixtures/crash_server"),
		|_base_url| {
			# This callback should never be called since server crashes
			Stdout.line!("FAIL: Callback was called but server should have crashed")?
			Err(CallbackShouldNotRun)
		},
	)

	match result {
		Err(ServerCrashed({ status, stderr })) =>
		# Verify the server did not exit cleanly (crashed)
			if status == Exited(0) {
				Stdout.line!("FAIL: ServerCrashed but the exit code is 0")?
				Err(WrongExitCode)
			} else if stderr.contains("CRASH: Server failed to start") {
				Stdout.line!("PASS: Server crash detected with correct stderr and status ${Str.inspect(status)}")
			} else {
				Stdout.line!("FAIL: ServerCrashed but stderr doesn't contain expected message")?
				Stdout.line!("Got stderr: ${stderr}")?
				Err(WrongStderr)
			}

		Err(ServerNotReady(_)) => {
			Stdout.line!("FAIL: Got ServerNotReady instead of ServerCrashed")?
			Err(WrongError)
		}

		Err(_) => {
			Stdout.line!("FAIL: Got unexpected error")?
			Err(UnexpectedError)
		}

		Ok(_) => {
			Stdout.line!("FAIL: Server.with! should have returned an error")?
			Err(ShouldHaveFailed)
		}
	}
}
