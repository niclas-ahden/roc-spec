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

run_with_workers! : U16 => Result { count : U64, ms : I128, all_passed : Bool } _
run_with_workers! = |max_workers|
    config = {
        max_workers,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    start = utc_now!({})
    results = Spec.run!("tests/parallel_fixtures", config)?
    end = utc_now!({})

    Ok({
        count: List.len(results),
        ms: end - start,
        all_passed: List.all(results, |r| r.passed),
    })

main! : List Arg.Arg => Result {} _
main! = |_args|
    # 6 tests each sleeping 200ms
    # Test three scenarios:
    # 1. Sequential (1 worker): ~1200ms
    # 2. Rolling window (2 workers < 6 tests): ~600ms (exercises queuing)
    # 3. Full parallel (6 workers >= 6 tests): ~200ms (all at once)

    # Run sequential
    Stdout.line!("Running with max_workers: 1 (sequential)...")?
    seq = run_with_workers!(1)?
    Stdout.line!("  Took $(Num.to_str(seq.ms))ms")?

    # Run with rolling window (workers < tests)
    Stdout.line!("Running with max_workers: 2 (rolling window)...")?
    rolling = run_with_workers!(2)?
    Stdout.line!("  Took $(Num.to_str(rolling.ms))ms")?

    # Run full parallel (workers >= tests)
    Stdout.line!("Running with max_workers: 6 (full parallel)...")?
    full = run_with_workers!(6)?
    Stdout.line!("  Took $(Num.to_str(full.ms))ms")?

    # Verify counts
    if seq.count != 6 then
        Stdout.line!("FAIL: Sequential expected 6 results, got $(Num.to_str(seq.count))")?
        Err(WrongSequentialCount)
    else if rolling.count != 6 then
        Stdout.line!("FAIL: Rolling expected 6 results, got $(Num.to_str(rolling.count))")?
        Err(WrongRollingCount)
    else if full.count != 6 then
        Stdout.line!("FAIL: Full parallel expected 6 results, got $(Num.to_str(full.count))")?
        Err(WrongFullCount)
    # Verify all passed
    else if !seq.all_passed then
        Stdout.line!("FAIL: Not all sequential tests passed")?
        Err(SequentialTestsFailed)
    else if !rolling.all_passed then
        Stdout.line!("FAIL: Not all rolling window tests passed")?
        Err(RollingTestsFailed)
    else if !full.all_passed then
        Stdout.line!("FAIL: Not all full parallel tests passed")?
        Err(FullTestsFailed)
    # Verify timing: sequential > rolling > full
    else if rolling.ms >= seq.ms then
        Stdout.line!("FAIL: Rolling ($(Num.to_str(rolling.ms))ms) should be faster than sequential ($(Num.to_str(seq.ms))ms)")?
        Err(RollingNotFaster)
    else if full.ms >= rolling.ms then
        Stdout.line!("FAIL: Full parallel ($(Num.to_str(full.ms))ms) should be faster than rolling ($(Num.to_str(rolling.ms))ms)")?
        Err(FullNotFaster)
    else
        seq_to_rolling = ((seq.ms - rolling.ms) * 100) // seq.ms
        rolling_to_full = ((rolling.ms - full.ms) * 100) // rolling.ms
        Stdout.line!("PASS: seq $(Num.to_str(seq.ms))ms > rolling $(Num.to_str(rolling.ms))ms (-$(Num.to_str(seq_to_rolling))%) > full $(Num.to_str(full.ms))ms (-$(Num.to_str(rolling_to_full))%)")
