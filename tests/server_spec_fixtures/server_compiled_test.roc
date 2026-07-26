## Fixture for tests/server_under_spec_test.roc: `Server.with!` in a COMPILED
## app, since `Spec.run!` spawns every test with `roc --opt=speed`.
##
## The bare `kill!: Cmd.Child.kill!` and `env_var!: Env.var_str!` references
## below are deliberate. They are the regression coverage for two fixed
## compiler bugs: roc-lang/roc#10370 (effect reordering in the optimizing
## backend, which ran the kill at spawn time and left the readiness poll
## waiting on a dead server) and roc-lang/roc#10321 (string literals not
## coerced through first-class calls to functions taking OsStr).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
	spec: "../../package/main.roc",
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

server_cmd = || Cmd.new("node").args_str(["tests/server_fixtures/working_server.mjs"])

main! = |_args| {
	result = Server.with_timeout!(
		server_effects,
		server_cmd(),
		{ max_attempts: 50, delay_ms: 200 },
		|base_url|
			match Http.get_utf8!(Url.parse(base_url) ? InvalidUrl) {
				Ok("OK") => Ok({})
				Ok(body) => {
					Stdout.line!("FAIL: Unexpected response: ${body}")?
					Err(UnexpectedResponse)
				}

				Err(e) => {
					Stdout.line!("FAIL: HTTP request failed: ${Str.inspect(e)}")?
					Err(HttpRequestFailed)
				}
			},
	)

	match result {
		Ok({}) => Stdout.line!("PASS: Server.with! worked through Spec.run!")

		Err(e) => {
			Stdout.line!("FAIL: ${Str.inspect(e)}")?
			Err(ServerFailed)
		}
	}
}
