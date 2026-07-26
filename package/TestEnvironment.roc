## Worker orchestration and per-worker context for parallel integration tests.
##
## Two sides of the same contract:
##
## 1. **For test runners**: `start!` spawns N isolated worker environments and
##    waits until every one of them is ready.
## 2. **For individual tests**: `with!`, `worker_url!`, `worker_index!` and
##    `fetch!` read the worker context the runner set up.
##
## Roc has no parameterized modules, so these functions take an
## `effects` record of platform functions as their first argument. Each function
## documents the fields it uses, and it only needs those fields: build exactly
## the record a call needs, there is no master record to assemble. Database
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
## env = { env_var!: Env.var_str! }
##
## main! = |_args|
##     TestEnvironment.with!(env, |worker_url| {
##         body = TestEnvironment.fetch!({ http_send!: Http.send! }, "${worker_url}/users")?
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
	## own error) or because some worker never became ready.
	StartError(err) : [
		WorkersNotReady(List(U16)),
		..err,
	]

	## The worker environments to start.
	##
	## - `count`: how many workers to run
	## - `spawn!`: starts one worker's processes, given its index. Its error
	##   propagates out of `start!` unchanged.
	## - `ready!`: one cheap readiness probe for a worker
	## - `max_attempts`/`delay_ms`: probe rounds and the gap between them, so
	##   the ceiling is `max_attempts * delay_ms`
	Workers(err) : {
		count : U16,
		spawn! : U16 => Try({}, StartError(err)),
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
	## - `spawn!` starts one worker's processes. Use `Cmd.spawn_grouped!` so
	##   they are cleaned up when the test runner exits.
	## - `ready!` is one cheap readiness probe (a TCP connect, an HTTP GET).
	##   It is called repeatedly, on every not-yet-ready worker each round.
	## - After `max_attempts` rounds, the not-ready worker indices are
	##   reported in `Err(WorkersNotReady(indices))`.
	##
	## Effects used: `{ sleep! }`.
	##
	## ```roc
	## TestEnvironment.start!({ sleep!: Sleep.millis! }, {
	##     count: 32,
	##     spawn!: |index| {
	##         port = (8000 + index).to_str()
	##         Cmd.new("./server").env_str("PORT", port).spawn_grouped!().map_ok(|_| {})
	##     },
	##     ready!: |index| check_health!(8000 + index),
	##     max_attempts: 150,
	##     delay_ms: 200,
	## })?
	## ```
	start! : _, Workers(err) => Try({}, StartError(err))
	start! = |effects, { count, spawn!: inner_spawn!, ready!: inner_ready!, max_attempts, delay_ms }| {
		# Phase 1: spawn everything.
		var $pending = []
		var $index = 0.U16
		while $index < count {
			inner_spawn!($index)?
			$pending = $pending.append($index)
			$index = $index + 1
		}

		# Phase 2: probe all not-yet-ready workers each round, until none are
		# left or the rounds run out.
		wait_for_workers!(effects, inner_ready!, $pending, 0, max_attempts, delay_ms)
	}

	## Run a test with the worker's URL.
	##
	## Effects used: `{ env_var! }`.
	##
	## ```roc
	## TestEnvironment.with!(env, |worker_url| {
	##     body = TestEnvironment.fetch!({ http_send!: Http.send! }, "${worker_url}/health")?
	##     Assert.contains(body, "ok")?
	##     Ok({})
	## })
	## ```
	with! : _, (Str => Try(ok, EnvError(err))) => Try(ok, EnvError(err))
	with! = |effects, test!| {
		url = TestEnvironment.worker_url!(effects)?
		test!(url)
	}

	## Fetch a URL and return the response body as a string.
	## Sets the Host header to the URL's own authority, for platforms and
	## proxies that route on it.
	##
	## Returns `Err(HttpError(status, url, body_preview))` for non-2xx status
	## codes, and `Err(InvalidUrl(url))` for a URL that does not parse.
	##
	## Effects used: `{ http_send! }`.
	##
	## ```roc
	## body = TestEnvironment.fetch!({ http_send!: Http.send! }, "${worker_url}/api/users")?
	## ```
	fetch! : _, Str => Try(Str, [HttpError(U16, Str, Str), InvalidUrl(Str), ..err])
	fetch! = |effects, url| {
		http_send! = effects.http_send!

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

		response = http_send!(request)?
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
	## Effects used: `{ env_var! }`.
	worker_url! : _ => Try(Str, EnvError(err))
	worker_url! = |effects| {
		port = TestEnvironment.worker_port!(effects)?
		host = TestEnvironment.worker_host!(effects)

		Ok("http://${host}:${port.to_str()}")
	}

	## Get the port for the current worker: `$ROC_SPEC_BASE_PORT + $WORKER_INDEX`.
	##
	## `ROC_SPEC_BASE_PORT` must be set; `WORKER_INDEX` defaults to 0 for
	## sequential/single-worker tests. Anything that needs a worker's address
	## in parts rather than as a URL builds it from this and `worker_host!`,
	## so the convention lives in one place.
	##
	## Effects used: `{ env_var! }`.
	worker_port! : _ => Try(U16, EnvError(err))
	worker_port! = |effects| {
		env_var! = effects.env_var!

		base_port_str = env_var!("ROC_SPEC_BASE_PORT") ? |_| EnvVarNotSet("ROC_SPEC_BASE_PORT")
		base_port = U16.from_str(base_port_str) ? |_| InvalidEnvVar("ROC_SPEC_BASE_PORT")

		worker_index = TestEnvironment.worker_index!(effects)?

		Ok(base_port + worker_index)
	}

	## Get the host for worker URLs from `ROC_SPEC_HOST`, defaulting to
	## "localhost".
	##
	## A default rather than an error: a single-host suite never has to set it,
	## while suites behind a reverse proxy or a vhost point it at the name the
	## server actually answers to.
	##
	## Effects used: `{ env_var! }`.
	worker_host! : _ => Str
	worker_host! = |effects| {
		env_var! = effects.env_var!

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
	## Effects used: `{ env_var! }`.
	worker_index! : _ => Try(U16, EnvError(err))
	worker_index! = |effects| {
		env_var! = effects.env_var!

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
wait_for_workers! = |effects, ready!, pending, attempt, max_attempts, delay_ms| {
	sleep! = effects.sleep!

	if pending.is_empty() {
		Ok({})
	} else if attempt >= max_attempts {
		Err(WorkersNotReady(pending))
	} else {
		still_pending = probe_round!(ready!, pending, [])

		if still_pending.is_empty() {
			Ok({})
		} else {
			sleep!(delay_ms)
			wait_for_workers!(effects, ready!, still_pending, attempt + 1, max_attempts, delay_ms)
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
