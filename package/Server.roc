## Server lifecycle management for integration tests.
##
## Provides helpers to spawn a server process, wait for it to be ready,
## run tests, and clean up - all in a single `with!` block.
##
## The address comes from the same worker environment `TestEnvironment` reads
## (`ROC_SPEC_HOST`, `ROC_SPEC_BASE_PORT`, `WORKER_INDEX`), so a test spawning
## its own server and a test talking to a runner-managed one agree on where
## the worker lives. `with_address!` takes one you supply instead.
##
## Roc has no parameterized modules, so these functions take a
## `PlatformHooks` record of platform functions as their first argument, the
## same one `Spec` takes (see `Spec` for the whole record). `Server` uses
## `os_str`, `spawn!`, `poll!`, `close!`, `env_var!`, `http_send!`,
## `send_options` and `sleep!`:
##
## ```roc
## main! = |_|
##     Server.with!(hooks, Cmd.new("./my-server"), |base_url| {
##         # Server is running and ready
##         body = Http.get_utf8!(Url.parse("${base_url}/health") ? InvalidUrl, {})?
##         Assert.eq(body, "ok")
##     })
## ```
##
## The server is started from your command with its port in both `PORT` and
## `ROC_BASIC_WEBSERVER_PORT`, its stdout and stderr captured, through the
## `spawn!` hook, so with `Cmd.Command.spawn_leashed!` it is killed when the
## test exits. `ServerCrashed` reports what it wrote on stderr. A captured
## stream has a budget (16 MiB by default): a server that exceeds it is
## cancelled by the platform and reported as `ServerOutputLimit`.
import TestEnvironment
import http.Request

Server :: [].{

	## How long to wait for a server to answer: `max_attempts` probes,
	## `delay_ms` apart, so the ceiling is `max_attempts * delay_ms`.
	##
	## The first answer does not end the wait. The server has to still be
	## alive a second later before it is declared ready, so a process that
	## answers once and then dies is caught as `ServerCrashed` rather than
	## reported as a success. Probing already done counts towards that
	## second, so a server that took a while to answer is ready as soon as it
	## answers.
	Timeout : {
		max_attempts : U64,
		delay_ms : U64,
	}

	## Where a managed server lives, and how long to wait for it.
	##
	## `base_url` is what the callback receives and what readiness polls;
	## `port` is what the server is started with.
	Address : {
		base_url : Str,
		port : Str,
		max_attempts : U64,
		delay_ms : U64,
	}

	## Everything that can go wrong before your callback runs, on top of
	## whatever the callback itself returns (`err`).
	##
	## - `ServerSpawnFailed`: the process would not start, carrying your
	##   platform's own spawn error
	## - `ServerCrashed`: it started and then exited before answering
	## - `ServerOutputLimit`: it printed more than its capture budget allows
	##   before answering, so the platform cancelled it
	## - `ServerNotReady`: it never answered within the timeout
	## - `EnvVarNotSet`/`InvalidEnvVar`: the worker environment could not be
	##   read (`with!` and `with_timeout!` only, since `with_address!` is told
	##   the address instead of deriving it)
	Error(spawn_err, err) : [
		ServerSpawnFailed(spawn_err),
		ServerCrashed({ status : [Exited(I32), Signaled(I32)], stderr : Str }),
		ServerOutputLimit({ stdout : Str, stderr : Str }),
		ServerNotReady(Str),
		EnvVarNotSet(Str),
		InvalidEnvVar(Str),
		..err,
	]

	## Run a test with a server. Spawns the server process, waits for it to be
	## ready, provides the base_url to the callback, and kills the server when done.
	##
	## Waits up to 30 seconds for the server to answer (150 probes, 200ms
	## apart). Use `with_timeout!` to change that.
	##
	## The address comes from the worker environment the runner set up, so
	## every worker in a parallel run gets its own port (see `with_address!`
	## for how it is derived, and for passing one in yourself).
	##
	## ```roc
	## Server.with!(hooks, Cmd.new("roc").args(["server.roc"]), |base_url| {
	##     # base_url = "http://localhost:8000" under a sequential run
	##     content = Http.get_utf8!(Url.parse("${base_url}/api/users") ? InvalidUrl, {})?
	##     Assert.contains(content, "alice")?
	##     Ok({})
	## })
	## ```
	with! : _, _, (Str => Try(ok, Error(spawn_err, err))) => Try(ok, Error(spawn_err, err))
	with! = |hooks, cmd, callback!|
		Server.with_timeout!(hooks, cmd, { max_attempts: 150, delay_ms: 200 }, callback!)

	## Run a test with a server, with custom timeout settings.
	##
	## Like `with!`, but allows configuring the timeout parameters.
	##
	## ```roc
	## # Quick timeout for testing slow-start scenarios (5 attempts × 200ms = 1 second)
	## Server.with_timeout!(hooks, Cmd.new("./my-server"), { max_attempts: 5, delay_ms: 200 }, |base_url| {
	##     # ...
	## })
	## ```
	with_timeout! : _, _, Timeout, (Str => Try(ok, Error(spawn_err, err))) => Try(ok, Error(spawn_err, err))
	with_timeout! = |hooks, cmd, { max_attempts, delay_ms }, callback!| {
		address = worker_address!(hooks)?

		Server.with_address!(
			hooks,
			cmd,
			{ base_url: address.base_url, port: address.port, max_attempts, delay_ms },
			callback!,
		)
	}

	## Run a test with a server at an address you supply.
	##
	## `base_url` is what the callback receives and what readiness polls, and
	## `port` is what the server is started with. They are separate because the
	## address a test reaches the server on is not always the one the server
	## binds: behind a reverse proxy or a vhost, tests speak to a hostname
	## while the process listens on a port.
	##
	## `with!` and `with_timeout!` derive both from the worker environment, so
	## reach for this only when that convention does not describe your setup.
	##
	## ```roc
	## Server.with_address!(hooks, Cmd.new("./my-server"), {
	##     base_url: "https://shop.example.test",
	##     port: "8443",
	##     max_attempts: 150,
	##     delay_ms: 200,
	## }, |base_url| { ... })
	## ```
	with_address! : _, _, Address, (Str => Try(ok, Error(spawn_err, err))) => Try(ok, Error(spawn_err, err))
	with_address! = |hooks, cmd, { base_url, port, max_attempts, delay_ms }, callback!| {
		close! = hooks.close!

		spawn_result = spawn_server!(hooks, cmd, port)

		match spawn_result {
			Ok(child) => {
				# Wait for server to be ready
				wait_result = wait_for_server!(hooks, base_url, max_attempts, delay_ms, child)

				# Run callback only if server is ready
				result =
					match wait_result {
						Ok({}) => callback!(base_url)
						Err(e) => Err(e)
					}

				# Always take the server down, even if wait or callback failed
				_ = close!(child)

				result
			}

			Err(e) =>
				Err(ServerSpawnFailed(e))
			}
	}
}

