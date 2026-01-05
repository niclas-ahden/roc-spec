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

with_worker_id : U64 -> List (Str, Str)
with_worker_id = |index| [("TEST_WORKER_ID", Num.to_str(index))]

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
    # Test 1: with worker_envs -> test should pass
    config_with_env = {
        max_workers: 1,
        worker_envs: with_worker_id,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results_with_env = Spec.run!("tests/env_fixtures", config_with_env)?

    passed_with_env =
        when List.first(results_with_env) is
            Ok(r) -> r.passed
            Err(_) -> Bool.false

    # Test 2: without worker_envs -> test should fail
    config_no_env = {
        max_workers: 1,
        worker_envs: no_envs,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true, # Suppress output for expected failures
    }

    results_no_env = Spec.run!("tests/env_fixtures", config_no_env)?

    failed_without_env =
        when List.first(results_no_env) is
            Ok(r) -> !r.passed
            Err(_) -> Bool.false

    # Test 3: with max_workers:2, verify both workers get different indices
    config_multi = {
        max_workers: 2,
        worker_envs: with_worker_id,
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 30_000,
        quiet: Bool.true,
    }

    results_multi = Spec.run!("tests/env_fixtures", config_multi)?

    # Both tests should pass and each should have a DIFFERENT worker ID
    all_passed = List.all(results_multi, |r| r.passed)

    # Parse worker IDs from each test's output
    # Format is "Worker ID: N"
    worker_ids = List.map(results_multi, |r|
        when Str.split_first(r.output, "Worker ID: ") is
            Ok({ after }) -> Str.trim(after)
            Err(_) -> "parse_error"
    )

    # Verify we have exactly 2 results with different worker IDs
    has_two_results = List.len(results_multi) == 2

    # Check that we have both 0 and 1 (not just "some output contains 0")
    has_id_0 = List.contains(worker_ids, "0")
    has_id_1 = List.contains(worker_ids, "1")
    ids_are_0_and_1 = has_id_0 && has_id_1

    if passed_with_env && failed_without_env && all_passed && has_two_results && ids_are_0_and_1 then
        Stdout.line!("PASS: worker_envs correctly passed to tests (single and multi-worker, IDs: $(Inspect.to_str(worker_ids)))")
    else if !passed_with_env then
        Stdout.line!("FAIL: Test should pass when worker_envs provides TEST_WORKER_ID")?
        Err(ShouldHavePassed)
    else if !failed_without_env then
        Stdout.line!("FAIL: Test should fail when worker_envs doesn't provide TEST_WORKER_ID")?
        Err(ShouldHaveFailed)
    else if !all_passed then
        Stdout.line!("FAIL: All tests should pass with max_workers:2")?
        Err(MultiWorkerFailed)
    else if !has_two_results then
        Stdout.line!("FAIL: Expected 2 test results, got $(Num.to_str(List.len(results_multi)))")?
        Err(WrongResultCount)
    else
        Stdout.line!("FAIL: Expected worker IDs [0, 1], got $(Inspect.to_str(worker_ids))")?
        Err(WorkerIndicesWrong)
