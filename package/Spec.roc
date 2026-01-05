## A Roc package for writing and running parallel tests with isolated test environments.
## Includes hooks for setup/teardown and utilities like database helpers, waiting for
## web servers to start etc.
##
## ## Quick start
## ```roc
## Spec.run!("tests", {
##     max_workers: 4,
##     worker_envs: |index| [("DATABASE_NAME", "test_$(Num.to_str(index))")],
##     before_each!: |_| Ok({}),
##     per_test_timeout_ms: 60_000,
## })
## ```
##
## ## Features
## - Parallel execution with rolling window of workers
## - Worker isolation via environment variables
## - Before-each hooks (e.g., truncate database)
## - Per-test timeouts
## - Recursive test file discovery
## - Pattern-based filtering
##
## ## Test file format
## Each test file should be a standalone Roc application that exits with code 0 on success
## and non-zero on failure. The test name is derived from the filename.
module { cmd_new, cmd_args, cmd_envs, cmd_spawn_grouped!, stdout_line!, dir_list!, utc_now!, sleep_millis! } -> [
    TestResult,
    Config,
    run!,
    run_filtered!,
]

import Format exposing [format_duration, indent_lines, green_check, red_x]

get_basename : Str -> Str
get_basename = |path|
    when Str.split_last(path, "/") is
        Ok({ after }) -> after
        Err(_) -> path

extract_test_name : Str -> Str
extract_test_name = |file|
    # Strip .roc suffix and first path component (test_dir)
    # e.g., "tests/fill/nested/test_foo.roc" -> "fill/nested/test_foo"
    without_extension = Str.replace_last(file, ".roc", "")
    when Str.split_first(without_extension, "/") is
        Ok({ after }) -> after
        Err(_) -> without_extension

## Result of a single test.
##
## - `name`: Test name derived from filename (e.g., `test_login` from `test_login.roc`)
## - `passed`: Whether the test exited with code 0
## - `duration_ms`: How long the test took to run
## - `output`: Captured stdout from the test process
## - `error`: Captured stderr from the test process
TestResult : {
    name : Str,
    passed : Bool,
    duration_ms : I128,
    output : Str,
    error : Str,
}

## Configuration for parallel test execution.
##
## - `max_workers`: Maximum number of tests to run concurrently
## - `worker_envs`: Function that returns environment variables for a given worker index
## - `before_each!`: Hook called before each test (e.g., to truncate database)
## - `per_test_timeout_ms`: Timeout for each individual test in milliseconds
## - `quiet`: When true, only show stdout/stderr for failed tests; when false, show for all tests
##
## Example:
## ```roc
## {
##     max_workers: 32,
##     worker_envs: |index| [
##         ("APP_PORT", Num.to_str(8000 + index)),
##         ("DATABASE_NAME", "test_$(Num.to_str(index))"),
##     ],
##     before_each!: |index| Pg.truncate!(query!, db, []),
##     per_test_timeout_ms: 120_000,
##     quiet: Bool.false,
## }
## ```
Config err : {
    max_workers : U16,
    worker_envs : U64 -> List (Str, Str),
    before_each! : U64 => Result {} err,
    per_test_timeout_ms : U64,
    quiet : Bool,
}

## Run all `test_*.roc` files in the given directory and subdirectories in parallel.
##
## Returns a list of test results, one for each test file discovered and run.
## See `run_filtered!` to run a subset of tests by name pattern.
run! : Str, Config err => Result (List TestResult) _
run! = |test_dir, config|
    run_filtered!(test_dir, config, "")

## Run tests matching a pattern.
##
## The pattern is a simple substring match on the filename:
## - `""` (empty string): run all tests
## - `"login"`: matches `test_login.roc`, `test_login_flow.roc`, etc.
## - `"api"`: matches `test_api_auth.roc`, `test_user_api.roc`, etc.
##
## Recursively searches all subdirectories for test files.
run_filtered! : Str, Config err, Str => Result (List TestResult) _
run_filtered! = |test_dir, config, pattern|
    # Find test files recursively in all subdirectories
    test_files = find_test_files_recursive!(test_dir, pattern, [])

    if List.is_empty(test_files) then
        Ok([])
    else
        run_with_rolling_window!(test_files, config)

## Recursively find all test files matching the pattern in a directory and its subdirectories.
find_test_files_recursive! = |dir, pattern, acc|
    when dir_list!(dir) is
        Err(_) ->
            # Not a directory or can't read it, return accumulated files
            acc

        Ok(entries) ->
            process_directory_entries!(entries, pattern, acc)

