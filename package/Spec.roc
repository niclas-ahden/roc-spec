## The main entrypoint for running your tests. Use `Spec.run!` or `Spec.run_filtered!`
## and pass in the platform `effects` and a `Config`.
##
## Roc has no parameterized modules, so these functions take an
## `effects` record of platform functions as their first argument. Each effect is
## shaped by what `Spec` needs rather than mirroring the platform's API, which
## keeps the record small. Build it once from basic-cli's modules:
##
## ```roc
## effects = {
##     # Start one test file as its own process group, with the given env vars.
##     # The command is yours: change the opt level, wrap tests in systemd-run,
##     # or run something that is not `roc` at all. Spawn grouped, so that a
##     # test killed on timeout takes its descendants with it.
##     spawn_test!: |file, envs|
##         Cmd.new(OsStr.utf8("roc"))
##             .args_str(["--opt=speed", file])
##             .envs_str(envs)
##             .spawn_grouped!(),
##     poll!: Cmd.Child.poll!,
##     kill_wait!: Cmd.Child.kill_wait!,
##     # List a directory's entries as path strings, e.g. "tests/foo_test.roc".
##     list_dir!: |dir| Path.list!(Path.utf8(dir)).map_ok(|entries| entries.map(Path.display)),
##     print!: Stdout.line!,
##     utc_now!: Utc.now!,
##     sleep_millis!: Sleep.millis!,
## }
##
## Spec.run!(effects, "tests", {
##     max_workers: 4,
##     worker_envs: |index| [("DATABASE_NAME", "test_${index.to_str()}")],
##     before_each!: |_| Ok({}),
##     per_test_timeout_ms: 60_000,
##     quiet: Bool.True,
##     fail_fast: Bool.False,
## })
## ```
import Format

