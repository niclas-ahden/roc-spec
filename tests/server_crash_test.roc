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

# Test: Server crashes before becoming HTTP ready
# Expected: Server.with! returns ServerCrashed error with stderr output
main! = |_args| {
	result = Server.with!(
		server_effects,
		Cmd.new("tests/server_fixtures/crash_server"),
		|_base_url| {
			# This callback should never be called since server crashes
			Stdout.line!("FAIL: Callback was called but server should have crashed")?
			Err(CallbackShouldNotRun)
		},
	)

	match result {
		Err(ServerCrashed({ exit_code, stderr })) =>
		# Verify exit_code is non-zero (crashed)
			if exit_code == 0 {
				Stdout.line!("FAIL: ServerCrashed but exit_code is 0")?
				Err(WrongExitCode)
			} else if stderr.contains("CRASH: Server failed to start") {
				Stdout.line!("PASS: Server crash detected with correct stderr and non-zero exit_code (${exit_code.to_str()})")
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
