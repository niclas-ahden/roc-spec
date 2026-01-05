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

# Test: Server is killed even when callback fails
# Expected: After Server.with! returns (with callback error), the port should be free
#
# Strategy: Run Server.with! with a failing callback, then immediately try to
# spawn another server on the same port. If cleanup worked, the second server
# should start successfully.
main! : List Arg.Arg => Result {} _
main! = |_args|
    # First call - callback fails
    result1 = Server.with_timeout!(
        Cmd.new("tests/server_fixtures/working_server"),
        { max_attempts: 50, delay_ms: 200 },
        |_base_url|
            Err(IntentionalCallbackError),
    )

    # Verify first call returned our error
    when result1 is
        Err(IntentionalCallbackError) ->
            # Good - now verify cleanup by starting another server on same port
            # Small delay to ensure cleanup completed
            Sleep.millis!(100)

            result2 = Server.with_timeout!(
                Cmd.new("tests/server_fixtures/working_server"),
                { max_attempts: 50, delay_ms: 200 },
                |base_url|
                    # If we get here, cleanup worked - the port was free
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
                    Stdout.line!("PASS: Cleanup verified - second server started on same port")

                Err(ServerCrashed({ stderr })) ->
                    Stdout.line!("FAIL: Second server crashed - port still in use (cleanup failed)")?
                    Stdout.line!("stderr: ${stderr}")?
                    Err(CleanupFailed)

                Err(ServerNotReady(_)) ->
                    Stdout.line!("FAIL: Second server not ready")?
                    Err(SecondServerNotReady)

                Err(e) ->
                    Stdout.line!("FAIL: Second server failed: ${Inspect.to_str(e)}")?
                    Err(SecondServerFailed)

        Err(e) ->
            Stdout.line!("FAIL: First call should have returned IntentionalCallbackError, got: ${Inspect.to_str(e)}")?
            Err(WrongFirstError)

        Ok(_) ->
            Stdout.line!("FAIL: First call should have failed")?
            Err(ShouldHaveFailed)
