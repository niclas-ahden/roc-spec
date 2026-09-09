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

# Test: Server command doesn't exist
# Expected: Server.with! returns ServerSpawnFailed
main! = |_args| {
	result = Server.with!(
		Effects.server,
		Cmd.new("tests/server_fixtures/nonexistent_server_that_does_not_exist"),
		|_base_url| {
			# This callback should never run
			Stdout.line!("FAIL: Callback was called for a nonexistent command")?
			Err(CallbackShouldNotRun)
		},
	)

	match result {
		Err(ServerSpawnFailed(_)) =>
			Stdout.line!("PASS: ServerSpawnFailed returned for nonexistent command")

		Err(ServerCrashed(_)) => {
			Stdout.line!("FAIL: Got ServerCrashed instead of ServerSpawnFailed")?
			Err(WrongError)
		}

		Err(ServerNotReady(_)) => {
			Stdout.line!("FAIL: Got ServerNotReady instead of ServerSpawnFailed")?
			Err(WrongError)
		}

		Err(e) => {
			Stdout.line!("FAIL: Got unexpected error: ${Str.inspect(e)}")?
			Err(UnexpectedError)
		}

		Ok(_) => {
			Stdout.line!("FAIL: Should have returned ServerSpawnFailed")?
			Err(ShouldHaveFailed)
		}
	}
}