Spec :: [].{

	## Result of a single test.
	##
	## - `name`: Test name derived from filename (e.g., `login_test` from `login_test.roc`)
	## - `passed`: Whether the test exited with code 0
	## - `duration_ms`: How long the test took to run
	## - `output`: Captured stdout from the test process
	## - `error`: Captured stderr from the test process
	TestResult : {
		name : Str,
		passed : Bool,
		duration_ms : U64,
		output : Str,
		error : Str,
	}

	## Why a run could not happen at all.
	##
	## Distinct from tests running and failing, which is not an error: that
	## shows up as `passed: Bool.False` in the returned `TestResult`s.
	Error(err) : [
		MaxWorkersIsZero,
		TestDirNotFound(Str),
		..err,
	]

	## Configuration for parallel test execution.
	##
	## - `max_workers`: Maximum number of tests to run concurrently, at least 1
	## - `worker_envs`: Function that returns the environment variables to set for a given worker index
	## - `before_each!`: Hook called before each test (e.g., to truncate database)
	## - `per_test_timeout_ms`: Timeout for each individual test in milliseconds
	## - `quiet`: When true, only show stdout/stderr for failed tests; when false, show for all tests
	## - `fail_fast`: When true, stop running new tests after the first failure
	##
	## Example:
	## ```roc
	## {
	##     max_workers: 32,
	##     worker_envs: |index| [
	##         ("APP_PORT", (8000 + index).to_str()),
	##         ("DATABASE_NAME", "test_${index.to_str()}"),
	##     ],
	##     before_each!: |index| Pg.truncate!(query!, db, []),
	##     per_test_timeout_ms: 120_000,
	##     quiet: Bool.False,
	##     fail_fast: Bool.False,
	## }
	## ```
	Config(err) : {
		max_workers : U16,
		worker_envs : U64 -> List((Str, Str)),
		before_each! : U64 => Try({}, err),
		per_test_timeout_ms : U64,
		quiet : Bool,
		fail_fast : Bool,
	}

	## Run all `*_test.roc` files in the given directory and subdirectories in parallel.
	##
	## Returns a list of test results, one for each test file discovered and run.
	## Errors with `MaxWorkersIsZero` if `max_workers` is 0, and with
	## `TestDirNotFound` if `test_dir` cannot be listed.
	## See `run_filtered!` to run a subset of tests by name pattern.
	##
	## Results come back in **completion order**, not discovery order: whichever
	## test finishes first is first in the list. Sort by `name` if you need a
	## stable order. With `fail_fast`, tests that never started are absent
	## entirely, so the list can be shorter than the number of files discovered.
	##
	## The `effects` record is left unannotated because its fields are shaped by
	## your platform's own types (the process handle `spawn_test!` returns, the
	## instant `utc_now!` returns). See the module docs above for one built from
	## basic-cli.
	run! : _, Str, Config(cfg_err) => Try(List(TestResult), Error(err))
	run! = |effects, test_dir, config|
		Spec.run_filtered!(effects, test_dir, config, "")

	## Run tests matching a pattern.
	##
	## The pattern is a simple substring match on the test name, which is the
	## file's path relative to `test_dir` without the `.roc` suffix:
	## - `""` (empty string): run all tests
	## - `"login"`: matches `login_test.roc`, `login_flow_test.roc`, etc.
	## - `"payments/"`: matches every test under that directory
	## - `"payments/invoice"`: matches `invoice_created_test.roc`,
	##   `invoice_paid_test.roc`, etc. under that directory
	## - We don't yet support globbing, wildcards, regex etc.
	##
	## Recursively searches all subdirectories for test files.
	##
	## Returns `Err(MaxWorkersIsZero)` if `max_workers` is 0, and
	## `Err(TestDirNotFound(test_dir))` if `test_dir` cannot be listed.
	##
	## Like `run!`, results come back in completion order rather than in
	## discovery order.
	run_filtered! : _, Str, Config(cfg_err), Str => Try(List(TestResult), Error(err))
	run_filtered! = |effects, test_dir, config, pattern| {
		# Zero workers can never run anything, and reporting an empty run as a
		# success is the worst way for a test runner to fail: green output, no
		# tests. Refuse the config instead.
		if config.max_workers == 0 {
			Err(MaxWorkersIsZero)
		} else {
			list_dir! = effects.list_dir!

			# A `test_dir` that cannot be listed is an error for the same
			# reason zero workers is: a typo'd directory must not produce a
			# green "0/0 passed" run. Deeper in the tree an unlistable entry
			# just means "this is a file, not a directory", so only the top
			# level is strict.
			entries = list_dir!(test_dir) ? |_| TestDirNotFound(test_dir)
			test_files = process_directory_entries!(effects, entries, [])

			# Name each test here, where `test_dir` is still in scope, so a name
			# is relative to the directory you asked to run rather than to how
			# deep that directory happens to be.
			named_tests = test_files.map(
				|file| { path: file, name: extract_test_name(file, test_dir) },
			)

			# Filter on the full test name rather than the filename, so a
			# pattern can pick out a directory ("payments/") as well as
			# a single test ("payments/invoice_paid").
			filtered_tests =
				if pattern.is_empty() {
					named_tests
				} else {
					named_tests.keep_if(|t| t.name.contains(pattern))
				}

			# Directory listings arrive in whatever order the filesystem hands
			# back, which differs between machines. Sorting by name fixes the
			# order tests are started in, so a `fail_fast` run stops after the
			# same tests everywhere instead of a different set each time.
			ordered_tests = filtered_tests.sort_with(|a, b| compare_str(a.name, b.name))

			if ordered_tests.is_empty() {
				Ok([])
			} else {
				run_with_rolling_window!(effects, ordered_tests, config)
			}
		}
	}
}

get_basename : Str -> Str
get_basename = |path|
	path.split_on("/").last().ok_or(path)

## Order two strings by their UTF-8 bytes.
##
## There is no `Str.compare` builtin, and sorting needs a total order rather
## than a locale-aware one: the point is that every machine agrees.
compare_str : Str, Str -> [LT, EQ, GT]
compare_str = |a, b|
	compare_bytes(a.to_utf8(), b.to_utf8())

compare_bytes : List(U8), List(U8) -> [LT, EQ, GT]
compare_bytes = |a, b|
	match a {
		[] => if b.is_empty() EQ else LT

		[first_a, .. as rest_a] =>
			match b {
				[] => GT

				[first_b, .. as rest_b] =>
					match first_a.compare(first_b) {
						EQ => compare_bytes(rest_a, rest_b)
						LT => LT
						GT => GT
					}
				}
		}

## Name a test by its path relative to the directory it was discovered in.
##
## e.g. with a `test_dir` of "tests", "tests/fill/nested/foo_test.roc" becomes
## "fill/nested/foo_test". The `test_dir` prefix is stripped in full, so the
## name does not shift when the same tests are reached by a deeper path.
extract_test_name : Str, Str -> Str
extract_test_name = |file, test_dir| {
	without_extension = file.drop_suffix(".roc")
	prefix = if test_dir.ends_with("/") test_dir else "${test_dir}/"
	# A path that does not start with the prefix keeps its full name rather
	# than being trimmed to something misleading.
	without_extension.drop_prefix(prefix)
}

