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

# Test: Server starts successfully, callback runs, result returned
# Expected: Callback is called with correct base_url, callback result is returned
main! = |_args| {
	result = Server.with_timeout!(
		server_effects,
		working_server_cmd(),
		{ max_attempts: 50, delay_ms: 200 },
		|base_url|
		# Verify base_url has correct format
			if !base_url.starts_with("http://localhost:") {
				Stdout.line!("FAIL: base_url doesn't start with http://localhost:")?
				Err(WrongBaseUrl)
			} else {
				# Make a request to verify server is responding
				match Http.get_utf8!(Url.parse(base_url) ? InvalidUrl) {
					Ok(body) =>
						if body == "OK" {
							# Return a specific value to verify it's propagated
							Ok(CallbackSucceeded)
						} else {
							Stdout.line!("FAIL: Unexpected response: ${body}")?
							Err(UnexpectedResponse)
						}

					Err(e) => {
						Stdout.line!("FAIL: HTTP request failed: ${Str.inspect(e)}")?
						Err(HttpRequestFailed)
					}
				}
			},
	)

	match result {
		Ok(CallbackSucceeded) =>
			Stdout.line!("PASS: Happy path - server started, callback ran, result returned")

		Ok(_) => {
			Stdout.line!("FAIL: Got Ok but wrong value")?
			Err(WrongResult)
		}

		Err(ServerCrashed({ stderr, exit_code: _ })) => {
			Stdout.line!("FAIL: Server crashed unexpectedly")?
			Stdout.line!("stderr: ${stderr}")?
			Err(UnexpectedCrash)
		}

		Err(ServerNotReady(url)) => {
			Stdout.line!("FAIL: Server not ready at ${url}")?
			Err(ServerNotReadyError)
		}

		Err(e) => {
			Stdout.line!("FAIL: Unexpected error: ${Str.inspect(e)}")?
			Err(UnexpectedError)
		}
	}
}
