#!/usr/bin/env roc
## All roc-spec tests: the packages' own `expect` blocks first, then the
## server fixtures are built, then every tests/*_test.roc runs as a
## standalone INTERPRETED app (plain `roc file.roc`).
##
## Interpreted on purpose: these tests are runners themselves, and running
## them interpreted keeps the compile budget on the tests they spawn, which
## `Spec.run!` builds with `--opt=speed` anyway. It also means the server
## tests here never exercise `Server.with!` compiled, which is how
## roc-lang/roc#10370 stayed hidden; tests/server_under_spec_test.roc covers
## that path on purpose.
##
## The PostgreSQL tests need a server. When DATABASE_URL is set they use that
## one untouched. Otherwise this script boots a throwaway Postgres of its own
## with initdb/postgres from the dev shell, so a plain run covers them too:
##
##     nix develop -c ./tests.roc
##
## With neither a DATABASE_URL nor initdb on PATH they are skipped, and skips
## are listed in the summary so a green run still shows what it did not cover.
##
## Pass --fail-fast to stop at the first failing test.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr exposing [OsStr]
import pf.Path
import pf.Sleep
import pf.Stderr
import pf.Stdout

unit_files : List(Str)
unit_files = ["package/Assert.roc", "package/Format.roc"]

## Need a PostgreSQL server. Skipped when there is neither a DATABASE_URL nor
## an initdb to boot one with. Matched on the filename rather than the whole
## path, because the directory part of a listing carries the platform's own
## separator.
pg_tests : List(Str)
pg_tests = ["rollback_test.roc", "truncate_test.roc"]

## Not using port 5432 since we don't want to collide with other databases
## you may be running.
pg_port = "5498"

pg_user = "roc_spec_test"

## The database initdb creates anyway, so the throwaway server needs no
## createdb step. Tables the tests create live and die with the data dir.
pg_database = "postgres"

## Where the throwaway server is reachable. The IPv4 literal is deliberate:
## the server only listens on 127.0.0.1, and `localhost` resolves to ::1 first
## on plenty of machines.
pg_url = "postgresql://${pg_user}@127.0.0.1:${pg_port}/${pg_database}"

