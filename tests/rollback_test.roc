app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	spec: "../package/main.roc",
	pg: "https://github.com/niclas-ahden/roc-pg/releases/download/0.5.0/3RhKioDLx8pWHv72xyu4Dc3U3xyWQiAokmBXyezbPSxr.tar.zst",
	db: "https://github.com/niclas-ahden/roc-database-url/releases/download/0.4.1/3tFBYWq9eBxjJe9FZJLbuQtUaFBrz3ykK2QDooeFM9Fy.tar.zst",
}

import pf.Duration
import pf.Env
import pf.Random
import pf.Stdout
import pf.Tcp
import spec.Pg
import pg.Client
import db.DatabaseUrl

query! = |client, sql|
	client.execute_unchecked!(sql, []).map_ok(|_| {})

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
					connect!: |host, port| Tcp.connect!(host, port, { connect_timeout: Duration.seconds(5), io_timeout: Duration.seconds(35) }),
					random_u64!: Random.seed_u64!,
					host: config.host,
					port: config.port,
					user: config.user,
					database: config.database,
					auth,
					statement_timeout: Duration.seconds(30),
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
