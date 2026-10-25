## Worker orchestration and per-worker context for parallel integration tests.
##
## Two sides of the same contract:
##
## 1. **For test runners**: `start!` spawns N isolated worker environments and
##    waits until every one of them is ready.
## 2. **For individual tests**: `with!`, `worker_url!`, `worker_index!` and
##    `fetch!` read the worker context the runner set up.
##
## Roc has no parameterized modules, so these functions take a
## `PlatformHooks` record of platform functions as their first argument, the
## same one `Spec` takes (see `Spec` for the whole record). Each function
## documents the hooks it uses and only reads those. Database
## helpers live in `Pg` (see `Pg.worker_db!`), so nothing here pulls in a
## database dependency.
##
## Environment variables read by the per-test helpers:
## - `WORKER_INDEX`: Current worker number (0, 1, 2, ...) - defaults to 0 if
##   not set, so the helpers also work in sequential (non-parallel) tests
## - `ROC_SPEC_BASE_PORT`: Base port number (worker port = base + index)
## - `ROC_SPEC_HOST`: Hostname for URLs (default: "localhost")
##
## Example test file:
## ```roc
## import spec.TestEnvironment
## import spec.Assert
##
## main! = |_args|
##     TestEnvironment.with!(hooks, |worker_url| {
##         body = TestEnvironment.fetch!(hooks, "${worker_url}/users")?
##         Assert.contains(body, "test")?
##         Ok({})
##     })
## ```
import http.Request
import http.Response
import url.Url

