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

# Test: Another server is already running on the same port
# Expected: Server.with! returns ServerCrashed because our server crashed,
#           even though HTTP responded (from the other server)
#
# Strategy: Use nested Server.with! calls. The outer one starts a server on
# port 8000, then the inner one tries the same port, causing a conflict.
main! : List Arg.Arg => Result {} _
main! = |_args|
    # Outer server starts on port 8000 (default)
    outer_result = Server.with_timeout!(
        Cmd.new("tests/server_fixtures/working_server"),
        { max_attempts: 50, delay_ms: 200 },
        |_outer_base_url|
            # Inner server tries same port - should fail with port conflict
            inner_result = Server.with!(
                Cmd.new("tests/server_fixtures/working_server"),
                |_inner_base_url|
                    # This callback should never run - inner server should crash
                    Err(CallbackShouldNotRun),
            )

            when inner_result is
                Err(ServerCrashed({ stderr })) ->
                    # Verify stderr contains port binding error
                    if Str.contains(stderr, "Address already in use") || Str.contains(stderr, "error binding") then
                        Ok(PortConflictDetected)
                    else
                        Stdout.line!("FAIL: ServerCrashed but stderr doesn't contain expected port error")?
                        Stdout.line!("stderr: ${stderr}")?
                        Err(WrongStderr)

                Err(ServerNotReady(_)) ->
                    Stdout.line!("FAIL: Got ServerNotReady instead of ServerCrashed")?
                    Err(WrongError)

                Err(ServerSpawnFailed(e)) ->
                    Stdout.line!("FAIL: Got ServerSpawnFailed: ${Inspect.to_str(e)}")?
                    Err(WrongError)

                Err(e) ->
                    Stdout.line!("FAIL: Got unexpected error: ${Inspect.to_str(e)}")?
                    Err(UnexpectedError)

                Ok({}) ->
                    Stdout.line!("FAIL: Inner Server.with! should have detected the port conflict")?
                    Err(ShouldHaveFailed),
    )

    when outer_result is
        Ok(PortConflictDetected) ->
            Stdout.line!("PASS: Port conflict detected with correct error message")

        Err(e) ->
            Stdout.line!("FAIL: Outer server failed: ${Inspect.to_str(e)}")?
            Err(OuterServerFailed)

        Ok(_) ->
            Stdout.line!("FAIL: Unexpected Ok value")?
            Err(UnexpectedOk)
