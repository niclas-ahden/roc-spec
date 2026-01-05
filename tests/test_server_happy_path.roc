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

# Test: Server starts successfully, callback runs, result returned
# Expected: Callback is called with correct base_url, callback result is returned
main! : List Arg.Arg => Result {} _
main! = |_args|
    # Use a unique port to avoid conflicts with other tests
    result = Server.with_timeout!(
        Cmd.new("tests/server_fixtures/working_server"),
        { max_attempts: 50, delay_ms: 200 },
        |base_url|
            # Verify base_url has correct format
            if !(Str.starts_with(base_url, "http://localhost:")) then
                Stdout.line!("FAIL: base_url doesn't start with http://localhost:")?
                Err(WrongBaseUrl)
            else
                # Make a request to verify server is responding
                when Http.get_utf8!(base_url) is
                    Ok(body) ->
                        if body == "OK" then
                            # Return a specific value to verify it's propagated
                            Ok(CallbackSucceeded)
                        else if Str.starts_with(body, "ERROR:") then
                            Stdout.line!("FAIL: Server returned error: ${body}")?
                            Err(ServerReturnedError)
                        else
                            Stdout.line!("FAIL: Unexpected response: ${body}")?
                            Err(UnexpectedResponse)

                    Err(e) ->
                        Stdout.line!("FAIL: HTTP request failed: ${Inspect.to_str(e)}")?
                        Err(HttpRequestFailed),
    )

    when result is
        Ok(CallbackSucceeded) ->
            Stdout.line!("PASS: Happy path - server started, callback ran, result returned")

        Ok(_) ->
            Stdout.line!("FAIL: Got Ok but wrong value")?
            Err(WrongResult)

        Err(ServerCrashed({ stderr })) ->
            Stdout.line!("FAIL: Server crashed unexpectedly")?
            Stdout.line!("stderr: ${stderr}")?
            Err(UnexpectedCrash)

        Err(ServerNotReady(url)) ->
            Stdout.line!("FAIL: Server not ready at ${url}")?
            Err(ServerNotReadyError)

        Err(ServerSpawnFailed(e)) ->
            Stdout.line!("FAIL: Server spawn failed: ${Inspect.to_str(e)}")?
            Err(SpawnFailed)

        Err(e) ->
            Stdout.line!("FAIL: Unexpected error: ${Inspect.to_str(e)}")?
            Err(UnexpectedError)