## Process directory entries, collecting test files and recursing into subdirectories.
process_directory_entries! = |entries, pattern, acc|
    when entries is
        [] -> acc
        [entry, .. as rest] ->
            basename = get_basename(entry)

            # Check if this entry is a test file
            is_test_file = Str.starts_with(basename, "test_") && Str.ends_with(basename, ".roc")
            matches_pattern = if Str.is_empty(pattern) then Bool.true else Str.contains(basename, pattern)

            # Add to results if it's a matching test file
            with_file =
                if is_test_file && matches_pattern then
                    List.append(acc, entry)
                else
                    acc

            # Try to recurse into this entry as a potential subdirectory
            # (dir_list! will fail for files, which is handled gracefully)
            with_subdir = find_test_files_recursive!(entry, pattern, with_file)

            # Continue processing remaining entries
            process_directory_entries!(rest, pattern, with_subdir)

## Rolling window scheduler - spawns replacement tests as others complete.
run_with_rolling_window! = |test_files, config|
    max_workers = Num.to_u64(config.max_workers)

    # Split into initial batch and remaining tests
    { before: initial_files, others: remaining_files } = List.split_at(test_files, max_workers)

    # Spawn initial batch (up to max_workers)
    initial_spawned = spawn_batch_with_indices!(initial_files, config, 0)

    # Process tests: poll for completion, process finished ones, spawn new ones as slots free up
    process_rolling_window!(initial_spawned, remaining_files, config, max_workers, [])

## Process spawned tests by polling for completion.
## Tests are processed in completion order (whichever finishes first), not spawn order.
process_rolling_window! = |spawned_queue, pending_files, config, max_workers, results|
    when spawned_queue is
        [] ->
            # No more spawned tests, we're done
            Ok(results)

        _ ->
            # First, handle any AlreadyFailed tests immediately
            { failed, running } = partition_failed(spawned_queue)

            when failed is
                [first_failed, .. as other_failed] ->
                    # Process the failed test
                    { name, worker_index, passed, duration_ms, output, error } =
                        when first_failed is
                            AlreadyFailed(f) -> f
                            Spawned(_) -> crash "unreachable"

                    test_result = { name, passed, duration_ms, output, error }

                    # Spawn replacement if any pending
                    { new_spawned, new_pending } = spawn_replacement!(running, other_failed, pending_files, worker_index, config)

                    # Continue processing
                    process_rolling_window!(new_spawned, new_pending, config, max_workers, List.append(results, test_result))

                [] ->
                    # No failed tests, poll running tests for completion
                    poll_for_completion!(running, pending_files, config, max_workers, results)

## Poll all running tests and process whichever finishes first.
poll_for_completion! = |running, pending_files, config, max_workers, results|
    when find_completed!(running) is
        Found({ completed, worker_index, poll_result, remaining }) ->
            # Process the completed test
            test_result = process_poll_result!(completed, poll_result, config.quiet)

            # Spawn replacement if any pending
            { new_spawned, new_pending } = spawn_replacement!(remaining, [], pending_files, worker_index, config)

            # Continue processing
            process_rolling_window!(new_spawned, new_pending, config, max_workers, List.append(results, test_result))

        NoneCompleted ->
            # No test finished yet, sleep briefly and try again
            sleep_millis!(10)
            poll_for_completion!(running, pending_files, config, max_workers, results)

## Partition spawned tests into AlreadyFailed and Spawned (running)
partition_failed = |spawned_queue|
    List.walk(
        spawned_queue,
        { failed: [], running: [] },
        |acc, item|
            when item is
                AlreadyFailed(_) -> { acc & failed: List.append(acc.failed, item) }
                Spawned(_) -> { acc & running: List.append(acc.running, item) },
    )

## Poll all running tests to find one that completed.
find_completed! = |running|
    find_completed_helper!(running, [])

find_completed_helper! = |remaining, checked|
    when remaining is
        [] ->
            NoneCompleted

        [Spawned(spawned), .. as rest] ->
            { name, worker_index, child, start_time } = spawned
            poll_result = child.poll!({})

            when poll_result is
                Ok(Exited({ exit_code, stdout, stderr })) ->
                    Found({
                        completed: { name, start_time },
                        worker_index,
                        poll_result: Ok({ stdout, stderr, exit_code }),
                        remaining: List.concat(checked, List.map(rest, |r| r)),
                    })

                Ok(Running) ->
                    # Not finished yet, keep looking
                    find_completed_helper!(rest, List.append(checked, Spawned(spawned)))

                Err(_) ->
                    # Error polling, skip
                    find_completed_helper!(rest, List.append(checked, Spawned(spawned)))

        [AlreadyFailed(_), ..] ->
            crash "unreachable: AlreadyFailed should be partitioned out"

