# roc-spec

A Roc package for writing and running parallel tests with isolated test environments. Includes hooks for setup/teardown and utilities like database helpers, waiting for web servers to start etc.

## How it works

1. Write test files named `test_*.roc` in a directory
2. Each test file is a standalone Roc app that exits 0 on success, non-zero on failure
3. `Spec.run!` discovers and runs them in parallel with isolated worker environments

## Example test file

```roc
# tests/test_math.roc
app [main!] { pf: platform "..." }

main! = |_args|
    if 1 + 1 == 2 then
        Ok({})
    else
        Err(AdditionBroken)
```

## Example test runner

```roc
# run_tests.roc
app [main!] {
    pf: platform "...",
    spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.1.0/k-8alMRioDXgy1Gc6CS4zHkJn6NId_Bjoe6TjS_XlaM.tar.br",
}

import pf.Stdout
import spec.Spec

main! = |_args|
    results = Spec.run!("tests/", {
        max_workers: 8,
        worker_envs: |index| [
            ("PORT", Num.to_str(8000 + index)),
        ],
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 120_000,
        quiet: Bool.true,
    })?

    passed = List.count_if(results, |r| r.passed)
    total = List.len(results)

    Stdout.line!("$(Num.to_str(passed))/$(Num.to_str(total)) tests passed")
```

## Using Assert in test files

For cleaner assertions, use `Assert` in your test files:

```roc
# tests/test_users.roc
app [main!] { pf: platform "...", spec: "..." }

import spec.Assert

main! = |_args|
    Assert.eq(1 + 1, 2)?
    Assert.contains(["a", "b", "c"], "b")?
    Assert.true(List.len([1, 2, 3]) > 0)?
    Ok({})
```

## PostgreSQL integration tests

For database tests, use `Pg.with_rollback!` or `Pg.with_truncate!`:

```roc
import spec.Pg

# Transaction-based isolation (rolls back after test)
Pg.with_rollback!(query!, client, |db|
    query!(db, "INSERT INTO users (name) VALUES ('test')")?
    Ok({})
)?

# Truncate-based isolation (for multi-connection tests)
Pg.with_truncate!(query!, client, ["schema_migrations"], |db|
    Ok({})
)?
```

## Documentation

View the full documentation at [https://niclas-ahden.github.io/roc-spec/](https://niclas-ahden.github.io/roc-spec/).

### Generating documentation locally

```bash
./docs.sh 0.1.0
```
