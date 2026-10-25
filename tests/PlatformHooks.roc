## The `PlatformHooks` every test in this directory hands to `Spec`, `Server`,
## `Wait` and `TestEnvironment`: basic-cli's own functions, passed as they are.
import pf.Cmd
import pf.Env
import pf.Http
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stdout
import pf.Utc

PlatformHooks :: [].{
	basic_cli = {
		new: Cmd.new,
		os_str: OsStr.from_str,
		spawn!: Cmd.Command.spawn_leashed!,
		poll!: Cmd.Child.poll!,
		wait!: Cmd.Child.wait!,
		kill!: Cmd.Child.kill!,
		close!: Cmd.Child.close!,
		path: Path.utf8,
		list!: Path.list!,
		print!: Stdout.line!,
		now!: Utc.now!,
		sleep!: Sleep.millis!,
		env_var!: Env.var_str!,
		http_send!: Http.send!,
		send_options: Http.SendOptions.{},
	}
}