## Recursively find all test files in a directory and its subdirectories.
find_test_files_recursive! = |effects, dir, acc| {
	list_dir! = effects.list_dir!

	match list_dir!(dir) {
		Err(_) => acc # Not a directory or can't read it, return accumulated files
		Ok(entries) =>
			process_directory_entries!(effects, entries, acc)
		}
}

## Process directory entries, collecting test files and recursing into subdirectories.
process_directory_entries! = |effects, entries, acc| {
	match entries {
		[] => acc
		[entry, .. as rest] => {
			basename = get_basename(entry)

			# Check if this entry is a test file
			is_test_file = basename.ends_with("_test.roc")

			# Add to results if it's a test file
			with_file =
				if is_test_file {
					acc.append(entry)
				} else {
					acc
				}

			# Try to recurse into this entry as a potential subdirectory
			# (list_dir! will fail for files, which is handled gracefully)
			with_subdir = find_test_files_recursive!(effects, entry, with_file)

			# Continue processing remaining entries
			process_directory_entries!(effects, rest, with_subdir)
		}
	}
}

## Rolling window scheduler - spawns replacement tests as others complete.
run_with_rolling_window! = |effects, test_files, config| {
	max_workers = config.max_workers.to_u64()

	# Split into initial batch and remaining tests
	{ before: initial_files, others: remaining_files } = test_files.split_at(max_workers)

	# Spawn initial batch (up to max_workers)
	initial_spawned = spawn_batch_with_indices!(effects, initial_files, config, 0)

	# Process tests: poll for completion, process finished ones, spawn new ones as slots free up
	process_rolling_window!(
		effects,
		only_running(initial_spawned),
		only_failed(initial_spawned),
		remaining_files,
		config,
		max_workers,
		[],
		Bool.False,
	)
}

## Process spawned tests by polling for completion.
## Tests are processed in completion order (whichever finishes first), not spawn order.
##
## Running tests and ones that never started are carried in separate lists. They
## are different things (one has a live child to poll, the other is already a
## result) and keeping them apart is what leaves this scheduler with no case
## that cannot happen.
process_rolling_window! = |effects, running, already_failed, pending_files, config, max_workers, results, stopping|
	match already_failed {
		[first_failed, .. as other_failed] => {
			# Report tests that never started before polling the live ones
			{ name, worker_index, passed, duration_ms, output, error } = first_failed
			test_result = { name, passed, duration_ms, output, error }
			now_stopping = stopping or (config.fail_fast and !passed)
			with_result = results.append(test_result)

			# Don't spawn replacements if stopping
			if now_stopping {
				process_rolling_window!(effects, running, other_failed, [], config, max_workers, with_result, now_stopping)
			} else {
				# Spawn replacement if any pending
				(spawned, new_pending) = spawn_next!(effects, pending_files, worker_index, config)

				match spawned {
					NothingPending =>
						process_rolling_window!(effects, running, other_failed, new_pending, config, max_workers, with_result, now_stopping)

					StartedRunning(started) =>
						process_rolling_window!(effects, running.append(started), other_failed, new_pending, config, max_workers, with_result, now_stopping)

					StartedFailed(failed) =>
						process_rolling_window!(effects, running, other_failed.append(failed), new_pending, config, max_workers, with_result, now_stopping)
					}
			}
		}

		[] =>
			if running.is_empty() {
				Ok(results) # Nothing running and nothing left to report, we're done
			} else {
				poll_for_completion!(effects, running, already_failed, pending_files, config, max_workers, results, stopping)
			}
		}

