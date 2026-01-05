## Test environment utilities for integration tests with isolated workers.
##
## Provides two sets of functionality:
##
## 1. **For test runners**: `start!` to spawn N isolated worker environments
## 2. **For individual tests**: `with!`, `with_db!`, `fetch!`, `command!` to access worker context
##
## When `WORKER_INDEX` env var is not set, defaults to 0. This allows using
## these helpers in sequential (non-parallel) tests.
##
## Required environment variables for parallel execution:
## - `WORKER_INDEX`: Current worker number (0, 1, 2, ...) - defaults to 0 if not set
## - `ROC_SPEC_BASE_PORT`: Base port number (worker port = base + index)
## - `ROC_SPEC_BASE_DATABASE_NAME`: Base database name (db = base_index)
## - `ROC_SPEC_HOST`: Hostname for URLs (default: "localhost")
## - `PG_HOST`, `PG_PORT`, `PG_USER`: PostgreSQL connection settings
##
## Example test file:
## ```roc
## import spec.TestEnvironment { ... }
## import spec.Assert
##
## main! = |_args|
##     TestEnvironment.with_db!(|{ worker_url, db }|
##         # Create test data
##         TestEnvironment.command!(db, "INSERT INTO users (name) VALUES ('test')")?
##
##         # Make HTTP request
##         body = TestEnvironment.fetch!("$(worker_url)/users")?
##
##         Assert.true(Str.contains(body, "test"))?
##         Ok({})
##     )
## ```
module { env_var!, pg_connect!, pg_cmd_new, pg_client_command!, http_send!, http_header } -> [
    start!,
    with!,
    with_db!,
    command!,
    fetch!,
    worker_url!,
    worker_db!,
]

## Start N isolated test environments by calling the start! callback for each index.
##
## The callback should spawn any processes needed (app server, reverse proxy, etc.)
## and wait until they're healthy before returning. Use `Cmd.spawn_grouped!` to ensure
## processes are automatically cleaned up when the test runner exits.
##
## ```roc
## TestEnvironment.start!({
##     count: 32,
##     start!: |index|
##         port = 8000 + index
##         Cmd.new("./server") |> Cmd.env("PORT", Num.to_str(port)) |> Cmd.spawn_grouped!()?
##         Wait.for_server!("http://localhost:$(Num.to_str(port))/health")
## })?
## ```
start! : { count : U16, start! : U16 => Result {} err } => Result {} err
start! = |{ count, start! : inner_start! }|
    List.range({ start: At(0), end: Before(count) })
        |> List.for_each_try!(inner_start!)

## Run a test that only needs the worker URL (no database).
##
## ```roc
## TestEnvironment.with!(|worker_url|
##     body = TestEnvironment.fetch!("$(worker_url)/health")?
##     Assert.true(Str.contains(body, "ok"))?
##     Ok({})
## )
## ```
with! = |test!|
    url = worker_url!({})?
    test!(url)

## Run a test that needs both worker URL and database connection.
##
## ```roc
## TestEnvironment.with_db!(|{ worker_url, db }|
##     # Insert test data
##     TestEnvironment.command!(db, "INSERT INTO items (name) VALUES ('test')")?
##
##     # Verify via HTTP
##     body = TestEnvironment.fetch!("$(worker_url)/items")?
##     Assert.true(Str.contains(body, "test"))?
##     Ok({})
## )
## ```
with_db! = |test!|
    url = worker_url!({})?
    db = worker_db!({})?
    test!({ worker_url: url, db })

## Execute a database command (INSERT/UPDATE/DELETE). Discards results.
##
## ```roc
## TestEnvironment.command!(db, "DELETE FROM sessions WHERE expired = true")?
## ```
command! : _, Str => Result {} _
command! = |db, sql|
    pg_cmd_new(sql)
    |> pg_client_command!(db)
    |> Result.map_ok(|_| {})

## Fetch a URL and return the response body as a string.
## Automatically sets the Host header for reverse proxy routing.
##
## Returns error for non-2xx status codes.
##
## ```roc
## body = TestEnvironment.fetch!("$(worker_url)/api/users")?
## ```
fetch! : Str => Result Str _
fetch! = |url|
    # Extract host:port from URL for Host header
    # URL format: http://hostname:PORT/path
    host_with_port =
        url
        |> Str.replace_first("http://", "")
        |> Str.split_first("/")
        |> Result.map_ok(|{ before }| before)
        |> Result.with_default("localhost")

    request = {
        method: GET,
        headers: [http_header(("Host", host_with_port))],
        uri: url,
        body: [],
        timeout_ms: TimeoutMilliseconds(10000),
    }

    response = http_send!(request)?
    body = Str.from_utf8(response.body) |> Result.with_default("")

    # Check for non-2xx status codes
    if response.status < 200 || response.status >= 300 then
        preview = body |> Str.to_utf8 |> List.take_first(500) |> Str.from_utf8 |> Result.with_default("")
        Err(HttpError(response.status, url, preview))
    else
        Ok(body)

## Get the worker URL for the current worker index.
## Reads from ROC_SPEC_BASE_PORT, WORKER_INDEX, and optionally ROC_SPEC_HOST.
## If WORKER_INDEX is not set, defaults to 0 (for sequential/single-worker tests).
worker_url! : {} => Result Str _
worker_url! = |{}|
    base_port =
        env_var!("ROC_SPEC_BASE_PORT")
        |> Result.map_err(|_| EnvVarNotSet("ROC_SPEC_BASE_PORT"))?
        |> Str.to_u16
        |> Result.map_err(|_| InvalidEnvVar("ROC_SPEC_BASE_PORT"))?

    worker_index = get_worker_index!({})

    # Host is optional, defaults to "localhost"
    host =
        when env_var!("ROC_SPEC_HOST") is
            Ok(h) -> h
            Err(_) -> "localhost"

    port = base_port + worker_index
    Ok("http://$(host):$(Num.to_str(port))")

## Connect to the worker's isolated database.
## Reads from ROC_SPEC_BASE_DATABASE_NAME, WORKER_INDEX, PG_HOST, PG_PORT, PG_USER.
## If WORKER_INDEX is not set, defaults to 0 (for sequential/single-worker tests).
worker_db! : {} => Result _ _
worker_db! = |{}|
    base_db_name = env_var!("ROC_SPEC_BASE_DATABASE_NAME") |> Result.map_err(|_| EnvVarNotSet("ROC_SPEC_BASE_DATABASE_NAME"))?
    worker_index = get_worker_index!({})
    db_name = "$(base_db_name)_$(Num.to_str(worker_index))"

    host = env_var!("PG_HOST") |> Result.map_err(|_| EnvVarNotSet("PG_HOST"))?
    port = env_var!("PG_PORT") |> Result.map_err(|_| EnvVarNotSet("PG_PORT"))? |> Str.to_u16 |> Result.map_err(|_| InvalidEnvVar("PG_PORT"))?
    user = env_var!("PG_USER") |> Result.map_err(|_| EnvVarNotSet("PG_USER"))?

    pg_connect!({ host, port, user, database: db_name, auth: None })

## Get worker index from environment, defaulting to 0 if not set.
## This allows TestEnvironment helpers to work in both parallel and sequential tests.
get_worker_index! : {} => U16
get_worker_index! = |{}|
    when env_var!("WORKER_INDEX") is
        Ok(s) ->
            when Str.to_u16(s) is
                Ok(n) -> n
                Err(_) -> 0
        Err(_) -> 0
