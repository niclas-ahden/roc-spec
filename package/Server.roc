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
## Roc has no parameterized modules, so these functions take an
## `effects` record of platform functions as their first argument:
##
## ```roc
## import pf.Cmd
## import pf.Env
## import pf.OsStr
## import pf.Http
## import pf.Url
## import pf.Sleep
## import spec.Server
##
## effects = {
##     env_var!: Env.var_str!,
##     # Start the server as its own process group on the given port. This is
##     # where you set whatever env vars your server reads its port from.
##     # Spawn leashed, so the server is killed when the parent exits.
##     spawn_server!: |cmd, port|
##         cmd
##             .env_str("PORT", port)
##             .env_str("ROC_BASIC_WEBSERVER_PORT", port)
##             .stdout(Capture)
##             .stderr(Capture)
##             .spawn_leashed!(),
##     close!: Cmd.Child.close!,
##     try_wait!: Cmd.Child.try_wait!,
##     http_get!: |url| Http.get_utf8!(Url.parse(url) ? InvalidUrl),
##     sleep!: Sleep.millis!,
## }
##
## main! = |_|
##     Server.with!(effects, Cmd.new("./my-server"), |base_url| {
##         # Server is running and ready
##         body = Http.get_utf8!(Url.parse("${base_url}/health") ? InvalidUrl)?
##         Assert.eq(body, "ok")
##     })
## ```
##
## `spawn_server!` decides what happens to the server's output. Capture
## `stderr` at least, since `ServerCrashed` reports it; `stdout` can be
## captured too, or sent to `Null` for a chatty server. A captured stream has
## a budget (`Cmd.output_limit`, 16 MiB by default): a server that exceeds it
## is cancelled by the platform and reported as `ServerOutputLimit`.
import TestEnvironment