main! = |os_args| {
	fail_fast = os_args.any(|a| OsStr.display(a) == "--fail-fast")

	# Bound here, above `use_systemd`, and not inlined into the `if` below.
	# Either change makes the compiler call the unrelated `if use_systemd` an
	# "unconditional condition", and one warning makes the whole run exit 2.
	have_db_url = Env.var_str!(OsStr.utf8("DATABASE_URL")).is_ok()

	# systemd scope when available (ensures all descendant processes die with
	# the test); fall back to a plain spawn in CI where no user session exists.
	use_systemd =
		Cmd.new(OsStr.utf8("systemctl"))
			.args([OsStr.utf8("--user"), OsStr.utf8("show-environment")])
			.exec_output!()
			.is_ok()

	# The data dir is repo local (and gitignored) rather than under TMPDIR,
	# where the roc interpreter's scratch cleanup can delete it mid-run.
	# Absolute, because the postgres daemon resolves the socket dir after
	# changing its working directory.
	data = Path.display(Env.cwd!().map_err(|_| CwdUnavailable)?.join(".pg-test-db"))

	# Where the Pg tests get their server:
	#
	#   Inherited   - DATABASE_URL is already set, so leave that server alone
	#                 and let the tests read the variable themselves.
	#   Provisioned - no DATABASE_URL, but initdb is on PATH, so boot a
	#                 throwaway server and hand it to the tests.
	#   Unavailable - neither, so the Pg tests are skipped.
	pg =
		if have_db_url {
			Inherited
		} else if have_program!("initdb") {
			Provisioned
		} else {
			Unavailable
		}

	run_pg_tests =
		match pg {
			Unavailable => Bool.False
			_ => Bool.True
		}

	# Only the server we booted ourselves needs the variable injected. An
	# inherited one is in the environment the tests already get.
	test_env =
		match pg {
			Provisioned => SetEnv("DATABASE_URL", pg_url)
			_ => NoEnv
		}

	Stdout.line!("--- Unit tests")?
	for file in unit_files {
		code = roc_exit_code!(["test", file])?
		if code != 0 {
			Stderr.line!("FAILED: ${file}")?
			return Err(UnitTestsFailed(file))
		} else {}
	}

	Stdout.line!("")?
	Stdout.line!("--- Building server fixtures")?
	fixtures = list_roc_files!("tests/server_fixtures")?
	for fixture in fixtures {
		Stdout.line!("Building ${fixture.path}...")?
		binary = fixture.path.drop_suffix(".roc")
		# roc build exits 2 when there are only warnings; the binary is still
		# produced, so treat that as success.
		code = roc_exit_code!(["build", fixture.path, "--output=${binary}"])?
		if code != 0 and code != 2 {
			Stderr.line!("FAILED to build: ${fixture.path}")?
			return Err(FixtureBuildFailed(fixture.path))
		} else {}
	}

	server =
		match pg {
			Provisioned => {
				Stdout.line!("")?
				Stdout.line!("--- Starting a throwaway Postgres on port ${pg_port}")?
				Started(start_pg!(data)?)
			}

			_ => NoServer
		}

	Stdout.line!("")?
	Stdout.line!("--- Integration tests")?
	test_files = list_roc_files!("tests")?

	var $skipped = []
	var $failed = []

	for entry in test_files {
		is_test = entry.name.ends_with("_test.roc")
		is_pg = pg_tests.contains(entry.name)

		if !is_test {
			{}
		} else if is_pg and !run_pg_tests {
			$skipped = $skipped.append(entry.path)
		} else {
			Stdout.line!("Running ${entry.path}...")?
			run_result =
				if use_systemd {
					exit_code!("systemd-run", ["--scope", "--user", "roc", entry.path], test_env)
				} else {
					exit_code!("roc", [entry.path], test_env)
				}
			# A test killed by a signal (a panic, an OOM killer) leaves no exit
			# code to read. That is one failing test, not a reason to abandon
			# the ones that have not run yet, so it counts as a failure here
			# rather than propagating out of the loop.
			code =
				match run_result {
					Ok(exit_code) => exit_code
					Err(e) => {
						Stderr.line!("  no exit code: ${Str.inspect(e)}")?
						1
					}
				}
			if code != 0 {
				Stderr.line!("FAILED: ${entry.path}")?
				if fail_fast {
					Stderr.line!("Stopping due to --fail-fast")?
					stop_pg!(server)
					return Err(TestFailed(entry.path))
				} else {}
				$failed = $failed.append(entry.path)
			} else {}
		}
	}

	Stdout.line!("")?
	if !$skipped.is_empty() {
		Stdout.line!("Skipped (no DATABASE_URL, and no initdb on PATH to boot a server with):")?
		for t in $skipped {
			Stdout.line!("  - ${t}")?
		}
	} else {}

	stop_pg!(server)

	if $failed.is_empty() {
		Stdout.line!("All tests passed.")?
		Ok({})
	} else {
		Stderr.line!("Failed tests:")?
		for t in $failed {
			Stderr.line!("  - ${t}")?
		}
		Err(TestsFailed({ failed: $failed.len() }))
	}
}

## Boot a throwaway Postgres in `data`, wait for it to accept connections, and
## return the child so the suite can stop it with `stop_pg!` when it is done.
##
## The server runs in the foreground under `spawn_leashed!`, not through
## `pg_ctl start`. The leash takes down a process group, and `pg_ctl` calls
## `setsid()` before exec'ing the postmaster, which puts the postmaster in a
## session of its own where the leash cannot reach it. A foreground postmaster
## stays in the group, so `stop_pg!` takes it down when the suite finishes and
## the platform takes it down when the suite dies before reaching that.
##
## The pg_is_ready! guard below catches a server that reached the port from
## outside the leash, since reporting that beats deleting the data dir out from
## under a server still using it.
##
## `-A trust` takes authentication out of the picture, so the suite never
## negotiates a password and never depends on the host's pg_hba rules.
start_pg! : Str => Try(Cmd.Child, _)
start_pg! = |data| {
	if pg_is_ready!() {
		return Err(SomethingAlreadyOnPgPort(
			"port ${pg_port} is already answering, so something outside this suite is on it. Kill it, or set DATABASE_URL to reuse it.",
		))
	} else {}

	data_path = Path.utf8(data)
	if Path.exists!(data_path)? {
		Path.delete_all!(data_path)?
	} else {}

	must_run!("initdb", ["-D", data, "-U", pg_user, "-A", "trust"])?

	# The socket dir is pointed into the data dir because the default
	# (/run/postgresql) is not writable in CI or in the nix dev shell.
	#
	# logging_collector sends the server's log to <data>/log rather than to the
	# pipes spawn_leashed! hands back, which keeps it off the suite's output and
	# leaves it on disk for a post-mortem.
	child =
		Cmd.new(OsStr.utf8("postgres"))
			.args_str([
				"-D",
				data,
				"-p",
				pg_port,
				"-c",
				"listen_addresses=127.0.0.1",
				"-k",
				data,
				"-c",
				"logging_collector=on",
			])
			.spawn_leashed!()?

	wait_for_pg!(child, 200)?
	Ok(child)
}

