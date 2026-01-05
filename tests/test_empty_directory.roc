app [main!] {
    pf: platform "../../growthagent/basic-cli/platform/main.roc",
    spec: "../package/main.roc",
}

import pf.Arg
import pf.Stdout
import pf.Cmd
import pf.Dir
import pf.Path
import pf.Utc
import pf.Sleep

dir_list! : Str => Result (List Str) _
dir_list! = |path|
    Dir.list!(path)
    |> Result.map_ok(|paths| List.map(paths, Path.display))

utc_now! : {} => I128
utc_now! = |{}|
    Utc.now!({}) |> Utc.to_millis_since_epoch

no_envs : U64 -> List (Str, Str)
no_envs = |_index| []

import spec.Spec {
    cmd_new: Cmd.new,
    cmd_args: Cmd.args,
    cmd_envs: Cmd.envs,
    cmd_spawn_grouped!: Cmd.spawn_grouped!,
    stdout_line!: Stdout.line!,
    dir_list!: dir_list!,
    utc_now!: utc_now!,
    sleep_millis!: Sleep.millis!,
}

main! : List Arg.Arg => Result {} _
main! = |_args|
    config = {
        max_workers: 4,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    # Run on empty directory
    results = Spec.run!("tests/empty_fixtures", config)?

    if List.is_empty(results) then
        Stdout.line!("PASS: Empty directory returns empty results list")
    else
        Stdout.line!("FAIL: Expected empty results, got $(Num.to_str(List.len(results))) results")?
        Err(ExpectedEmptyResults)
