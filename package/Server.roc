## Server lifecycle management for integration tests.
##
## Provides helpers to spawn a server process, wait for it to be ready,
## run tests, and clean up - all in a single `with!` block.
##
## Example:
## ```roc
## import spec.Server { ... }
##
## main! = |_|
##     Server.with!(Cmd.new("./my-server"), |base_url|
##         # Server is running and ready
##         body = Http.get_utf8!("$(base_url)/health")?
##         Assert.eq(body, "ok")
##     )
## ```
module { env_var!, cmd_env, cmd_spawn_grouped!, http_get!, sleep! } -> [with!, with_timeout!]

## Run a test with a server. Spawns the server process, waits for it to be
## ready, provides the base_url to the callback, and kills the server when done.
##
## The server port is read from the PORT environment variable (default: 8000).
##
## ```roc
## Server.with!(Cmd.new("roc") |> Cmd.args(["dev", "server.roc"]), |base_url|
##     # base_url = "http://localhost:8000" (or whatever PORT is set to)
##     content = Http.get_utf8!("$(base_url)/api/users")?
##     Assert.contains(content, "alice")?
##     Ok({})
## )
## ```
with! = |cmd, callback!|
    with_timeout!(cmd, { max_attempts: 150, delay_ms: 200 }, callback!)

## Run a test with a server, with custom timeout settings.
##
## Like `with!`, but allows configuring the timeout parameters.
##
## ```roc
## # Quick timeout for testing slow-start scenarios (5 attempts × 200ms = 1 second)
## Server.with_timeout!(Cmd.new("./my-server"), { max_attempts: 5, delay_ms: 200 }, |base_url|
##     # ...
## )
## ```
with_timeout! = |cmd, { max_attempts, delay_ms }, callback!|
    # Get port from environment (default 8000)
    port =
        when env_var!("PORT") is
            Ok(p) -> p
            Err(_) -> "8000"

    base_url = "http://localhost:${port}"

    # Spawn server with both PORT and ROC_BASIC_WEBSERVER_PORT env vars
    # (different platforms use different env vars)
    # Use spawn_grouped! so the server is killed when parent exits (even via SIGKILL)
    spawn_result =
        cmd
        |> cmd_env("PORT", port)
        |> cmd_env("ROC_BASIC_WEBSERVER_PORT", port)
        |> cmd_spawn_grouped!()

    when spawn_result is
        Ok({ kill!, poll! }) ->
            # Wait for server to be ready
            wait_result = wait_for_server!(base_url, max_attempts, delay_ms, poll!)

            # Run callback only if server is ready
            result =
                when wait_result is
                    Ok({}) -> callback!(base_url)
                    Err(e) -> Err(e)

            # Always kill the server, even if wait or callback failed
            _ = kill!({})

            result

        Err(e) ->
            Err(ServerSpawnFailed(e))

## Wait for server to be ready by polling the base URL
wait_for_server! = |url, max_attempts, delay_ms, poll!|
    wait_for_server_helper!(url, max_attempts, delay_ms, 0, poll!)

wait_for_server_helper! = |url, max_attempts, delay_ms, attempt, poll!|
    if attempt >= max_attempts then
        Err(ServerNotReady(url))
    else
        # Check if the server process crashed
        poll_result = poll!({})
        when poll_result is
            Ok(Exited({ exit_code, stderr })) ->
                stderr_str = Str.from_utf8_lossy(stderr)
                Err(ServerCrashed({ exit_code, stderr: stderr_str }))

            Ok(Running) ->
                # Server is still running, check if it's ready via HTTP
                when http_get!(url) is
                    Ok(body) ->
                        # Http.get_utf8! returns Ok "ERROR:..." on connection errors
                        if Str.starts_with(body, "ERROR:") then
                            sleep!(delay_ms)
                            wait_for_server_helper!(url, max_attempts, delay_ms, attempt + 1, poll!)
                        else
                            # Got a valid response - but check poll one more time to ensure
                            # it's from OUR server (not a leftover process on the same port)
                            # Wait a bit for the server to fully start (or crash)
                            sleep!(200)
                            when poll!({}) is
                                Ok(Running) -> Ok({})
                                Ok(Exited({ exit_code, stderr: err_bytes })) ->
                                    Err(ServerCrashed({ exit_code, stderr: Str.from_utf8_lossy(err_bytes) }))
                                # Poll failed but HTTP worked and first poll showed Running.
                                # This is likely a platform edge case, not a real problem.
                                Err(_) -> Ok({})

                    Err(_) ->
                        sleep!(delay_ms)
                        wait_for_server_helper!(url, max_attempts, delay_ms, attempt + 1, poll!)

            Err(_poll_err) ->
                # Couldn't poll, fall back to http-only check
                when http_get!(url) is
                    Ok(body) ->
                        if Str.starts_with(body, "ERROR:") then
                            sleep!(delay_ms)
                            wait_for_server_helper!(url, max_attempts, delay_ms, attempt + 1, poll!)
                        else
                            Ok({})

                    Err(_) ->
                        sleep!(delay_ms)
                        wait_for_server_helper!(url, max_attempts, delay_ms, attempt + 1, poll!)
