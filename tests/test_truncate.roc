app [main!] {
    pf: platform "../../growthagent/basic-cli/platform/main.roc",
    pg: "https://github.com/growthagent/roc-pg/releases/download/0.7.0/X06BecFGCZlH_7YhdTQmN6PtxgYDRH2ykIH30obB0lg.tar.br",
    dburl: "https://github.com/niclas-ahden/roc-database-url/releases/download/0.1.0/w6sV-GxFqFo8cGOC8oxam_-TZAQkjjRKFamcqZfftbY.tar.br",
    spec: "../package/main.roc",
}

import pf.Arg
import pf.Env
import pf.Stdout

import pg.Pg.Client
import pg.Pg.Cmd

import dburl.DatabaseUrl

import spec.Pg

main! : List Arg.Arg => Result {} _
main! = |_args|
    config = parse_database_url!({})?

    client = Pg.Client.connect!(config)?

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

    when (truncate_result, excluded_result) is
        (Ok({}), Err(_)) ->
            Stdout.line!("PASS: truncate cleared table but preserved excluded table")

        (Err(_), Err(_)) ->
            Stdout.line!("FAIL: truncate_test was not cleared")?
            Err(TruncateDidNotClearTable)

        (Err(_), Ok({})) ->
            Stdout.line!("FAIL: truncate_test was not cleared")?
            Err(TruncateDidNotClearTable)

        (Ok({}), Ok({})) ->
            Stdout.line!("FAIL: truncate_excluded was cleared but should have been preserved")?
            Err(ExcludedTableWasCleared)

parse_database_url! : {} => Result { host : Str, port : U16, user : Str, auth : [None, Password Str], database : Str } _
parse_database_url! = |{}|
    url = Env.var!("DATABASE_URL")
        |> Result.map_err(|_| MissingEnvVar("DATABASE_URL must be set (e.g. postgresql://user:pass@localhost:5432/dbname)"))?

    when DatabaseUrl.parse(url) is
        Ok(PostgreSQL(config)) -> Ok({ host: config.host, port: config.port, user: config.user, auth: config.auth, database: config.database })
        Ok(_) -> Err(InvalidDatabaseUrl("DATABASE_URL must be a PostgreSQL URL"))
        Err(err) -> Err(InvalidDatabaseUrl("Failed to parse DATABASE_URL: $(Inspect.to_str(err))"))

query! : Pg.Client.Client, Str => Result {} _
query! = |db, sql|
    Pg.Cmd.new(sql)
    |> Pg.Client.command!(db)
    |> Result.map_ok(|_| {})
