## The main entrypoint for running your tests. Use `Spec.run!` or `Spec.run_filtered!`
## and pass in your `PlatformHooks` and a `Config`.
##
## Roc has no parameterized modules, so these functions take a
## `PlatformHooks` record of platform functions as their first argument. The
## hooks are [niclas-ahden/basic-cli](https://github.com/niclas-ahden/basic-cli)'s own functions, passed as they are,
## so build the record once and hand the same one to every module of this
## package. Each function only reads the hooks it uses.
##
## ```roc
## hooks = {
##     new: Cmd.new,
##     os_str: OsStr.from_str,
##     # Leashed, so a test killed on timeout takes its descendants with it.
##     spawn!: Cmd.Command.spawn_leashed!,
##     poll!: Cmd.Child.poll!,
##     wait!: Cmd.Child.wait!,
##     kill!: Cmd.Child.kill!,
##     close!: Cmd.Child.close!,
##     path: Path.utf8,
##     list!: Path.list!,
##     print!: Stdout.line!,
##     now!: Utc.now!,
##     sleep!: Sleep.millis!,
##     env_var!: Env.var_str!,
##     # WORKAROUND: a lambda rather than `Http.send!` itself, because roc-spec
##     # passing a bare `{}` as its `SendOptions` crashes Roc 54283d4. Pass
##     # `Http.send!` once roc-lang/roc#12606 is fixed.
##     http_send!: |request| Http.send!(request, {}),
## }
##
## Spec.run!(hooks, "tests", {
##     test_command: ["roc", "--opt=speed"],
##     max_workers: 4,
##     worker_envs: |index| [("DATABASE_NAME", "test_${index.to_str()}")],
##     before_each!: |_| Ok({}),
##     per_test_timeout_ms: 60_000,
##     quiet: Bool.True,
##     fail_fast: Bool.False,
## })
## ```
##
## `Spec` uses `new`, `os_str`, `spawn!`, `poll!`, `wait!`, `kill!`, `path`,
## `list!`, `print!`, `now!` and `sleep!`. It starts each test as
## `test_command` followed by the test file, with both streams captured: a
## test's output is reported from what `poll!` and `wait!` hand back. A test
## that prints more than the capture budget (16 MiB by default) is cancelled
## by the platform and reported as failed, with what it printed up to that
## point.
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
		EmptyTestCommand,
		TestDirNotFound(Str),
		..err,
	]

	## Configuration for parallel test execution.
	##
	## - `test_command`: The program and arguments that run one test, with the
	##   test file appended, e.g. `["roc", "--opt=speed"]`. Change the opt level,
	##   wrap tests in systemd-run, or run something that is not `roc` at all
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
	##     test_command: ["roc", "--opt=speed"],
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
		test_command : List(Str),
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
	## Errors with `MaxWorkersIsZero` if `max_workers` is 0, with
	## `EmptyTestCommand` if `test_command` is empty, and with
	## `TestDirNotFound` if `test_dir` cannot be listed.
	## See `run_filtered!` to run a subset of tests by name pattern.
	##
	## Results come back in **completion order**, not discovery order: whichever
	## test finishes first is first in the list. Sort by `name` if you need a
	## stable order. With `fail_fast`, tests that never started are absent
	## entirely, so the list can be shorter than the number of files discovered.
	##
	## The `PlatformHooks` record is left unannotated because its fields are
	## your platform's own functions, with its own types. See the module docs
	## above for one built from [niclas-ahden/basic-cli](https://github.com/niclas-ahden/basic-cli).
	run! : _, Str, Config(cfg_err) => Try(List(TestResult), Error(err))
	run! = |hooks, test_dir, config|
		Spec.run_filtered!(hooks, test_dir, config, "")

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
	## Returns `Err(MaxWorkersIsZero)` if `max_workers` is 0,
	## `Err(EmptyTestCommand)` if `test_command` is empty, and
	## `Err(TestDirNotFound(test_dir))` if `test_dir` cannot be listed.
	##
	## Like `run!`, results come back in completion order rather than in
	## discovery order.
	run_filtered! : _, Str, Config(cfg_err), Str => Try(List(TestResult), Error(err))
	run_filtered! = |hooks, test_dir, config, pattern| {
		# Zero workers can never run anything, and reporting an empty run as a
		# success is the worst way for a test runner to fail: green output, no
		# tests. Refuse the config instead.
		if config.max_workers == 0 {
			Err(MaxWorkersIsZero)
		} else if config.test_command.is_empty() {
			Err(EmptyTestCommand)
		} else {
			# A `test_dir` that cannot be listed is an error for the same
			# reason zero workers is: a typo'd directory must not produce a
			# green "0/0 passed" run. Deeper in the tree an unlistable entry
			# just means "this is a file, not a directory", so only the top
			# level is strict.
			entries = list_dir!(hooks, test_dir) ? |_| TestDirNotFound(test_dir)
			test_files = process_directory_entries!(hooks, entries, [])

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
				run_with_rolling_window!(hooks, ordered_tests, config)
			}
		}
	}
}

