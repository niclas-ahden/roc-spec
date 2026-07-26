app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
	spec: "../package/main.roc",
	pg: "https://github.com/niclas-ahden/roc-pg/releases/download/0.1.0/6AJ537Fhm4hhsgAERCmtJxWZ9mRfT6sa8ysZWNM1U4a4.tar.zst",
	db: "https://github.com/niclas-ahden/roc-database-url/releases/download/0.3.0/HTtdy7BMLHRmLiMfdTQbf4YYzDGi6ihuUibMVUx67n8d.tar.zst",
}

import pf.Env
import pf.Stdout
import pf.Tcp
import spec.Pg
import pg.Client
import pg.Cmd
import db.DatabaseUrl

tcp_effects = {
	connect!: Tcp.connect!,
	write!: Tcp.Stream.write!,
	read_exactly!: Tcp.Stream.read_exactly!,
	close!: Tcp.close!,
	pool!: Tcp.pool!,
	pool_acquire!: Tcp.pool_acquire!,
	pool_release!: Tcp.pool_release!,
}

query! = |client, sql|
	Client.command!(Cmd.new(sql), client).map_ok(|_| {})

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
				tcp_effects,
				{
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

	Client.close!(client)

	match result {
		Ok({}) =>
			Stdout.line!("PASS: rollback correctly prevented insert from persisting")

		Err(_) => {
			Stdout.line!("FAIL: insert failed - rollback did not work")?
			Err(RollbackDidNotWork)
		}
	}
}
