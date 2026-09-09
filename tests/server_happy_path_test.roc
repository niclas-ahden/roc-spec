app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst",
	spec: "../package/main.roc",
}

import pf.Cmd
import pf.Http
import pf.Url
import pf.Stdout
import spec.Server
import Effects

# The working server fixture is a node script (there is no basic-webserver
# platform for the new compiler yet).
working_server_cmd = || Cmd.new("node").args_str(["tests/server_fixtures/working_server.mjs"])

# Test: Server starts successfully, callback runs, result returned
# Expected: Callback is called with correct base_url, callback result is returned
main! = |_args| {
	result = Server.with_timeout!(
		Effects.server,
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

		Err(ServerCrashed({ stderr, status: _ })) => {
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
