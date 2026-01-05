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

# Test: Server crashes before becoming HTTP ready
# Expected: Server.with! returns ServerCrashed error with stderr output
main! : List Arg.Arg => Result {} _
main! = |_args|
    result = Server.with!(
        Cmd.new("tests/server_fixtures/crash_server"),
        |_base_url|
            # This callback should never be called since server crashes
            Stdout.line!("FAIL: Callback was called but server should have crashed")?
            Err(CallbackShouldNotRun),
    )

    when result is
        Err(ServerCrashed({ exit_code, stderr })) ->
            # Verify exit_code is non-zero (crashed)
            if exit_code == 0 then
                Stdout.line!("FAIL: ServerCrashed but exit_code is 0")?
                Err(WrongExitCode)
            else if Str.contains(stderr, "CRASH: Server failed to start") then
                Stdout.line!("PASS: Server crash detected with correct stderr and non-zero exit_code (${Num.to_str(exit_code)})")
            else
                Stdout.line!("FAIL: ServerCrashed but stderr doesn't contain expected message")?
                Stdout.line!("Got stderr: ${stderr}")?
                Err(WrongStderr)

        Err(ServerNotReady(_)) ->
            Stdout.line!("FAIL: Got ServerNotReady instead of ServerCrashed")?
            Err(WrongError)

        Err(ServerSpawnFailed(_)) ->
            Stdout.line!("FAIL: Got ServerSpawnFailed instead of ServerCrashed")?
            Err(WrongError)

        Err(_) ->
            Stdout.line!("FAIL: Got unexpected error")?
            Err(UnexpectedError)

        Ok({}) ->
            Stdout.line!("FAIL: Server.with! should have returned an error")?
            Err(ShouldHaveFailed)
