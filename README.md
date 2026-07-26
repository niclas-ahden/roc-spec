# roc-spec

A Roc package for writing and running parallel tests with isolated test environments. Includes hooks for setup/teardown and utilities like database helpers, waiting for web servers to start etc.

## How it works

1. Write test files named `*_test.roc` in a directory.
2. Each test file is a standalone Roc app that exits 0 on success, non-zero on failure.
3. `Spec.run!` discovers and runs them in parallel with isolated worker environments.

`Spec` takes an `effects` record of platform functions as its first argument. Build it once from your platform's modules and pass it along. Typically you'd put that record in a helper module that you import in all of your tests to avoid duplication.

## Example test file

```roc
# tests/math_test.roc
app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst" }

main! = |_|
    if 1 + 1 == 2 {
        Ok({})
    } else {
        Err(AdditionBroken)
    }
```

## Example test runner

```roc
# run_tests.roc
app [main!] {
    pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
    spec: "../roc-spec/package/main.roc",
}

import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stdout
import pf.Utc
import spec.Spec

effects = {
    # Start one test file as its own process group, with the given env vars.
    spawn_test!: |file, envs|
        Cmd.new(OsStr.utf8("roc"))
            .args_str(["--opt=speed", file])
            .envs_str(envs)
            .spawn_grouped!(),
    poll!: Cmd.Child.poll!,
    kill_wait!: Cmd.Child.kill_wait!,
    # List a dir as `List(Str)`
    list_dir!: |dir| Path.list!(Path.utf8(dir)).map_ok(|entries| entries.map(Path.display)),
    print!: Stdout.line!,
    utc_now!: Utc.now!,
    sleep_millis!: Sleep.millis!,
}

main! = |_args| {
    results = Spec.run!(effects, "tests", {
        max_workers: 8,
        worker_envs: |index| [("ROC_SPEC_WORKER", index.to_str())],
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 120_000,
        quiet: Bool.True,
        fail_fast: Bool.False,
    })?

    passed = results.count_if(|r| r.passed)
    total = results.len()

    Stdout.line!("${passed.to_str()}/${total.to_str()} tests passed")?

    if passed == total {
        Ok({})
    } else {
        Err(TestsFailed)
    }
}
```

Use `Spec.run_filtered!(effects, "tests", config, "math")` to run only the tests whose name contains a given substring. A test's name is its path relative to the test directory, so `"payments/"` runs every test under that directory and `"payments/invoice"` runs `invoice_created_test.roc`, `invoice_paid_test.roc`, and so on. See `examples/` for runnable versions of both.

A test directory that cannot be listed is an error (`TestDirNotFound`) rather than an empty run, so a typo'd path can never produce a green "0/0 passed".

The `spawn_test!` effect above runs each test file with `roc --opt=speed`, so your tests run compiled. Feel free to change the command as you please. You could for example wrap tests in e.g. `systemd-run` for even better control, or run something that is not `roc` at all. Spawn grouped, so that a test killed on timeout takes its descendants with it.

## Spawning a server in a test

```roc
import spec.Server

server_effects = {
    env_var!: Env.var_str!,
    # Start the server as its own process group on the given port. Set the
    # env vars your server reads its port from.
    spawn_server!: |cmd, port|
        cmd
            ->Cmd.env_str("PORT", port)
            ->Cmd.env_str("ROC_BASIC_WEBSERVER_PORT", port)
            ->Cmd.spawn_grouped!(),
    kill!: Cmd.Child.kill!,
    poll!: Cmd.Child.poll!,
    http_get!: |url| Http.get_utf8!(Url.parse(url) ? InvalidUrl),
    sleep!: Sleep.millis!,
}

main! = |_args|
    Server.with!(server_effects, Cmd.new("./my-server"), |base_url| {
        body = Http.get_utf8!(Url.parse("${base_url}/health") ? InvalidUrl)?
        Assert.eq(body, "ok")
    })
```

`Server.with!` waits for the server to answer, runs your callback, and kills the server afterwards even if the callback failed.

It takes the address from the same worker environment `TestEnvironment` reads: the port is `ROC_SPEC_BASE_PORT + WORKER_INDEX` and the host is `ROC_SPEC_HOST` (default `localhost`), so set those in `worker_envs` and every worker gets its own port. A test run on its own has no runner to set that up, so there the port comes from `PORT`, default 8000.

When the address a test reaches the server on is not the one that convention describes - a reverse proxy, a vhost, TLS on a different port - pass it in with `Server.with_address!`:

```roc
Server.with_address!(server_effects, Cmd.new("./my-server"), {
    base_url: "https://shop.example.test",
    port: "8443",
    max_attempts: 150,
    delay_ms: 200,
}, |base_url| { ... })
```

`base_url` is what your callback receives and what readiness polls; `port` is what `spawn_server!` receives.

## Using `Assert` in test files

For cleaner assertions, use `Assert` in your test files. The error unions are open, so different assertions chain with `?` (and `? |e| MyTag(e)` gives a failure its own tag):

