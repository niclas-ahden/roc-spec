## PostgreSQL test helpers.
##
## These functions generate PostgreSQL-specific SQL for test database management.
## They accept a generic `db` connection and a `query!` function, making them
## compatible with any PostgreSQL client library.
##
## Example with roc-pg:
## ```roc
## import pg.Client
## import pg.Cmd
## import spec.Pg
##
## query! = |client, sql|
##     Client.command!(Cmd.new(sql), client).map_ok(|_| {})
##
## Pg.with_truncate!(query!, client, ["schema_migrations"], |client|
##     # test code
## )
## ```
import TestEnvironment

Pg :: [].{

	## The settings `worker_db!` reads out of the environment and hands to your
	## `pg_connect!`.
	##
	## `auth` uses the same `[Password(Str), NoPassword]` shape as
	## roc-database-url rather than any one client's tag names, so map it to
	## whatever your client wants (roc-pg calls the empty case `NoAuth`).
	Connection : {
		host : Str,
		port : U16,
		user : Str,
		database : Str,
		auth : [Password(Str), NoPassword],
	}

	## Connect to the current worker's isolated database, named
	## `$ROC_SPEC_BASE_DATABASE_NAME_$WORKER_INDEX` (e.g. `myapp_test_3`).
	## `WORKER_INDEX` defaults to 0 for sequential/single-worker tests.
	##
	## Connection settings come from `PG_HOST`, `PG_PORT` and `PG_USER`, which
	## must be set, and from `PG_PASSWORD`, which is optional: unset means
	## `NoPassword`, for the trust or peer authentication a local test database
	## usually runs with.
	##
	## Effects used: `{ env_var!, pg_connect! }`. Your `pg_connect!` adapts the
	## [Connection] to your client's own connect function, which is where a
	## client-specific setting like roc-pg's `timeout_ms` goes:
	##
	## ```roc
	## db = Pg.worker_db!({
	##     env_var!: Env.var_str!,
	##     pg_connect!: |{ host, port, user, database, auth }|
	##         Client.connect!(tcp_effects, {
	##             host,
	##             port,
	##             user,
	##             database,
	##             auth: match auth {
	##                 Password(p) => Password(p)
	##                 NoPassword => NoAuth
	##             },
	##             timeout_ms: 5_000,
	##         }),
	## })?
	## ```
	worker_db! : _ => Try(ok, TestEnvironment.EnvError(err))
	worker_db! = |effects| {
		env_var! = effects.env_var!
		pg_connect! = effects.pg_connect!

		base_db_name = env_var!("ROC_SPEC_BASE_DATABASE_NAME") ? |_| EnvVarNotSet("ROC_SPEC_BASE_DATABASE_NAME")
		worker_index = TestEnvironment.worker_index!({ env_var!: env_var! })?
		db_name = "${base_db_name}_${worker_index.to_str()}"

		host = env_var!("PG_HOST") ? |_| EnvVarNotSet("PG_HOST")
		port_str = env_var!("PG_PORT") ? |_| EnvVarNotSet("PG_PORT")
		port = U16.from_str(port_str) ? |_| InvalidEnvVar("PG_PORT")
		user = env_var!("PG_USER") ? |_| EnvVarNotSet("PG_USER")

		# Optional, unlike the rest: a test database reached over trust or peer
		# auth has no password, and demanding an empty one would be noise.
		auth =
			match env_var!("PG_PASSWORD") {
				Ok(password) => Password(password)
				Err(_) => NoPassword
			}

		pg_connect!({ host, port, user, database: db_name, auth })
	}

	## Begin a database transaction.
	begin! : (db, Str => Try({}, err)), db => Try({}, err)
	begin! = |query!, db|
		query!(db, "BEGIN")

	## Rollback a database transaction.
	rollback! : (db, Str => Try({}, err)), db => Try({}, err)
	rollback! = |query!, db|
		query!(db, "ROLLBACK")

	## Commit a database transaction.
	commit! : (db, Str => Try({}, err)), db => Try({}, err)
	commit! = |query!, db|
		query!(db, "COMMIT")

	## Run a function inside a transaction that always rolls back.
	## Useful for tests that shouldn't persist data.
	##
	## The body's result wins: if the test fails and the `ROLLBACK` also fails,
	## you get the test's error, since that is the one that says what broke.
	## A failing `ROLLBACK` is only reported when the body itself succeeded.
	##
	## ```roc
	## Pg.with_rollback!(query!, client, |client|
	##     # test code that modifies db
	##     Ok(result)
	## )
	## ```
	with_rollback! : (db, Str => Try({}, err)), db, (db => Try(a, err)) => Try(a, err)
	with_rollback! = |query!, db, body!| {
		Pg.begin!(query!, db)?
		result = body!(db)
		# Always rollback, regardless of result
		rollback_result = Pg.rollback!(query!, db)

		match result {
			Err(_) => result
			Ok(_) =>
				match rollback_result {
					Err(e) => Err(e)
					Ok({}) => result
				}
			}
	}

	## Truncate all tables in the database except for excluded ones.
	## Useful for resetting database state between tests.
	##
	## ```roc
	## Pg.truncate!(query!, client, ["schema_migrations"])?
	## ```
	##
	## This will:
	## - Find all tables in the 'public' schema
	## - Exclude tables in the provided list
	## - TRUNCATE them with RESTART IDENTITY CASCADE
	truncate! : (db, Str => Try({}, err)), db, List(Str) => Try({}, err)
	truncate! = |query!, db, excluded_tables| {
		# Build the exclusion clause for SQL
		exclusion_clause =
			if excluded_tables.is_empty() {
				""
			} else {
				exclusion_list =
					excluded_tables
					# Double any single quote: the names are interpolated
					# into SQL as literals, and quote_literal cannot help
					# here since the name has to travel into the query
					# safely before the server could quote it.
						.map(|t| "'${t.replace_each("'", "''")}'")
						->Str.join_with(", ")
				"AND tablename NOT IN (${exclusion_list})"
			}

		# Use DO block to dynamically build and execute TRUNCATE
		sql =
			\\DO $$
			\\DECLARE
			\\    tables_to_truncate TEXT;
			\\BEGIN
			\\    SELECT string_agg(quote_ident(tablename), ', ')
			\\    INTO tables_to_truncate
			\\    FROM pg_tables
			\\    WHERE schemaname = 'public'
			\\    ${exclusion_clause};
			\\
			\\    IF tables_to_truncate IS NOT NULL AND tables_to_truncate != '' THEN
			\\        EXECUTE 'TRUNCATE ' || tables_to_truncate || ' RESTART IDENTITY CASCADE';
			\\    END IF;
			\\END $$;

		query!(db, sql)
	}

	## Run a test with a truncated database.
	## Useful for HTTP integration tests where rollback doesn't work
	## (because the app server has a separate DB connection).
	##
	## ```roc
	## Pg.with_truncate!(query!, client, ["schema_migrations"], |client|
	##     # insert test data
	##     # run test
	##     Ok(result)
	## )
	## ```
	with_truncate! : (db, Str => Try({}, err)), db, List(Str), (db => Try(a, err)) => Try(a, err)
	with_truncate! = |query!, db, excluded_tables, body!| {
		Pg.truncate!(query!, db, excluded_tables)?
		body!(db)
	}
}
