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

# Test: Server process runs but never becomes HTTP ready
# Expected: Server.with_timeout! returns ServerNotReady after timeout
#
# Uses a short timeout (5 attempts × 200ms = 1 second) to keep the test fast.
# The slow_start_server just sleeps and never binds to a port.
main! : List Arg.Arg => Result {} _
main! = |_args|
    # Use a unique port to avoid conflicts
    # Note: We can't change the port Server.with_timeout! uses via env here,
    # since the test process would need PORT set. But slow_start_server
    # doesn't bind to any port anyway, so it doesn't matter.
    result = Server.with_timeout!(
        Cmd.new("tests/server_fixtures/slow_start_server"),
        { max_attempts: 5, delay_ms: 200 },
        |_base_url|
            # This callback should never run - server never becomes ready
            Err(CallbackShouldNotRun),
    )

    when result is
        Err(ServerNotReady(_)) ->
            Stdout.line!("PASS: ServerNotReady returned for non-HTTP server")

        Err(ServerCrashed(_)) ->
            Stdout.line!("FAIL: Got ServerCrashed instead of ServerNotReady")?
            Err(WrongError)

        Err(ServerSpawnFailed(e)) ->
            Stdout.line!("FAIL: Got ServerSpawnFailed: ${Inspect.to_str(e)}")?
            Err(WrongError)

        Err(_) ->
            Stdout.line!("FAIL: Got unexpected error")?
            Err(UnexpectedError)

        Ok({}) ->
            Stdout.line!("FAIL: Should have timed out waiting for HTTP")?
            Err(ShouldHaveTimedOut)
