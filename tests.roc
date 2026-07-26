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
## The PostgreSQL tests are skipped unless DATABASE_URL is set (skips are
## listed in the summary so a green run still shows what it did not cover):
##
##     DATABASE_URL=postgresql://user:pass@localhost:5432/roc_spec_test ./tests.roc
##
## Pass --fail-fast to stop at the first failing test.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr exposing [OsStr]
import pf.Path
import pf.Stderr
import pf.Stdout

unit_files : List(Str)
unit_files = ["package/Assert.roc", "package/Format.roc"]

## Need DATABASE_URL; skipped when it is not set.
pg_tests : List(Str)
pg_tests = ["tests/rollback_test.roc", "tests/truncate_test.roc"]

main! = |os_args| {
	fail_fast = os_args.any(|a| OsStr.display(a) == "--fail-fast")

	have_db = Env.var_str!(OsStr.utf8("DATABASE_URL")).is_ok()

	# systemd scope when available (ensures all descendant processes die with
	# the test); fall back to a plain spawn in CI where no user session exists.
	use_systemd =
		Cmd.new(OsStr.utf8("systemctl"))
			.args([OsStr.utf8("--user"), OsStr.utf8("show-environment")])
			.exec_output!()
			.is_ok()

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
		Stdout.line!("Building ${fixture}...")?
		binary = fixture.drop_suffix(".roc")
		# roc build exits 2 when there are only warnings; the binary is still
		# produced, so treat that as success.
		code = roc_exit_code!(["build", fixture, "--output=${binary}"])?
		if code != 0 and code != 2 {
			Stderr.line!("FAILED to build: ${fixture}")?
			return Err(FixtureBuildFailed(fixture))
		} else {}
	}

	Stdout.line!("")?
	Stdout.line!("--- Integration tests")?
	test_files = list_roc_files!("tests")?

	var $skipped = []
	var $failed = []

	for file in test_files {
		basename = file.split_on("/").last().ok_or(file)
		is_test = basename.ends_with("_test.roc")
		is_pg = pg_tests.contains(file)

		if !is_test {
			{}
		} else if is_pg and !have_db {
			$skipped = $skipped.append(file)
		} else {
			Stdout.line!("Running ${file}...")?
			run_result =
				if use_systemd {
					exit_code!("systemd-run", ["--scope", "--user", "roc", file])
				} else {
					roc_exit_code!([file])
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
				Stderr.line!("FAILED: ${file}")?
				if fail_fast {
					Stderr.line!("Stopping due to --fail-fast")?
					return Err(TestFailed(file))
				} else {}
				$failed = $failed.append(file)
			} else {}
		}
	}

	Stdout.line!("")?
	if !$skipped.is_empty() {
		Stdout.line!("Skipped (DATABASE_URL not set):")?
		for t in $skipped {
			Stdout.line!("  - ${t}")?
		}
	} else {}

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

## Run `roc` with the given arguments, stdio inherited, returning the exit code.
roc_exit_code! : List(Str) => Try(I32, _)
roc_exit_code! = |arguments| exit_code!("roc", arguments)

exit_code! : Str, List(Str) => Try(I32, _)
exit_code! = |program, arguments|
	Cmd.new(OsStr.utf8(program))
		.args(arguments.map(OsStr.utf8))
		.exec_exit_code!()

## The .roc files directly inside `dir` (directory listing order).
list_roc_files! : Str => Try(List(Str), _)
list_roc_files! = |dir| {
	entries = Path.list!(Path.utf8(dir)) ? |e| FailedToListDir(dir, e)
	Ok(entries.map(|p| Path.display(p)).keep_if(|name| name.ends_with(".roc")))
}