## Windows lists a directory with a backslash between the directory you passed
## and each entry, so a name would otherwise keep the whole path. Names use `/`
## on every OS. `path` keeps whatever the OS said, since that is what runs.
normalize_separators : Str -> Str
normalize_separators = |path| path.replace_each("\\", "/")

get_basename : Str -> Str
get_basename = |path|
	normalize_separators(path).split_on("/").last().ok_or(path)

expect get_basename("tests/nested/foo_test.roc") == "foo_test.roc"
expect get_basename("examples/tests\\math_test.roc") == "math_test.roc"

## Order two strings by their UTF-8 bytes.
##
## There is no `Str.order_relative_to` builtin, and sorting needs a total
## order rather than a locale-aware one: the point is that every machine
## agrees.
compare_str : Str, Str -> [Before, Same, After]
compare_str = |a, b|
	compare_bytes(a.to_utf8(), b.to_utf8())

compare_bytes : List(U8), List(U8) -> [Before, Same, After]
compare_bytes = |a, b|
	match a {
		[] => if b.is_empty() Same else Before

		[first_a, .. as rest_a] =>
			match b {
				[] => After

				[first_b, .. as rest_b] =>
					match first_a.order_relative_to(first_b) {
						Same => compare_bytes(rest_a, rest_b)
						Before => Before
						After => After
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
	without_extension = normalize_separators(file).drop_suffix(".roc")
	dir = normalize_separators(test_dir)
	prefix = if dir.ends_with("/") dir else "${dir}/"
	# A path that does not start with the prefix keeps its full name rather
	# than being trimmed to something misleading.
	without_extension.drop_prefix(prefix)
}

expect extract_test_name("tests/fill/nested/foo_test.roc", "tests") == "fill/nested/foo_test"
expect extract_test_name("tests/foo_test.roc", "tests/") == "foo_test"
expect extract_test_name("examples/tests\\math_test.roc", "examples/tests") == "math_test"
expect extract_test_name("tests\\nested\\foo_test.roc", "tests") == "nested/foo_test"
expect extract_test_name("elsewhere/foo_test.roc", "tests") == "elsewhere/foo_test"

## A directory's entries as path strings, e.g. "tests/foo_test.roc".
list_dir! = |hooks, dir| {
	list! = hooks.list!
	path = hooks.path

	list!(path(dir)).map_ok(|entries| entries.map(|entry| entry.display()))
}

## The current instant in nanoseconds since the epoch, which durations are
## measured in.
now_nanos! : _ => U128
now_nanos! = |hooks| {
	now! = hooks.now!

	now!().to_nanos_since_epoch().to_u128_wrap()
}

## Recursively find all test files in a directory and its subdirectories.
find_test_files_recursive! = |hooks, dir, acc| {
	match list_dir!(hooks, dir) {
		Err(_) => acc # Not a directory or can't read it, return accumulated files
		Ok(entries) =>
			process_directory_entries!(hooks, entries, acc)
		}
}

## Process directory entries, collecting test files and recursing into subdirectories.
process_directory_entries! = |hooks, entries, acc| {
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
			with_subdir = find_test_files_recursive!(hooks, entry, with_file)

			# Continue processing remaining entries
			process_directory_entries!(hooks, rest, with_subdir)
		}
	}
}