## Take the throwaway server down, tree and all. A cleanup failure (say the
## server already died) is ignored rather than allowed to overwrite the
## suite's verdict.
stop_pg! : [Started(Cmd.Child), NoServer] => {}
stop_pg! = |server|
	match server {
		Started(child) =>
			match child.kill!() {
				Ok({}) => {}
				Err(_) => {}
			}

		NoServer => {}
	}

## Poll until the server answers, giving up after `attempts` tries.
##
## The child is polled alongside `pg_isready` so that a server which dies during
## startup (a taken port, a rejected option) is reported as that, rather than as
## a wait that ran out.
wait_for_pg! : Cmd.Child, U64 => Try({}, _)
wait_for_pg! = |child, attempts|
	if attempts == 0 {
		Err(PgNeverBecameReady)
	} else {
		match child.poll!()? {
			Exited(exit) => Err(PgDiedAtStartup({
				exit_code: exit.exit_code,
				stderr: Str.from_utf8_lossy(exit.stderr),
			}))
			Running => {
				if pg_is_ready!() {
					Ok({})
				} else {
					Sleep.millis!(50)
					wait_for_pg!(child, attempts - 1)
				}
			}
		}
	}

## Whether the throwaway server is accepting connections yet. The output is
## captured rather than inherited so the polling stays out of the suite's log.
pg_is_ready! : () => Bool
pg_is_ready! = ||
	Cmd.new(OsStr.utf8("pg_isready"))
		.args_str(["-h", "127.0.0.1", "-p", pg_port])
		.exec_output!()
		.is_ok()

## Whether `program` is on PATH and runnable.
have_program! : Str => Bool
have_program! = |program|
	Cmd.new(OsStr.utf8(program))
		.args([OsStr.utf8("--version")])
		.exec_output!()
		.is_ok()

## Run a command with stdio inherited, failing on a nonzero exit.
must_run! : Str, List(Str) => Try({}, _)
must_run! = |program, arguments| {
	code = exit_code!(program, arguments, NoEnv)?
	if code != 0 {
		Err(CommandFailed(program, code))
	} else {
		Ok({})
	}
}

## Run `roc` with the given arguments, stdio inherited, returning the exit code.
roc_exit_code! : List(Str) => Try(I32, _)
roc_exit_code! = |arguments| exit_code!("roc", arguments, NoEnv)

exit_code! : Str, List(Str), [SetEnv(Str, Str), NoEnv] => Try(I32, _)
exit_code! = |program, arguments, extra_env| {
	base = Cmd.new(OsStr.utf8(program)).args(arguments.map(OsStr.utf8))
	cmd =
		match extra_env {
			SetEnv(key, value) => base.env_str(key, value)
			NoEnv => base
		}
	cmd.exec_exit_code!()
}

## The .roc files directly inside `dir` (directory listing order), each with
## the filename that the platform's own separator rules give it.
##
## `Path.filename` is the separator-aware step, and it only works while the
## value is still a `Path`: a Windows listing hands back `Windows` paths
## joined with a backslash, which are just ordinary characters once
## `Path.display` has flattened them into a `Str`.
list_roc_files! : Str => Try(List({ path : Str, name : Str }), _)
list_roc_files! = |dir| {
	entries = Path.list!(Path.utf8(dir)) ? |e| FailedToListDir(dir, e)
	named =
		entries.map(
			|p| {
				path: Path.display(p),
				name: Path.filename(p).map_ok(|f| Path.display(f)).ok_or(Path.display(p)),
			},
		)
	Ok(named.keep_if(|entry| entry.name.ends_with(".roc")))
}
