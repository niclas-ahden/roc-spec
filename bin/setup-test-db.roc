#!/usr/bin/env roc
## Create the PostgreSQL database that the `Pg` tests need, if it is not
## already there.
##
##     DATABASE_URL=postgresql://user:pass@localhost:5432/roc_spec_test ./bin/setup-test-db.roc
##
## Connects to the server's own `postgres` database to do it, since the
## database we are about to create cannot be connected to yet. Shells out to
## `psql` rather than using roc-pg, so that setting up the test database does
## not depend on the package the tests are testing.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
	db: "https://github.com/niclas-ahden/roc-database-url/releases/download/0.3.0/HTtdy7BMLHRmLiMfdTQbf4YYzDGi6ihuUibMVUx67n8d.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Stderr
import pf.Stdout
import db.DatabaseUrl

main! = |_args| {
	url =
		Env.var_str!(OsStr.utf8("DATABASE_URL"))
			? |_| MissingEnvVar("DATABASE_URL must be set, e.g. postgresql://user@localhost:5432/roc_spec_test")

	config =
		match DatabaseUrl.parse(url) ? |e| InvalidDatabaseUrl(e) {
			PostgreSQL(c) => Ok(c)
			# The tests speak the PostgreSQL wire protocol, so anything else is
			# a typo rather than a setup we could honour.
			_ => Err(NotPostgres("DATABASE_URL must be a postgresql:// URL"))
		}?

	if exists!(config)? {
		Stdout.line!("Database '${config.database}' already exists.")
	} else {
		create!(config)?
		Stdout.line!("Database '${config.database}' created.")
	}
}

## Whether the target database is already on the server.
exists! = |config| {
	# Single-quote inside an identifier is legal in PostgreSQL, and this name
	# travels as a string literal, so double any quote it contains.
	quoted = config.database.replace_each("'", "''")
	output = psql!(config, "SELECT 1 FROM pg_database WHERE datname = '${quoted}'")?
	Ok(output.stdout_utf8.trim() == "1")
}

## Create the target database.
create! = |config| {
	# The name is an identifier here rather than a literal, so it is
	# double-quoted, and any double quote in it is doubled.
	quoted = config.database.replace_each("\"", "\"\"")
	_ = psql!(config, "CREATE DATABASE \"${quoted}\"")?
	Ok({})
}

## Run one statement against the server's `postgres` database.
##
## `-t` and `-A` strip the header, padding and row count that `psql` prints by
## default, so a result is exactly the value and nothing else.
psql! = |config, sql| {
	base =
		Cmd.new(OsStr.utf8("psql"))
			.args_str([
				"--host=${config.host}",
				"--port=${config.port.to_str()}",
				"--username=${config.user}",
				"--dbname=postgres",
				"-tAc",
				sql,
			])

	cmd =
		match config.auth {
			Password(password) => base.env_str("PGPASSWORD", password)
			NoPassword => base
		}

	match cmd.exec_output!() {
		Ok(output) => Ok(output)
		Err(e) => {
			Stderr.line!("psql failed: ${Str.inspect(e)}")?
			Err(PsqlFailed(e))
		}
	}
}
