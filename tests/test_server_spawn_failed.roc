app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.25.0/2Qj7ggHJdVV9jAspIjvskp_cUWvAyh7B9I-Ma_sY4zk.tar.br",
    spec: "../package/main.roc",
}

import pf.Arg
import pf.Stdout
import pf.Cmd
import pf.Env
import pf.Http
import pf.Sleep

import spec.Server {
    env_var!: Env.var!,
    cmd_env: Cmd.env,
    cmd_spawn_grouped!: Cmd.spawn_grouped!,
    http_get!: Http.get_utf8!,
    sleep!: Sleep.millis!,
}

# Test: Server command doesn't exist
# Expected: Server.with! returns ServerSpawnFailed
main! : List Arg.Arg => Result {} _
main! = |_args|
    result = Server.with!(
        Cmd.new("tests/server_fixtures/nonexistent_server_that_does_not_exist"),
        |_base_url|
            # This callback should never run
            Err(CallbackShouldNotRun),
    )

    when result is
        Err(ServerSpawnFailed(_)) ->
            Stdout.line!("PASS: ServerSpawnFailed returned for nonexistent command")

        Err(ServerCrashed(_)) ->
            Stdout.line!("FAIL: Got ServerCrashed instead of ServerSpawnFailed")?
            Err(WrongError)

        Err(ServerNotReady(_)) ->
            Stdout.line!("FAIL: Got ServerNotReady instead of ServerSpawnFailed")?
            Err(WrongError)

        Err(e) ->
            Stdout.line!("FAIL: Got unexpected error: ${Inspect.to_str(e)}")?
            Err(UnexpectedError)

        Ok(_) ->
            Stdout.line!("FAIL: Should have returned ServerSpawnFailed")?
            Err(ShouldHaveFailed)
