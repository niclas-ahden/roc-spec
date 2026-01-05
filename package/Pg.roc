## PostgreSQL test helpers.
##
## These functions generate PostgreSQL-specific SQL for test database management.
## They accept a generic `db` connection and a `query!` function, making them
## compatible with any PostgreSQL client library.
##
## Example with roc-pg:
## ```roc
## import pg.Pg.Client
## import pg.Pg.Cmd
## import spec.Pg
##
## query! = |client, sql|
##     Pg.Cmd.new(sql) |> Pg.Client.command!(client) |> Result.map_ok(|_| {})
##
## Pg.with_truncate!(query!, client, ["schema_migrations"], |client|
##     # test code
## )
## ```
module [begin!, rollback!, commit!, with_rollback!, truncate!, with_truncate!]

## Begin a database transaction.
begin! : (db, Str => Result {} err), db => Result {} err
begin! = |query!, db|
    query!(db, "BEGIN")

## Rollback a database transaction.
rollback! : (db, Str => Result {} err), db => Result {} err
rollback! = |query!, db|
    query!(db, "ROLLBACK")

## Commit a database transaction.
commit! : (db, Str => Result {} err), db => Result {} err
commit! = |query!, db|
    query!(db, "COMMIT")

## Run a function inside a transaction that always rolls back.
## Useful for tests that shouldn't persist data.
##
## ```roc
## Pg.with_rollback!(query!, client, |client|
##     # test code that modifies db
##     Ok(result)
## )
## ```
with_rollback! : (db, Str => Result {} err), db, (db => Result a err) => Result a err
with_rollback! = |query!, db, body!|
    begin!(query!, db)?
    result = body!(db)
    # Always rollback, regardless of result
    rollback!(query!, db)?
    result

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
truncate! : (db, Str => Result {} err), db, List Str => Result {} err
truncate! = |query!, db, excluded_tables|
    # Build the exclusion clause for SQL
    exclusion_clause =
        if List.is_empty(excluded_tables) then
            ""
        else
            exclusion_list =
                excluded_tables
                |> List.map(|t| "'$(t)'")
                |> Str.join_with(", ")
            "AND tablename NOT IN ($(exclusion_list))"

    # Use DO block to dynamically build and execute TRUNCATE
    sql =
        """
        DO $$
        DECLARE
            tables_to_truncate TEXT;
        BEGIN
            SELECT string_agg(quote_ident(tablename), ', ')
            INTO tables_to_truncate
            FROM pg_tables
            WHERE schemaname = 'public'
            $(exclusion_clause);

            IF tables_to_truncate IS NOT NULL AND tables_to_truncate != '' THEN
                EXECUTE 'TRUNCATE ' || tables_to_truncate || ' RESTART IDENTITY CASCADE';
            END IF;
        END $$;
        """

    query!(db, sql)

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
with_truncate! : (db, Str => Result {} err), db, List Str, (db => Result a err) => Result a err
with_truncate! = |query!, db, excluded_tables, body!|
    truncate!(query!, db, excluded_tables)?
    body!(db)