## Poll all running tests and process whichever finishes first.
##
## `already_failed` is empty at every call site, since the scheduler reports
## those first. It is carried anyway rather than assumed, so a future caller
## cannot silently drop tests waiting to be reported.
poll_for_completion! = |effects, running, already_failed, pending_files, config, max_workers, results, stopping| {
	sleep_millis! = effects.sleep_millis!

	match find_completed!(effects, running, config) {
		Found({ completed, worker_index, poll_result, remaining }) => {
			# Process the completed test
			test_result = process_poll_result!(effects, completed, poll_result, config.quiet)
			now_stopping = stopping or (config.fail_fast and !test_result.passed)
			with_result = results.append(test_result)

			if now_stopping {
				# Don't spawn replacements, just drain remaining running tests
				process_rolling_window!(effects, remaining, already_failed, [], config, max_workers, with_result, now_stopping)
			} else {
				# Spawn replacement if any pending
				(spawned, new_pending) = spawn_next!(effects, pending_files, worker_index, config)

				match spawned {
					NothingPending =>
						process_rolling_window!(effects, remaining, already_failed, new_pending, config, max_workers, with_result, now_stopping)

					StartedRunning(started) =>
						process_rolling_window!(effects, remaining.append(started), already_failed, new_pending, config, max_workers, with_result, now_stopping)

					StartedFailed(failed) =>
						process_rolling_window!(effects, remaining, already_failed.append(failed), new_pending, config, max_workers, with_result, now_stopping)
					}
			}
		}

		NoneCompleted => {
			# No test finished yet, sleep briefly and try again
			sleep_millis!(10)
			poll_for_completion!(effects, running, already_failed, pending_files, config, max_workers, results, stopping)
		}
	}
}

## The tests in a freshly spawned batch that have a live child to poll.
only_running = |spawned|
	spawned.fold(
		[],
		|acc, item|
			match item {
				Spawned(started) => acc.append(started)
				AlreadyFailed(_) => acc
			},
	)

## The tests in a freshly spawned batch that never started, and so are already
## results waiting to be reported.
only_failed = |spawned|
	spawned.fold(
		[],
		|acc, item|
			match item {
				AlreadyFailed(failed) => acc.append(failed)
				Spawned(_) => acc
			},
	)

## Poll all running tests to find one that completed or ran out of time.
find_completed! = |effects, running, config|
	find_completed_helper!(effects, running, [], config.per_test_timeout_ms)