## Process a poll result into a TestResult.
process_poll_result! = |{ name, start_time }, poll_result, quiet|
    end_time = utc_now!({})
    duration_ms = end_time - start_time

    when poll_result is
        Ok({ stdout, stderr, exit_code }) ->
            stdout_str = Str.from_utf8(stdout) |> Result.with_default("")
            stderr_str = Str.from_utf8(stderr) |> Result.with_default("")

            if exit_code == 0 then
                _ = stdout_line!("$(green_check) $(name) ($(format_duration(duration_ms)))")
                _ =
                    if !quiet then
                        print_output!(stdout_str, stderr_str)
                    else
                        Ok({})
                {
                    name,
                    passed: Bool.true,
                    duration_ms,
                    output: stdout_str,
                    error: stderr_str,
                }
            else if exit_code == 124 then
                # Exit code 124 = timeout command killed the process
                _ = stdout_line!("$(red_x) $(name) (TIMEOUT after $(format_duration(duration_ms)))")
                _ = print_output!(stdout_str, stderr_str)
                {
                    name,
                    passed: Bool.false,
                    duration_ms,
                    output: stdout_str,
                    error: "Test timed out",
                }
            else
                _ = stdout_line!("$(red_x) $(name) ($(format_duration(duration_ms)))")
                _ = print_output!(stdout_str, stderr_str)
                {
                    name,
                    passed: Bool.false,
                    duration_ms,
                    output: stdout_str,
                    error: stderr_str,
                }

        Err(_) ->
            _ = stdout_line!("$(red_x) $(name) (failed to run)")
            {
                name,
                passed: Bool.false,
                duration_ms,
                output: "",
                error: "Failed to poll process",
            }

## Print captured stdout/stderr with indentation
print_output! = |stdout_str, stderr_str|
    _ =
        if !Str.is_empty(stdout_str) then
            stdout_line!(indent_lines(stdout_str))
        else
            Ok({})
    if !Str.is_empty(stderr_str) then
        stdout_line!(indent_lines(stderr_str))
    else
        Ok({})

## Spawn a replacement test if there are pending files.
spawn_replacement! = |running, other_failed, pending_files, freed_worker_index, config|
    when pending_files is
        [] ->
            # No more pending tests
            { new_spawned: List.concat(running, other_failed), new_pending: [] }

        [next_file, .. as other_pending] ->
            # Spawn next test using the freed worker index
            next_spawned = spawn_one!(next_file, freed_worker_index, config)
            # Add to the running queue
            { new_spawned: List.concat(List.concat(running, other_failed), [next_spawned]), new_pending: other_pending }

## Spawn a batch of tests with sequential worker indices starting from start_index.
spawn_batch_with_indices! = |test_files, config, start_index|
    indexed = List.map_with_index(test_files, |file, i| (file, start_index + i))
    spawn_batch_helper!(indexed, config, [])

spawn_batch_helper! = |remaining, config, acc|
    when remaining is
        [] -> acc
        [(file, worker_index), .. as rest] ->
            result = spawn_one!(file, worker_index, config)
            spawn_batch_helper!(rest, config, List.append(acc, result))

spawn_one! = |file, worker_index, config|
    name = extract_test_name(file)

    # Run before_each hook (e.g., truncate database)
    when config.before_each!(worker_index) is
        Err(_) ->
            # Note: Can't use Inspect.to_str(e) here due to compiler bug with
            # polymorphic error types from module param callbacks
            _ = stdout_line!("$(red_x) $(name) (before_each failed)")
            AlreadyFailed({
                name,
                worker_index,
                passed: Bool.false,
                duration_ms: 0,
                output: "",
                error: "before_each! failed: can't give more context due compiler limitations",
            })

        Ok({}) ->
            start_time = utc_now!({})
            envs = config.worker_envs(worker_index)
            timeout_secs = config.per_test_timeout_ms // 1000
            spawn_result =
                cmd_new("timeout")
                |> cmd_args([Num.to_str(timeout_secs), "roc", "dev", "--linker", "legacy", file])
                |> cmd_envs(envs)
                |> cmd_spawn_grouped!()

            when spawn_result is
                Ok(child) ->
                    Spawned({ name, worker_index, child, start_time })

                Err(e) ->
                    _ = stdout_line!("$(red_x) $(name) (failed to spawn)")
                    AlreadyFailed({
                        name,
                        worker_index,
                        passed: Bool.false,
                        duration_ms: 0,
                        output: "",
                        error: "Failed to spawn process: $(Inspect.to_str(e))",
                    })
