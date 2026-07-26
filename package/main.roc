## Write and run parallel tests with isolated test environments.
##
## Each test is a standalone Roc app named `*_test.roc` that exits 0 on success.
## `Spec.run!` discovers them, runs them across parallel workers, and reports
## what passed. The rest of the package is what integration tests tend to need
## around that: assertions, a managed server, per-worker ports and databases.
##
## - `Spec`: discover and run test files in parallel. Start here.
## - `Assert`: assertions that return `Try`, so they chain with `?`.
## - `Server`: spawn a server, wait for it, kill it when the test ends.
## - `TestEnvironment`: start N worker environments, and read the per-worker
##   port and URL from inside a test.
## - `Pg`: PostgreSQL isolation, per-worker databases, rollback and truncate.
## - `Wait`: retry a condition, or poll a URL until it answers.
##
## Roc has no parameterized modules, so these functions take an
## `effects` record of platform functions as their first argument. Each module's
## docs show the record it needs, built from basic-cli.
##
## See the README for a complete runner, and `examples/` for runnable versions.
package
	[Assert, Spec, Pg, Wait, TestEnvironment, Server]
	{
		# HTTP data types (Method, Request, Response) come from the shared
		# roc-lang/http package, the same one platforms build their `send!`
		# around, so a request built here is the nominal type a platform's
		# `http_send!` accepts.
		http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
		# URL parsing for the Host header `TestEnvironment.fetch!` sets.
		url: "https://github.com/niclas-ahden/roc-url/releases/download/0.7.0/DCKNTirZCLugy1ZydPLrYpefR71RYq1HFUpgQVSNvaFy.tar.zst",
	}