## The address for this worker's server.
##
## The runner's worker convention comes first (`ROC_SPEC_BASE_PORT` +
## `WORKER_INDEX`, host from `ROC_SPEC_HOST`), which gives every worker in a
## parallel run its own port. A sequential run has no runner to set that up,
## so there the port is `PORT`, default 8000.
##
## A `ROC_SPEC_BASE_PORT` or `WORKER_INDEX` that is set but unparseable is a
## misconfiguration and errors: quietly routing every worker to one port
## surfaces as baffling cross-test interference.
worker_address! = |hooks| {
	env_var! = hooks.env_var!

	port =
		match TestEnvironment.worker_port!(hooks) {
			Ok(worker_port) => Ok(worker_port.to_str())
			Err(EnvVarNotSet(_)) =>
				match env_var!("PORT") {
					Ok(configured) => Ok(configured)
					Err(_) => Ok("8000")
				}
			Err(other) => Err(other)
		}?

	host = TestEnvironment.worker_host!(hooks)

	Ok({ base_url: "http://${host}:${port}", port })
}

## Wait for server to be ready by polling the base URL
wait_for_server! = |hooks, url, max_attempts, delay_ms, child|
	wait_for_server_helper!(hooks, url, max_attempts, delay_ms, 0, child)

wait_for_server_helper! = |hooks, url, max_attempts, delay_ms, attempt, child| {
	sleep! = hooks.sleep!

	if attempt >= max_attempts {
		Err(ServerNotReady(url))
	} else {
		match check_server!(hooks, child, url) {
			Err(e) => Err(e)

			Ok(Running) =>
			# Server is still running, check if it's ready via HTTP
				match probe!(hooks, url) {
					Ok(_body) =>
						# Something answered, but that is not proof it was ours:
						# a leftover process on the same port answers just as
						# well, and a server can answer once and then die on
						# its first real request. Watch the child for a while
						# before declaring it up.
						settle!(hooks, child, url, settle_ms(attempt, delay_ms))

					Err(_) => {
						_ = sleep!(delay_ms)
						wait_for_server_helper!(hooks, url, max_attempts, delay_ms, attempt + 1, child)
					}
				}

			Ok(Unknown) =>
			# Couldn't poll, fall back to http-only check
				match probe!(hooks, url) {
					Ok(_body) => Ok({})

					Err(_) => {
						_ = sleep!(delay_ms)
						wait_for_server_helper!(hooks, url, max_attempts, delay_ms, attempt + 1, child)
					}
				}
		}
	}
}

