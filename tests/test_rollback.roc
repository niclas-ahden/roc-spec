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

    # Create a test table with a unique constraint
    query!(client, "CREATE TABLE IF NOT EXISTS rollback_test (id SERIAL PRIMARY KEY, key TEXT UNIQUE)")?

    # Clean up any previous test data
    query!(client, "DELETE FROM rollback_test")?

    # Run test with rollback - insert should NOT persist
    Pg.with_rollback!(query!, client, |db|
        query!(db, "INSERT INTO rollback_test (key) VALUES ('unique_key')")?
        Ok({})
    )?

    # If rollback worked, we should be able to insert the same key again
    # (If it didn't rollback, this would fail with a unique constraint violation)
    result = query!(client, "INSERT INTO rollback_test (key) VALUES ('unique_key')")

    when result is
        Ok({}) ->
            Stdout.line!("PASS: rollback correctly prevented insert from persisting")

        Err(_) ->
            Stdout.line!("FAIL: insert failed - rollback did not work")?
            Err(RollbackDidNotWork)

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
