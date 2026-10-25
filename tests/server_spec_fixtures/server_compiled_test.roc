## Fixture for tests/server_under_spec_test.roc: `Server.with!` in a COMPILED
## app, since `Spec.run!` spawns every test with `roc --opt=speed`.
##
## The bare `close!: Cmd.Child.close!` and `env_var!: Env.var_str!` hooks below
## are deliberate. They are the regression coverage for two fixed
## compiler bugs: roc-lang/roc#10370 (effect reordering in the optimizing
## backend, which ran the kill at spawn time and left the readiness poll
## waiting on a dead server) and roc-lang/roc#10321 (string literals not
## coerced through first-class calls to functions taking OsStr).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
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

hooks = {
	os_str: OsStr.from_str,
	spawn!: Cmd.Command.spawn_leashed!,
	poll!: Cmd.Child.poll!,
	close!: Cmd.Child.close!,
	env_var!: Env.var_str!,
	# WORKAROUND: a lambda rather than `Http.send!` itself, because roc-spec
	# passing a bare `{}` as its `SendOptions` crashes Roc 54283d4. Pass
	# `Http.send!` once roc-lang/roc#12606 is fixed.
	http_send!: |request| Http.send!(request, {}),
	sleep!: Sleep.millis!,
}

server_cmd = || Cmd.new("node").args(["tests/server_fixtures/working_server.mjs"])

main! = |_args| {
	result = Server.with_timeout!(
		hooks,
		server_cmd(),
		{ max_attempts: 50, delay_ms: 200 },
		|base_url|
			match Http.get_utf8!(Url.parse(base_url) ? InvalidUrl, {}) {
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
