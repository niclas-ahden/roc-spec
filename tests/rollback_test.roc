app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	spec: "../package/main.roc",
	pg: "https://github.com/niclas-ahden/roc-pg/releases/download/0.2.0/EGCCBmR793d6wQJzX8aS9994n9nzz6dgMvhKuU6PqQ12.tar.zst",
	db: "https://github.com/niclas-ahden/roc-database-url/releases/download/0.4.0/6sKP47ivkLchhdvDMDe9ajVoiFPEP57ZgQoEy2WTDczX.tar.zst",
}

import pf.Env
import pf.Random
import pf.Stdout
import pf.Tcp
import spec.Pg
import pg.Client
import db.DatabaseUrl

query! = |client, sql|
	client.execute!(sql, []).map_ok(|_| {})

connect! = |{}| {
	url = Env.var_str!("DATABASE_URL") ? |_| MissingEnvVar("DATABASE_URL must be set (e.g. postgresql://user:pass@localhost:5432/dbname)")
	parsed = DatabaseUrl.parse(url) ? |e| InvalidDatabaseUrl(e)
	match parsed {
		PostgreSQL(config) => {
			auth = match config.auth {
				Password(p) => Password(p)
				NoPassword => NoAuth
			}
			Client.connect!(
				{
					connect!: Tcp.connect!,
					random_u64!: Random.seed_u64!,
					host: config.host,
					port: config.port,
					user: config.user,
					database: config.database,
					auth,
					timeout_ms: 5000,
				},
			)
		}

		_ => Err(ExpectedPostgresUrl)
	}
}

main! = |_args| {
	client = connect!({})?

	# Create a test table with a unique constraint
	query!(client, "CREATE TABLE IF NOT EXISTS rollback_test (id SERIAL PRIMARY KEY, key TEXT UNIQUE)")?

	# Clean up any previous test data
	query!(client, "DELETE FROM rollback_test")?

	# Run test with rollback - the insert should NOT persist. The client is a
	# single connection, so BEGIN, INSERT, and ROLLBACK issued by separate
	# query! calls share one session (unlike the old psql-based hook, which
	# opened a new session per call).
	Pg.with_rollback!(
		query!,
		client,
		|inner| {
			query!(inner, "INSERT INTO rollback_test (key) VALUES ('unique_key')")?
			Ok({})
		},
	)?

	# If rollback worked, we should be able to insert the same key again
	# (If it didn't rollback, this would fail with a unique constraint violation)
	result = query!(client, "INSERT INTO rollback_test (key) VALUES ('unique_key')")

	client.close!()

	match result {
		Ok({}) =>
			Stdout.line!("PASS: rollback correctly prevented insert from persisting")

		Err(_) => {
			Stdout.line!("FAIL: insert failed - rollback did not work")?
			Err(RollbackDidNotWork)
		}
	}
}