TestEnvironment :: [].{

	## Reading the worker environment fails in two ways: a variable that must
	## be set is missing, or one that is set does not parse.
	EnvError(err) : [
		EnvVarNotSet(Str),
		InvalidEnvVar(Str),
		..err,
	]

	## Starting workers fails either because a `spawn!` failed (`err`, your
	## own error, passed through unchanged) or because some worker never
	## became ready.
	##
	## `WorkersNotReady` carries the indices that never answered and every
	## handle `spawn!` returned, in index order, so the runner can ask the
	## silent workers how they ended (`Cmd.Child.poll!` gives an exit
	## status and captured output). A managed child is terminated when its
	## last reference is released, so a handle dropped inside `start!` would
	## be gone before the error reached the caller.
	StartError(handle, err) : [
		WorkersNotReady({ not_ready : List(U16), handles : List(handle) }),
		..err,
	]

	## The worker environments to start.
	##
	## - `count`: how many workers to run
	## - `spawn!`: starts one worker's processes, given its index, and hands
	##   back whatever keeps them alive (a `Cmd.Child`, or a record of them).
	##   Its error propagates out of `start!` unchanged.
	## - `ready!`: one cheap readiness probe for a worker
	## - `max_attempts`/`delay_ms`: probe rounds and the gap between them, so
	##   the ceiling is `max_attempts * delay_ms`
	Workers(handle, err) : {
		count : U16,
		spawn! : U16 => Try(handle, StartError(handle, err)),
		ready! : U16 => Bool,
		max_attempts : U64,
		delay_ms : U64,
	}

	## Start N isolated worker environments in two phases: first spawn every
	## worker, then poll every worker until all of them are ready.
	##
	## Spawning first and waiting afterwards lets the workers start up
	## concurrently. Waiting inside the spawn loop would serialize startup:
	## worker 1 would not even be spawned until worker 0 answered.
	##
	## - `spawn!` starts one worker's processes. Use `Cmd.spawn_leashed!` so
	##   they are cleaned up when the test runner exits, and return the
	##   `Cmd.Child`: a managed child is terminated when its last reference
	##   is released, so `start!` hands the handles back, one per worker in
	##   index order, for the runner to keep until the run is done. Roc
	##   releases a binding after its last use, so a `servers` that is never
	##   read again is released as soon as `start!` returns, and the workers
	##   are gone before the first test starts. Closing them after the run,
	##   as below, is what keeps them alive until then.
	## - `ready!` is one cheap readiness probe (a TCP connect, an HTTP GET).
	##   It is called repeatedly, on every not-yet-ready worker each round.
	## - After `max_attempts` rounds, the not-ready worker indices are
	##   reported in `Err(WorkersNotReady({ not_ready, handles }))`, together
	##   with every handle, so the runner can inspect the workers that never
	##   answered. A `spawn!` failure returns its error as is. The workers
	##   spawned before it are released on the way out, which terminates them.
	##
	## Hooks used: `sleep!`.
	##
	## ```roc
	## servers = TestEnvironment.start!(hooks, {
	##     count: 32,
	##     spawn!: |index| {
	##         port = (8000 + index).to_str()
	##         Cmd.new("./server").env("PORT", OsStr.from_str(port)).spawn_leashed!() ? |e| SpawnFailed(e)
	##     },
	##     ready!: |index| check_health!(8000 + index),
	##     max_attempts: 150,
	##     delay_ms: 200,
	## })?
	##
	## results = Spec.run!(hooks, "tests", config)?
	##
	## # Holding the handles until here kept the servers up for the run.
	## # Close them now that it is over.
	## for server in servers {
	##     _ = Cmd.Child.close!(server)
	## }
	## ```
	start! : _, Workers(handle, err) => Try(List(handle), StartError(handle, err))
	start! = |hooks, { count, spawn!: inner_spawn!, ready!: inner_ready!, max_attempts, delay_ms }| {
		# Phase 1: spawn everything.
		var $handles = []
		var $pending = []
		var $index = 0.U16
		while $index < count {
			$handles = $handles.append(inner_spawn!($index)?)
			$pending = $pending.append($index)
			$index = $index + 1
		}

		# Phase 2: probe all not-yet-ready workers each round, until none are
		# left or the rounds run out.
		match wait_for_workers!(hooks, inner_ready!, $pending, 0, max_attempts, delay_ms) {
			Ok({}) => Ok($handles)
			Err(NotReady(not_ready)) => Err(WorkersNotReady({ not_ready, handles: $handles }))
		}
	}

	## Run a test with the worker's URL.
	##
	## Hooks used: `env_var!`.
	##
	## ```roc
	## TestEnvironment.with!(hooks, |worker_url| {
	##     body = TestEnvironment.fetch!(hooks, "${worker_url}/health")?
	##     Assert.contains(body, "ok")?
	##     Ok({})
	## })
	## ```
	with! : _, (Str => Try(ok, EnvError(err))) => Try(ok, EnvError(err))
	with! = |hooks, test!| {
		url = TestEnvironment.worker_url!(hooks)?
		test!(url)
	}

	## Fetch a URL and return the response body as a string.
	## Sets the Host header to the URL's own authority, for platforms and
	## proxies that route on it.
	##
	## Returns `Err(HttpError(status, url, body_preview))` for non-2xx status
	## codes, and `Err(InvalidUrl(url))` for a URL that does not parse.
	##
	## Hooks used: `http_send!` and `send_options`.
	##
	## ```roc
	## body = TestEnvironment.fetch!(hooks, "${worker_url}/api/users")?
	## ```
	fetch! : _, Str => Try(Str, [HttpError(U16, Str, Str), InvalidUrl(Str), ..err])
	fetch! = |hooks, url| {
		http_send! = hooks.http_send!

		# The Host header is the URL's authority, which roc-url parses out for
		# us. Slicing the string by hand worked only for `http://host:port/…`
		# and produced a nonsense header for anything else.
		parsed = Url.parse(url) ? |_| InvalidUrl(url)
		authority =
			match Url.explicit_port(parsed) {
				Port(p) => "${Url.host(parsed)}:${p.to_str()}"
				NoPort => Url.host(parsed)
			}

		request =
			Request.from_method(GET)
				->Request.with_uri(url)
				->Request.with_headers([{ name: "Host", value: authority }])
				->Request.with_timeout(TimeoutMilliseconds(10000))

		response = http_send!(request, hooks.send_options)?
		status = Response.status(response)
		response_body = Response.body(response)
		body = Str.from_utf8_lossy(response_body)

		# Check for non-2xx status codes
		if status < 200 or status >= 300 {
			preview = Str.from_utf8_lossy(response_body.take_first(500))
			Err(HttpError(status, url, preview))
		} else {
			Ok(body)
		}
	}

	## Get the worker URL for the current worker index:
	## `http://$ROC_SPEC_HOST:($ROC_SPEC_BASE_PORT + $WORKER_INDEX)`.
	##
	## `ROC_SPEC_HOST` defaults to "localhost", and `WORKER_INDEX` to 0 (for
	## sequential/single-worker tests). `ROC_SPEC_BASE_PORT` must be set.
	##
	## Hooks used: `env_var!`.
	worker_url! : _ => Try(Str, EnvError(err))
	worker_url! = |hooks| {
		port = TestEnvironment.worker_port!(hooks)?
		host = TestEnvironment.worker_host!(hooks)

		Ok("http://${host}:${port.to_str()}")
	}

	## Get the port for the current worker: `$ROC_SPEC_BASE_PORT + $WORKER_INDEX`.
	##
	## `ROC_SPEC_BASE_PORT` must be set; `WORKER_INDEX` defaults to 0 for
	## sequential/single-worker tests. Anything that needs a worker's address
	## in parts rather than as a URL builds it from this and `worker_host!`,
	## so the convention lives in one place.
	##
	## Hooks used: `env_var!`.
	worker_port! : _ => Try(U16, EnvError(err))
	worker_port! = |hooks| {
		env_var! = hooks.env_var!

		base_port_str = env_var!("ROC_SPEC_BASE_PORT") ? |_| EnvVarNotSet("ROC_SPEC_BASE_PORT")
		base_port = U16.from_str(base_port_str) ? |_| InvalidEnvVar("ROC_SPEC_BASE_PORT")

		worker_index = TestEnvironment.worker_index!(hooks)?

		Ok(base_port + worker_index)
	}

	## Get the host for worker URLs from `ROC_SPEC_HOST`, defaulting to
	## "localhost".
	##
	## A default rather than an error: a single-host suite never has to set it,
	## while suites behind a reverse proxy or a vhost point it at the name the
	## server actually answers to.
	##
	## Hooks used: `env_var!`.
	worker_host! : _ => Str
	worker_host! = |hooks| {
		env_var! = hooks.env_var!

		match env_var!("ROC_SPEC_HOST") {
			Ok(host) => host
			Err(_) => "localhost"
		}
	}

	## Get the current worker index from `WORKER_INDEX`.
	##
	## Unset means a sequential/single-worker run and defaults to 0. A value
	## that is set but does not parse is a misconfiguration and errors with
	## `InvalidEnvVar`: silently routing such a test to worker 0's port and
	## database would surface as baffling cross-test interference instead.
	##
	## Hooks used: `env_var!`.
	worker_index! : _ => Try(U16, EnvError(err))
	worker_index! = |hooks| {
		env_var! = hooks.env_var!

		match env_var!("WORKER_INDEX") {
			Ok(s) => {
				index = U16.from_str(s) ? |_| InvalidEnvVar("WORKER_INDEX")
				Ok(index)
			}
			Err(_) => Ok(0.U16)
		}
	}
}

## Probe every pending worker until none are left or the rounds run out.
wait_for_workers! = |hooks, ready!, pending, attempt, max_attempts, delay_ms| {
	sleep! = hooks.sleep!

	if pending.is_empty() {
		Ok({})
	} else if attempt >= max_attempts {
		Err(NotReady(pending))
	} else {
		still_pending = probe_round!(ready!, pending, [])

		if still_pending.is_empty() {
			Ok({})
		} else {
			_ = sleep!(delay_ms)
			wait_for_workers!(hooks, ready!, still_pending, attempt + 1, max_attempts, delay_ms)
		}
	}
}

## One round of readiness probes: check every pending worker once, and keep
## the ones that are still not ready.
probe_round! = |ready!, pending, still_pending|
	match pending {
		[] => still_pending
		[index, .. as rest] =>
			if ready!(index) {
				probe_round!(ready!, rest, still_pending)
			} else {
				probe_round!(ready!, rest, still_pending.append(index))
			}
		}