## Rolling window scheduler - spawns replacement tests as others complete.
run_with_rolling_window! = |hooks, test_files, config| {
	max_workers = config.max_workers.to_u64()

	# Split into initial batch and remaining tests
	{ before: initial_files, others: remaining_files } = test_files.split_at(max_workers)

	# Spawn initial batch (up to max_workers)
	initial_spawned = spawn_batch_with_indices!(hooks, initial_files, config, 0)

	# Process tests: poll for completion, process finished ones, spawn new ones as slots free up
	process_rolling_window!(
		hooks,
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
process_rolling_window! = |hooks, running, already_failed, pending_files, config, max_workers, results, stopping|
	match already_failed {
		[first_failed, .. as other_failed] => {
			# Report tests that never started before polling the live ones
			{ name, worker_index, passed, duration_ms, output, error } = first_failed
			test_result = { name, passed, duration_ms, output, error }
			now_stopping = stopping or (config.fail_fast and !passed)
			with_result = results.append(test_result)

			# Don't spawn replacements if stopping
			if now_stopping {
				process_rolling_window!(hooks, running, other_failed, [], config, max_workers, with_result, now_stopping)
			} else {
				# Spawn replacement if any pending
				(spawned, new_pending) = spawn_next!(hooks, pending_files, worker_index, config)

				match spawned {
					NothingPending =>
						process_rolling_window!(hooks, running, other_failed, new_pending, config, max_workers, with_result, now_stopping)

					StartedRunning(started) =>
						process_rolling_window!(hooks, running.append(started), other_failed, new_pending, config, max_workers, with_result, now_stopping)

					StartedFailed(failed) =>
						process_rolling_window!(hooks, running, other_failed.append(failed), new_pending, config, max_workers, with_result, now_stopping)
					}
			}
		}

		[] =>
			if running.is_empty() {
				Ok(results) # Nothing running and nothing left to report, we're done
			} else {
				poll_for_completion!(hooks, running, already_failed, pending_files, config, max_workers, results, stopping)
			}
		}

## Poll all running tests and process whichever finishes first.
##
## `already_failed` is empty at every call site, since the scheduler reports
## those first. It is carried anyway rather than assumed, so a future caller
## cannot silently drop tests waiting to be reported.
poll_for_completion! = |hooks, running, already_failed, pending_files, config, max_workers, results, stopping| {
	sleep! = hooks.sleep!

	match find_completed!(hooks, running, config) {
		Found({ completed, worker_index, poll_result, remaining }) => {
			# Process the completed test
			test_result = process_poll_result!(hooks, completed, poll_result, config.quiet)
			now_stopping = stopping or (config.fail_fast and !test_result.passed)
			with_result = results.append(test_result)

			if now_stopping {
				# Don't spawn replacements, just drain remaining running tests
				process_rolling_window!(hooks, remaining, already_failed, [], config, max_workers, with_result, now_stopping)
			} else {
				# Spawn replacement if any pending
				(spawned, new_pending) = spawn_next!(hooks, pending_files, worker_index, config)

				match spawned {
					NothingPending =>
						process_rolling_window!(hooks, remaining, already_failed, new_pending, config, max_workers, with_result, now_stopping)

					StartedRunning(started) =>
						process_rolling_window!(hooks, remaining.append(started), already_failed, new_pending, config, max_workers, with_result, now_stopping)

					StartedFailed(failed) =>
						process_rolling_window!(hooks, remaining, already_failed.append(failed), new_pending, config, max_workers, with_result, now_stopping)
					}
			}
		}

		NoneCompleted => {
			# No test finished yet, sleep briefly and try again
			_ = sleep!(10)
			poll_for_completion!(hooks, running, already_failed, pending_files, config, max_workers, results, stopping)
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
find_completed! = |hooks, running, config|
	find_completed_helper!(hooks, running, [], config.per_test_timeout_ms)

find_completed_helper! = |hooks, remaining, checked, timeout_ms| {
	poll! = hooks.poll!

	match remaining {
		[] =>
			NoneCompleted

		[spawned, .. as rest] => {
			{ name, worker_index, child, start_time } = spawned

			# Only a child still running is subject to the timeout below;
			# everything else is a result, however the test ended.
			outcome =
				match poll!(child) {
					Ok(Finished(output)) =>
						Done(Finished(ended(output)))

					Ok(Running) =>
						StillRunning

					# The platform's own deadline (`Cmd.timeout`) ran out before
					# this loop's did. What it retained is what the test
					# managed to print.
					Err(CmdErr(TimedOut(partial))) =>
						Done(TimedOut({ stdout: partial.stdout_bytes, stderr: partial.stderr_bytes, kill_error: "" }))

					Err(CmdErr(OutputLimitExceeded(partial))) =>
						Done(OutputLimitExceeded({ stdout: partial.stdout_bytes, stderr: partial.stderr_bytes }))

					# A poll error is usually transient, so keep the test in the
					# running list. The timeout still applies there: a child
					# whose poll never recovers would otherwise stay in that
					# list forever and hang the entire run.
					Err(_) =>
						StillRunning
				}

			match outcome {
				Done(poll_result) =>
					Found({
						completed: { name, start_time },
						worker_index,
						poll_result,
						remaining: checked.concat(rest),
					})

				StillRunning => {
					elapsed_ms = (now_nanos!(hooks).minus_saturated(start_time) // 1_000_000).to_u64_wrap()

					if elapsed_ms > timeout_ms {
						Found({
							completed: { name, start_time },
							worker_index,
							poll_result: kill_timed_out!(hooks, child),
							remaining: checked.concat(rest),
						})
					} else {
						# Not finished yet, keep looking
						find_completed_helper!(hooks, rest, checked.append(spawned), timeout_ms)
					}
				}
			}
		}
	}
}

## Kill a test that ran out of time and shape what it left behind into a poll
## result. Killing a leashed child takes down the test and anything it spawned,
## and reaping it hands back whatever it printed before it hung, which is the
## most useful part of a timeout report.
kill_timed_out! = |hooks, child| {
	kill! = hooks.kill!
	wait! = hooks.wait!

	match kill!(child) {
		Err(e) =>
			TimedOut({ stdout: [], stderr: [], kill_error: "could not kill it: ${Str.inspect(e)}" })

		Ok({}) =>
			match wait!(child) {
				Ok(platform_output) => {
					output = ended(platform_output)
					match output.status {
						# A test that exited 0 in the sliver between the poll
						# and the kill beat the deadline by a hair, so report
						# what it did rather than a timeout. A zero exit is the
						# only status trusted for that: on Unix a killed child
						# comes back `Signaled`, but on Windows the host cannot
						# tell a TerminateProcess from a genuine exit and
						# reports `Exited(1)`, so any other status after a
						# successful kill is the timeout it was killed for.
						Exited(0) => Finished(output)
						_ => TimedOut({ stdout: output.stdout_bytes, stderr: output.stderr_bytes, kill_error: "" })
					}
				}

				Err(CmdErr(TimedOut(partial))) =>
					TimedOut({ stdout: partial.stdout_bytes, stderr: partial.stderr_bytes, kill_error: "" })

				# Both budgets ran out. The deadline is why it was killed, so
				# that is what gets reported, along with what it printed.
				Err(CmdErr(OutputLimitExceeded(partial))) =>
					TimedOut({ stdout: partial.stdout_bytes, stderr: partial.stderr_bytes, kill_error: "" })

				Err(e) =>
					TimedOut({ stdout: [], stderr: [], kill_error: "could not reap it: ${Str.inspect(e)}" })
			}
	}
}

## How a child ended and what it printed, out of the platform's own output.
ended = |output| { status: output.status, stdout_bytes: output.stdout_bytes, stderr_bytes: output.stderr_bytes }

## Process a poll result into a TestResult.
process_poll_result! = |hooks, { name, start_time }, poll_result, quiet| {
	print! = hooks.print!

	end_time = now_nanos!(hooks)
	duration_ms = (end_time.minus_saturated(start_time) // 1_000_000).to_u64_wrap()
	duration = Format.format_duration(duration_ms)

	match poll_result {
		Finished({ status, stdout_bytes, stderr_bytes }) => {
			stdout_str = Str.from_utf8_lossy(stdout_bytes)
			stderr_str = Str.from_utf8_lossy(stderr_bytes)

			match status {
				Exited(0) => {
					_ = print!("${Format.green_check} ${name} (${duration})")
					_ =
						if !quiet {
							print_output!(hooks, stdout_str, stderr_str)
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
				}

				Exited(_) => {
					_ = print!("${Format.red_x} ${name} (${duration})")
					_ = print_output!(hooks, stdout_str, stderr_str)
					{
						name,
						passed: Bool.False,
						duration_ms,
						output: stdout_str,
						error: stderr_str,
					}
				}

				Signaled(signal) => {
					_ = print!("${Format.red_x} ${name} (killed by signal ${signal.to_str()} after ${duration})")
					_ = print_output!(hooks, stdout_str, stderr_str)
					{
						name,
						passed: Bool.False,
						duration_ms,
						output: stdout_str,
						error: with_note(stderr_str, "Killed by signal ${signal.to_str()}"),
					}
				}
			}
		}

		TimedOut({ stdout, stderr, kill_error }) => {
			stdout_str = Str.from_utf8_lossy(stdout)
			stderr_str = Str.from_utf8_lossy(stderr)

			_ = print!("${Format.red_x} ${name} (TIMEOUT after ${duration})")
			_ = print_output!(hooks, stdout_str, stderr_str)
			{
				name,
				passed: Bool.False,
				duration_ms,
				output: stdout_str,
				error: if kill_error.is_empty() "Test timed out" else "Test timed out, ${kill_error}",
			}
		}

		OutputLimitExceeded({ stdout, stderr }) => {
			stdout_str = Str.from_utf8_lossy(stdout)
			stderr_str = Str.from_utf8_lossy(stderr)

			_ = print!("${Format.red_x} ${name} (OUTPUT LIMIT exceeded after ${duration})")
			_ = print_output!(hooks, stdout_str, stderr_str)
			{
				name,
				passed: Bool.False,
				duration_ms,
				output: stdout_str,
				error: with_note(stderr_str, output_limit_note),
			}
		}
	}
}

## What a test is told when the platform cancelled it for printing too much.
output_limit_note : Str
output_limit_note = "Test exceeded its output limit and was cancelled. Print less, or raise the limit with Cmd.Command.output_limit in your spawn! hook."

## Add a note on how a test ended to what it wrote on stderr.
with_note : Str, Str -> Str
with_note = |stderr_str, note|
	if stderr_str.is_empty() note else "${stderr_str}\n${note}"

## Print captured stdout/stderr with indentation
print_output! = |hooks, stdout_str, stderr_str| {
	print! = hooks.print!

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
spawn_next! = |hooks, pending_files, freed_worker_index, config|
	match pending_files {
		[] =>
		# No more pending tests
			(NothingPending, [])

		[next_file, .. as other_pending] =>
			match spawn_one!(hooks, next_file, freed_worker_index, config) {
				Spawned(started) => (StartedRunning(started), other_pending)
				AlreadyFailed(failed) => (StartedFailed(failed), other_pending)
			}
		}

## Spawn a batch of tests with sequential worker indices starting from start_index.
spawn_batch_with_indices! = |hooks, test_files, config, start_index| {
	indexed = test_files.map_with_index(|file, i| (file, start_index + i))
	spawn_batch_helper!(hooks, indexed, config, [])
}

spawn_batch_helper! = |hooks, remaining, config, acc|
	match remaining {
		[] => acc
		[(file, worker_index), .. as rest] => {
			result = spawn_one!(hooks, file, worker_index, config)
			spawn_batch_helper!(hooks, rest, config, acc.append(result))
		}
	}

spawn_one! = |hooks, test_file, worker_index, config| {
	print! = hooks.print!
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
			start_time = now_nanos!(hooks)
			envs = worker_envs(worker_index)
			# The per-test timeout is enforced by the poll loop rather than by
			# wrapping the command in `timeout`, so it needs no coreutils and
			# keeps millisecond resolution.
			spawn_result = spawn_test!(hooks, config.test_command, test_file.path, envs)

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
						error: "Failed to spawn process: ${e}",
					})
				}
			}
		}
	}
}

## Start one test as `test_command` followed by the test file, with the
## worker's env vars set and both streams captured, through the `spawn!` hook.
spawn_test! = |hooks, test_command, file, envs| {
	new = hooks.new
	os_str = hooks.os_str
	spawn! = hooks.spawn!

	match test_command {
		# `run_filtered!` refuses an empty command before anything is spawned.
		[] => Err("test_command is empty")
		[program, .. as args] => {
			cmd =
				new(os_str(program))
					.args(args.append(file).map(os_str))
					.envs(envs.map(|(name, value)| (os_str(name), os_str(value))))
					.stdout(Capture)
					.stderr(Capture)
			spawn!(cmd).map_err(|e| Str.inspect(e))
		}
	}
}
