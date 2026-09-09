## The platform effects every test in this directory hands to `Spec` and
## `Server`, built once from basic-cli so the tests do not each carry a copy.
##
## Both streams are captured: `Spec` and `Server` report a child's output from
## what `try_wait!` and `wait!` hand back, and `spawn_leashed!` inherits the
## streams unless told otherwise.
import pf.Cmd
import pf.Env
import pf.Http
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stdout
import pf.Url
import pf.Utc

Effects :: [].{
	## For `Spec.run!`: one test file per process, compiled with `--opt=speed`.
	spec = {
		spawn_test!: |file, envs|
			Cmd.new(OsStr.utf8("roc"))
				.args_str(["--opt=speed", file])
				.envs_str(envs)
				.stdout(Capture)
				.stderr(Capture)
				.spawn_leashed!(),
		try_wait!: Cmd.Child.try_wait!,
		kill!: Cmd.Child.kill!,
		wait!: Cmd.Child.wait!,
		list_dir!: |dir| Path.list!(Path.utf8(dir)).map_ok(|entries| entries.map(Path.display)),
		print!: Stdout.line!,
		utc_now!: Utc.now!,
		sleep_millis!: Sleep.millis!,
	}

	## For `Server.with!`: a server on the port the worker convention assigns.
	server = {
		env_var!: Env.var_str!,
		# Written with `->` rather than method calls: `cmd` is a lambda
		# parameter, so its type is only known at the call site, and the
		# interpreter crashes dispatching a method on it from inside a module.
		spawn_server!: |cmd, port|
			cmd
				->Cmd.env_str("PORT", port)
				->Cmd.env_str("ROC_BASIC_WEBSERVER_PORT", port)
				->Cmd.stdout(Capture)
				->Cmd.stderr(Capture)
				->Cmd.spawn_leashed!(),
		close!: Cmd.Child.close!,
		try_wait!: Cmd.Child.try_wait!,
		http_get!: |url| Http.get_utf8!(Url.parse(url) ? InvalidUrl),
		sleep!: Sleep.millis!,
	}
}
