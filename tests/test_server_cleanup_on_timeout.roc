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

# Test: Server process is killed even when wait times out (ServerNotReady)
# Expected: After Server.with_timeout! returns ServerNotReady, the port should be free
#           and the slow_start_server process should be killed
#
# Strategy: Run Server.with_timeout! with slow_start_server (never becomes HTTP ready),
# then immediately try to spawn a working server on the same port. If cleanup worked,
# the second server should start successfully.
main! : List Arg.Arg => Result {} _
main! = |_args|
    # First call - times out waiting for HTTP ready
    result1 = Server.with_timeout!(
        Cmd.new("tests/server_fixtures/slow_start_server"),
        { max_attempts: 3, delay_ms: 100 },  # Quick timeout
        |_base_url|
            # This callback should never run
            Err(CallbackShouldNotRun),
    )

    # Verify first call returned ServerNotReady
    when result1 is
        Err(ServerNotReady(_)) ->
            # Good - now verify cleanup by starting a working server on same port
            Sleep.millis!(100)

            result2 = Server.with_timeout!(
                Cmd.new("tests/server_fixtures/working_server"),
                { max_attempts: 50, delay_ms: 200 },
                |base_url|
                    # If we get here, cleanup worked - the slow_start_server was killed
                    when Http.get_utf8!(base_url) is
                        Ok(body) ->
                            if body == "OK" then
                                Ok(SecondServerWorked)
                            else if Str.starts_with(body, "ERROR:") then
                                Err(SecondServerError)
                            else
                                Err(UnexpectedResponse)

                        Err(_) ->
                            Err(HttpFailed),
            )

            when result2 is
                Ok(SecondServerWorked) ->
                    Stdout.line!("PASS: Cleanup on timeout verified - slow_start_server was killed")

                Err(ServerCrashed({ stderr })) ->
                    # If port still in use, slow_start_server wasn't killed
                    Stdout.line!("FAIL: Second server crashed - slow_start_server still running (cleanup failed)")?
                    Stdout.line!("stderr: ${stderr}")?
                    Err(CleanupFailed)

                Err(ServerNotReady(_)) ->
                    Stdout.line!("FAIL: Second server not ready")?
                    Err(SecondServerNotReady)

                Err(e) ->
                    Stdout.line!("FAIL: Second server failed: ${Inspect.to_str(e)}")?
                    Err(SecondServerFailed)

        Err(ServerCrashed(_)) ->
            Stdout.line!("FAIL: First call returned ServerCrashed instead of ServerNotReady")?
            Err(WrongFirstError)

        Err(e) ->
            Stdout.line!("FAIL: First call should have returned ServerNotReady, got: ${Inspect.to_str(e)}")?
            Err(WrongFirstError)

        Ok(_) ->
            Stdout.line!("FAIL: First call should have timed out")?
            Err(ShouldHaveTimedOut)