## How long a server has to stay up before an answer on its URL is taken as
## its own. A leftover process on the same port answers immediately, so an
## answer that arrives before ours has had time to bind and fall over proves
## nothing.
##
## Deliberately not `delay_ms`: that is a polling interval, and a caller who
## polls every 50ms wants a quick first answer, not a 50ms guard. A cold
## process on a loaded machine takes longer than that just to reach its
## `listen` call, which is where a port conflict surfaces.
min_alive_ms : U64
min_alive_ms = 1000

## How often `settle!` looks at the child, so a server that dies during the
## window is reported without waiting the window out.
settle_slice_ms : U64
settle_slice_ms = 50

## What is left of `min_alive_ms` once the probing already done is counted.
##
## Every failed probe is a second the child was alive without anything
## answering, which is the evidence the window is there to gather. A server
## that answered only on the tenth probe has already earned its keep; one
## that answered on the first has not.
settle_ms = |attempt, delay_ms| {
	polled_ms = attempt * delay_ms

	if polled_ms >= min_alive_ms {
		0
	} else {
		min_alive_ms - polled_ms
	}
}

## Watch a child that has answered for `remaining_ms`, then declare it ready.
##
## Returns as soon as the child is seen to have died, so the window costs
## nothing in the case it exists to catch.
settle! = |hooks, child, url, remaining_ms| {
	sleep! = hooks.sleep!

	if remaining_ms == 0 {
		match check_server!(hooks, child, url) {
			Ok(_) => Ok({})
			Err(e) => Err(e)
		}
	} else {
		slice =
			if remaining_ms < settle_slice_ms {
				remaining_ms
			} else {
				settle_slice_ms
			}

		_ = sleep!(slice)

		match check_server!(hooks, child, url) {
			Ok(_) => settle!(hooks, child, url, remaining_ms - slice)
			Err(e) => Err(e)
		}
	}
}

## Whether the server is still running, or how it ended if it is not.
check_server! = |hooks, child, url| {
	poll! = hooks.poll!

	match poll!(child) {
		Ok(Running) =>
			Ok(Running)

		Ok(Finished(output)) =>
			Err(ServerCrashed({ status: output.status, stderr: Str.from_utf8_lossy(output.stderr_bytes) }))

		Err(CmdErr(OutputLimitExceeded(partial))) =>
			Err(ServerOutputLimit({
				stdout: Str.from_utf8_lossy(partial.stdout_bytes),
				stderr: Str.from_utf8_lossy(partial.stderr_bytes),
			}))

		# The platform's own deadline (`Cmd.timeout`) ran out first.
		Err(CmdErr(TimedOut(_))) =>
			Err(ServerNotReady(url))

		# A poll error is treated as no news, so readiness falls back to the
		# HTTP probe alone.
		Err(_) =>
			Ok(Unknown)
	}
}

## Start the server from `cmd` with its port set and both streams captured.
spawn_server! = |hooks, cmd, port| {
	os_str = hooks.os_str
	spawn! = hooks.spawn!

	spawn!(
		cmd
			.env("PORT", os_str(port))
			.env("ROC_BASIC_WEBSERVER_PORT", os_str(port))
			.stdout(Capture)
			.stderr(Capture),
	)
}

## One readiness probe: whether anything answers a GET on `url`. Any answer
## counts, whatever its status.
probe! = |hooks, url| {
	http_send! = hooks.http_send!

	http_send!(Request.from_method(GET)->Request.with_uri(url), hooks.send_options)
}
