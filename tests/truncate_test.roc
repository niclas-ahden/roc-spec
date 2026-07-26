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

	# Create test tables with unique constraints
	query!(client, "CREATE TABLE IF NOT EXISTS truncate_test (id SERIAL PRIMARY KEY, key TEXT UNIQUE)")?
	query!(client, "CREATE TABLE IF NOT EXISTS truncate_excluded (id SERIAL PRIMARY KEY, key TEXT UNIQUE)")?

	# Insert test data
	query!(client, "DELETE FROM truncate_test")?
	query!(client, "DELETE FROM truncate_excluded")?
	query!(client, "INSERT INTO truncate_test (key) VALUES ('test_key')")?
	query!(client, "INSERT INTO truncate_excluded (key) VALUES ('excluded_key')")?

	# Truncate all tables except truncate_excluded
	Pg.truncate!(query!, client, ["truncate_excluded"])?

	# Verify truncate_test was cleared (can insert same key again)
	truncate_result = query!(client, "INSERT INTO truncate_test (key) VALUES ('test_key')")

	# Verify truncate_excluded was NOT cleared (inserting same key should fail)
	excluded_result = query!(client, "INSERT INTO truncate_excluded (key) VALUES ('excluded_key')")

	Client.close!(client)

	match (truncate_result, excluded_result) {
		(Ok({}), Err(_)) =>
			Stdout.line!("PASS: truncate cleared table but preserved excluded table")

		(Err(_), Err(_)) => {
			Stdout.line!("FAIL: truncate_test was not cleared")?
			Err(TruncateDidNotClearTable)
		}

		(Err(_), Ok({})) => {
			Stdout.line!("FAIL: truncate_test was not cleared")?
			Err(TruncateDidNotClearTable)
		}

		(Ok({}), Ok({})) => {
			Stdout.line!("FAIL: truncate_excluded was cleared but should have been preserved")?
			Err(ExcludedTableWasCleared)
		}
	}
}