Server :: [].{

	## How long to wait for a server to answer: `max_attempts` probes,
	## `delay_ms` apart, so the ceiling is `max_attempts * delay_ms`.
	##
	## One further `delay_ms` passes after the first answer, before the server
	## is declared ready: a process that answers once and then dies is caught
	## as `ServerCrashed` rather than reported as a success.
	Timeout : {
		max_attempts : U64,
		delay_ms : U64,
	}

	## Where a managed server lives, and how long to wait for it.
	##
	## `base_url` is what the callback receives and what readiness polls;
	## `port` is what `spawn_server!` receives.
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
	## Server.with!(effects, Cmd.new("roc").args_str(["server.roc"]), |base_url| {
	##     # base_url = "http://localhost:8000" under a sequential run
	##     content = Http.get_utf8!(Url.parse("${base_url}/api/users") ? InvalidUrl)?
	##     Assert.contains(content, "alice")?
	##     Ok({})
	## })
	## ```
	with! : _, cmd, (Str => Try(ok, Error(spawn_err, err))) => Try(ok, Error(spawn_err, err))
	with! = |effects, cmd, callback!|
		Server.with_timeout!(effects, cmd, { max_attempts: 150, delay_ms: 200 }, callback!)

	## Run a test with a server, with custom timeout settings.
	##
	## Like `with!`, but allows configuring the timeout parameters.
	##
	## ```roc
	## # Quick timeout for testing slow-start scenarios (5 attempts × 200ms = 1 second)
	## Server.with_timeout!(effects, Cmd.new("./my-server"), { max_attempts: 5, delay_ms: 200 }, |base_url| {
	##     # ...
	## })
	## ```
	with_timeout! : _, cmd, Timeout, (Str => Try(ok, Error(spawn_err, err))) => Try(ok, Error(spawn_err, err))
	with_timeout! = |effects, cmd, { max_attempts, delay_ms }, callback!| {
		address = worker_address!(effects)?

		Server.with_address!(
			effects,
			cmd,
			{ base_url: address.base_url, port: address.port, max_attempts, delay_ms },
			callback!,
		)
	}

	## Run a test with a server at an address you supply.
	##
	## `base_url` is what the callback receives and what readiness polls;
	## `port` is what `spawn_server!` receives. They are separate because the
	## address a test reaches the server on is not always the one the server
	## binds: behind a reverse proxy or a vhost, tests speak to a hostname
	## while the process listens on a port.
	##
	## `with!` and `with_timeout!` derive both from the worker environment, so
	## reach for this only when that convention does not describe your setup.
	##
	## ```roc
	## Server.with_address!(effects, Cmd.new("./my-server"), {
	##     base_url: "https://shop.example.test",
	##     port: "8443",
	##     max_attempts: 150,
	##     delay_ms: 200,
	## }, |base_url| { ... })
	## ```
	with_address! : _, cmd, Address, (Str => Try(ok, Error(spawn_err, err))) => Try(ok, Error(spawn_err, err))
	with_address! = |effects, cmd, { base_url, port, max_attempts, delay_ms }, callback!| {
		spawn_server! = effects.spawn_server!
		close! = effects.close!

		spawn_result = spawn_server!(cmd, port)

		match spawn_result {
			Ok(child) => {
				# Wait for server to be ready
				wait_result = wait_for_server!(effects, base_url, max_attempts, delay_ms, child)

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
worker_address! = |effects| {
	env_var! = effects.env_var!

	port =
		match TestEnvironment.worker_port!(effects) {
			Ok(worker_port) => Ok(worker_port.to_str())
			Err(EnvVarNotSet(_)) =>
				match env_var!("PORT") {
					Ok(configured) => Ok(configured)
					Err(_) => Ok("8000")
				}
			Err(other) => Err(other)
		}?

	host = TestEnvironment.worker_host!(effects)

	Ok({ base_url: "http://${host}:${port}", port })
}

## Wait for server to be ready by polling the base URL
wait_for_server! = |effects, url, max_attempts, delay_ms, child|
	wait_for_server_helper!(effects, url, max_attempts, delay_ms, 0, child)

wait_for_server_helper! = |effects, url, max_attempts, delay_ms, attempt, child| {
	http_get! = effects.http_get!
	sleep! = effects.sleep!

	if attempt >= max_attempts {
		Err(ServerNotReady(url))
	} else {
		match check_server!(effects, child, url) {
			Err(e) => Err(e)

			Ok(Running) =>
			# Server is still running, check if it's ready via HTTP
				match http_get!(url) {
					Ok(_body) => {
						# Something answered, but that is not proof it was ours:
						# a leftover process on the same port answers just as
						# well, and a server can answer once and then die on
						# its first real request. Give it one more `delay_ms`
						# to fall over, then check again before declaring it up.
						sleep!(delay_ms)
						match check_server!(effects, child, url) {
							Ok(_) => Ok({})
							Err(e) => Err(e)
						}
					}

					Err(_) => {
						sleep!(delay_ms)
						wait_for_server_helper!(effects, url, max_attempts, delay_ms, attempt + 1, child)
					}
				}

			Ok(Unknown) =>
			# Couldn't poll, fall back to http-only check
				match http_get!(url) {
					Ok(_body) => Ok({})

					Err(_) => {
						sleep!(delay_ms)
						wait_for_server_helper!(effects, url, max_attempts, delay_ms, attempt + 1, child)
					}
				}
		}
	}
}

## Whether the server is still running, or how it ended if it is not.
check_server! = |effects, child, url| {
	try_wait! = effects.try_wait!

	match try_wait!(child) {
		Ok([]) =>
			Ok(Running)

		Ok([output, ..]) =>
			Err(ServerCrashed({ status: output.status, stderr: Str.from_utf8_lossy(output.stderr_bytes) }))

		Err(OutputLimit(partial)) =>
			Err(ServerOutputLimit({
				stdout: Str.from_utf8_lossy(partial.stdout_bytes),
				stderr: Str.from_utf8_lossy(partial.stderr_bytes),
			}))

		# The platform's own deadline (`Cmd.timeout_ms`) ran out first.
		Err(Timeout(_)) =>
			Err(ServerNotReady(url))

		# A poll error is treated as no news, so readiness falls back to the
		# HTTP probe alone.
		Err(IO(_)) =>
			Ok(Unknown)
	}
}