find_completed_helper! = |effects, remaining, checked, timeout_ms| {
	poll! = effects.poll!
	utc_now! = effects.utc_now!

	match remaining {
		[] =>
			NoneCompleted

		[spawned, .. as rest] => {
			{ name, worker_index, child, start_time } = spawned
			poll_result = poll!(child)

			match poll_result {
				Ok(Exited({ exit_code, stdout, stderr })) =>
					Found({
						completed: { name, start_time },
						worker_index,
						poll_result: Exited({ stdout, stderr, exit_code }),
						remaining: checked.concat(rest),
					})

				Ok(Running) => {
					elapsed_ms = (utc_now!().minus_saturated(start_time) // 1_000_000).to_u64_wrap()

					if elapsed_ms > timeout_ms {
						Found({
							completed: { name, start_time },
							worker_index,
							poll_result: kill_timed_out!(effects, child),
							remaining: checked.concat(rest),
						})
					} else {
						# Not finished yet, keep looking
						find_completed_helper!(effects, rest, checked.append(spawned), timeout_ms)
					}
				}

				Err(_) => {
					# A poll error is usually transient, so keep the test in the
					# running list. The timeout still applies here: a child
					# whose poll never recovers would otherwise stay in that
					# list forever and hang the entire run.
					elapsed_ms = (utc_now!().minus_saturated(start_time) // 1_000_000).to_u64_wrap()

					if elapsed_ms > timeout_ms {
						Found({
							completed: { name, start_time },
							worker_index,
							poll_result: kill_timed_out!(effects, child),
							remaining: checked.concat(rest),
						})
					} else {
						find_completed_helper!(effects, rest, checked.append(spawned), timeout_ms)
					}
				}
			}
		}
	}
}

## Kill a test that ran out of time and shape what it left behind into a poll
## result. Killing a grouped child takes down the test and anything it spawned,
## and hands back whatever it printed before it hung, which is the most useful
## part of a timeout report.
kill_timed_out! = |effects, child| {
	kill_wait! = effects.kill_wait!

	match kill_wait!(child) {
		Ok({ stdout, stderr, exit_code }) =>
		# A test that finished in the sliver between the poll and the kill
		# has a real exit code; the signal path reports -1. Report what it
		# did rather than a timeout it beat by a hair.
			if exit_code >= 0 {
				Exited({ stdout, stderr, exit_code })
			} else {
				TimedOut({ stdout, stderr, kill_error: "" })
			}

		Err(e) =>
			TimedOut({ stdout: [], stderr: [], kill_error: "could not kill it: ${Str.inspect(e)}" })
		}
}

## Process a poll result into a TestResult.
process_poll_result! = |effects, { name, start_time }, poll_result, quiet| {
	print! = effects.print!
	utc_now! = effects.utc_now!

	end_time = utc_now!()
	duration_ms = (end_time.minus_saturated(start_time) // 1_000_000).to_u64_wrap()

	match poll_result {
		Exited({ stdout, stderr, exit_code }) => {
			stdout_str = Str.from_utf8_lossy(stdout)
			stderr_str = Str.from_utf8_lossy(stderr)

			if exit_code == 0 {
				_ = print!("${Format.green_check} ${name} (${Format.format_duration(duration_ms)})")
				_ =
					if !quiet {
						print_output!(effects, stdout_str, stderr_str)
					} else {
						Ok({})
					}
				{
					name,
					passed: Bool.True,
					duration_ms,
					output: stdout_str,
					error: stderr_str,
				}
			} else {
				_ = print!("${Format.red_x} ${name} (${Format.format_duration(duration_ms)})")
				_ = print_output!(effects, stdout_str, stderr_str)
				{
					name,
					passed: Bool.False,
					duration_ms,
					output: stdout_str,
					error: stderr_str,
				}
			}
		}

		TimedOut({ stdout, stderr, kill_error }) => {
			stdout_str = Str.from_utf8_lossy(stdout)
			stderr_str = Str.from_utf8_lossy(stderr)

			_ = print!("${Format.red_x} ${name} (TIMEOUT after ${Format.format_duration(duration_ms)})")
			_ = print_output!(effects, stdout_str, stderr_str)
			{
				name,
				passed: Bool.False,
				duration_ms,
				output: stdout_str,
				error: if kill_error.is_empty() "Test timed out" else "Test timed out, ${kill_error}",
			}
		}
	}
}

## Print captured stdout/stderr with indentation
print_output! = |effects, stdout_str, stderr_str| {
	print! = effects.print!

	_ =
		if !stdout_str.is_empty() {
			print!(Format.indent_lines(stdout_str))
		} else {
			Ok({})
		}
	if !stderr_str.is_empty() {
		print!(Format.indent_lines(stderr_str))
	} else {
		Ok({})
	}
}

## Spawn the next pending test on a freed worker index, if any are left.
##
## Reports which list the caller should file the result under, so neither list
## has to hold a test of the other kind.
spawn_next! = |effects, pending_files, freed_worker_index, config|
	match pending_files {
		[] =>
		# No more pending tests
			(NothingPending, [])

		[next_file, .. as other_pending] =>
			match spawn_one!(effects, next_file, freed_worker_index, config) {
				Spawned(started) => (StartedRunning(started), other_pending)
				AlreadyFailed(failed) => (StartedFailed(failed), other_pending)
			}
		}

## Spawn a batch of tests with sequential worker indices starting from start_index.
spawn_batch_with_indices! = |effects, test_files, config, start_index| {
	indexed = test_files.map_with_index(|file, i| (file, start_index + i))
	spawn_batch_helper!(effects, indexed, config, [])
}

spawn_batch_helper! = |effects, remaining, config, acc|
	match remaining {
		[] => acc
		[(file, worker_index), .. as rest] => {
			result = spawn_one!(effects, file, worker_index, config)
			spawn_batch_helper!(effects, rest, config, acc.append(result))
		}
	}

spawn_one! = |effects, test_file, worker_index, config| {
	spawn_test! = effects.spawn_test!
	print! = effects.print!
	utc_now! = effects.utc_now!
	before_each! = config.before_each!
	worker_envs = config.worker_envs

	name = test_file.name

	# Run before_each hook (e.g., truncate database)
	match before_each!(worker_index) {
		Err(e) => {
			_ = print!("${Format.red_x} ${name} (before_each failed)")
			AlreadyFailed({
				name,
				worker_index,
				passed: Bool.False,
				duration_ms: 0,
				output: "",
				error: "before_each! failed: ${Str.inspect(e)}",
			})
		}

		Ok({}) => {
			start_time = utc_now!()
			envs = worker_envs(worker_index)
			# The per-test timeout is enforced by the poll loop rather than by
			# wrapping the command in `timeout`, so it needs no coreutils and
			# keeps millisecond resolution.
			spawn_result = spawn_test!(test_file.path, envs)

			match spawn_result {
				Ok(child) =>
					Spawned({ name, worker_index, child, start_time })

				Err(e) => {
					_ = print!("${Format.red_x} ${name} (failed to spawn)")
					AlreadyFailed({
						name,
						worker_index,
						passed: Bool.False,
						duration_ms: 0,
						output: "",
						error: "Failed to spawn process: ${Str.inspect(e)}",
					})
				}
			}
		}
	}
}