| Assertion | Passes when |
| --- | --- |
| `Assert.eq(actual, expected)` | the two are equal |
| `Assert.not_eq(actual, unexpected)` | the two differ |
| `Assert.true(condition)` / `Assert.false(condition)` | the `Bool` is true / false |
| `Assert.ok(try)` / `Assert.err(try)` | the `Try` is `Ok` / `Err`, returning what it held |
| `Assert.just(maybe)` / `Assert.nothing(maybe)` | the `Maybe` is `Just` / `Nothing` |
| `Assert.contains(coll, elem)` | a `List` holds the element, or a `Str` holds the substring |
| `Assert.not_contains(coll, elem)` | it does not |
| `Assert.gt` / `Assert.gte` / `Assert.lt` / `Assert.lte` | the comparison holds |

Each returns `Try({}, ...)` (except `ok`, `err` and `just`, which return the value they unwrapped) and reports both sides on failure, so `Assert.eq(2, 3)` fails with `2 should equal 3, but it doesn't.`

```roc
# tests/test_users.roc
app [main!] {
    pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
    spec: "../../roc-spec/package/main.roc",
}

import spec.Assert

main! = |_args| {
    Assert.eq(1 + 1, 2)?
    Assert.contains(["a", "b", "c"], "b")?
    Assert.gt([1, 2, 3].len(), 0) ? |e| ListWasEmpty(e)
    Ok({})
}
```

## Starting worker environments

When each worker needs its own server (or reverse proxy, or both), start them with `TestEnvironment.start!`. It spawns every worker first and then polls them all until ready, so the workers start up concurrently instead of each one waiting for the previous:

```roc
import spec.TestEnvironment

TestEnvironment.start!({ sleep!: Sleep.millis! }, {
    count: workers,
    spawn!: |index| {
        port = (8000 + index).to_str()
        Cmd.new("./server").env_str("PORT", port).spawn_grouped!().map_ok(|_| {})
    },
    ready!: |index| check_health!(8000 + index),
    max_attempts: 150,
    delay_ms: 200,
})?
```

`spawn!` starts one worker's processes (use `spawn_grouped!` so they die with the runner) and `ready!` is one cheap probe, called repeatedly until every worker answers. Workers that never answer are reported in `Err(WorkersNotReady(indices))`.

Inside a test, `TestEnvironment.worker_url!` builds the worker's URL from the env the runner sets (`ROC_SPEC_BASE_PORT`, `WORKER_INDEX`, `ROC_SPEC_HOST`). Every `TestEnvironment` function documents exactly which effect fields it needs, so a test that only wants the URL passes `{ env_var!: ... }` and nothing else.

## Waiting for something to become true

`Wait.until!` retries a condition, and `Wait.for_server!` is that specialised to polling a URL until it answers. Use them when a test has to wait on something the runner did not start for it: a migration finishing, a queue draining, a server someone else spawned.

```roc
import spec.Wait

effects = {
    http_send!: Http.send!,
    sleep!: Sleep.millis!,
}

# Retry any condition. Gives up with Err(ConditionNotMet(last_error)).
Wait.until!({ sleep!: Sleep.millis! }, |{}| check_job_finished!(), {
    max_attempts: 10,
    delay_ms: 100,
})?

# Poll a URL until it answers with anything below 500.
Wait.for_server!(effects, "http://localhost:8000/health", {
    max_attempts: 50,
    delay_ms: 50,
    request_timeout_ms: 5000,
    headers: [],
})?
```

The condition is tried once before any sleeping, so `max_attempts: 10, delay_ms: 100` gives up after roughly 900ms. `headers` is there for reverse proxies that route on `Host`.

`Server.with!` already waits for the server it spawns, so you only need `Wait` for servers it does not manage.

## PostgreSQL integration tests

For database tests, use `Pg.with_rollback!` or `Pg.with_truncate!`. They are client-agnostic: you pass a `query! : db, Str => Try({}, err)` function and whatever `db` value it needs. With [roc-pg](https://github.com/niclas-ahden/roc-pg) the query function is a one-liner, see `tests/rollback_test.roc` in this repository for a complete example, including parsing `DATABASE_URL` with `roc-database-url` and connecting.

```roc
import spec.Pg

# Transaction-based isolation (rolls back after the test)
Pg.with_rollback!(query!, db, |db2| {
    query!(db2, "INSERT INTO users (name) VALUES ('test')")?
    Ok({})
})?

# Truncate-based isolation (for multi-connection tests); listed tables survive
Pg.with_truncate!(query!, db, ["schema_migrations"], |db2| Ok({}))?
```

`Pg.worker_db!` connects to the current worker's isolated database, named `$ROC_SPEC_BASE_DATABASE_NAME_$WORKER_INDEX`. It reads `PG_HOST`, `PG_PORT` and `PG_USER`, plus an optional `PG_PASSWORD` (unset means no password, for the trust or peer auth a local test database usually runs with). Your `pg_connect!` adapts those settings to your client's own connect function, which is where client-specific settings like roc-pg's `timeout_ms` go:

```roc
db = Pg.worker_db!({
    env_var!: Env.var_str!,
    pg_connect!: |{ host, port, user, database, auth }|
        Client.connect!(tcp_effects, {
            host,
            port,
            user,
            database,
            auth: match auth {
                Password(p) => Password(p)
                NoPassword => NoAuth
            },
            timeout_ms: 5_000,
        }),
})?
```

## Documentation

View the full documentation at [https://niclas-ahden.github.io/roc-spec/](https://niclas-ahden.github.io/roc-spec/).

The site is built in CI: `deploy-docs.yml` publishes the `main`-branch docs on every push and a versioned copy for each published release (each release's docs ride along as a `docs.tar.gz` asset produced by `bundle.yaml`).
