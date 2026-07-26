## Waiting/retrying helpers for integration tests.
##
## Roc has no parameterized modules, so these functions take an
## `effects` record of platform functions as their first argument. Build it once
## from basic-cli's modules and pass it in:
##
## ```roc
## effects = {
##     http_send!: Http.send!,
##     sleep!: Sleep.millis!,
## }
## Wait.for_server!(effects, "http://localhost:8000/health", {
##     max_attempts: 50,
##     delay_ms: 50,
##     request_timeout_ms: 5000,
##     headers: [],
## })?
## ```
import http.Request
import http.Response

Wait :: [].{

	## How many times to try, and how long to wait between tries.
	##
	## The condition is tried immediately and then once per remaining attempt,
	## so `max_attempts: 10, delay_ms: 100` gives up after roughly 900ms of
	## sleeping. Values below 1 still get one try.
	Attempts : {
		max_attempts : U64,
		delay_ms : U64,
	}

	## Configuration for waiting on a server.
	##
	## - `max_attempts`: Maximum number of polling attempts
	## - `delay_ms`: Delay between attempts in milliseconds
	## - `request_timeout_ms`: Timeout for each HTTP request
	## - `headers`: HTTP headers to send (e.g., Host header for reverse proxies)
	ServerConfig : {
		max_attempts : U64,
		delay_ms : U64,
		request_timeout_ms : U64,
		headers : List((Str, Str)),
	}

	## Retry a condition until it succeeds or max attempts reached.
	##
	## The condition is tried once before any sleeping, so `max_attempts: 0`
	## and `max_attempts: 1` both mean "try once, do not retry". The last
	## failure is carried out in `ConditionNotMet`.
	##
	## Only the `sleep!` effect is used:
	##
	## ```roc
	## Wait.until!({ sleep!: Sleep.millis! }, || check_something!(), { max_attempts: 10, delay_ms: 100 }) ? ConditionNotMet
	## ```
	until! : _, ({} => Try({}, cond_err)), Attempts => Try({}, [ConditionNotMet(cond_err), ..err])
	until! = |effects, condition!, { max_attempts, delay_ms }| {
		sleep! = effects.sleep!
		match condition!({}) {
			Ok({}) => Ok({})
			Err(e) =>
				if max_attempts <= 1 {
					Err(ConditionNotMet(e))
				} else {
					sleep!(delay_ms)
					Wait.until!(effects, condition!, { max_attempts: max_attempts - 1, delay_ms })
				}
			}
	}

	## Wait for an HTTP server to be ready by polling the given URL.
	##
	## ```roc
	## # Simple usage (2.5 second timeout)
	## Wait.for_server!(effects, "http://localhost:8000/health", {
	##     max_attempts: 50,
	##     delay_ms: 50,
	##     request_timeout_ms: 5000,
	##     headers: [],
	## })?
	##
	## # With custom Host header for reverse proxy (60 second timeout)
	## Wait.for_server!(effects, "http://127.0.0.1:9100/", {
	##     max_attempts: 300,
	##     delay_ms: 200,
	##     request_timeout_ms: 5000,
	##     headers: [("Host", "myapp.localhost:9100")],
	## })?
	## ```
	for_server! : _, Str, ServerConfig => Try({}, [ServerNotReady(Str), ..err])
	for_server! = |effects, url, config| {
		http_send! = effects.http_send!

		condition! = |{}| {
			request =
				Request.from_method(GET)
					->Request.with_uri(url)
					->Request.with_headers(config.headers.map(|(name, value)| { name, value }))
					->Request.with_timeout(TimeoutMilliseconds(config.request_timeout_ms))

			match http_send!(request) {
				Ok(response) => {
					status = Response.status(response)

					# Accept any non-5xx response (server is running)
					if status < 500 {
						Ok({})
					} else {
						Err(ServerError(status))
					}
				}
				Err(e) => Err(ConnectionFailed(e))
			}
		}

		match Wait.until!(effects, condition!, { max_attempts: config.max_attempts, delay_ms: config.delay_ms }) {
			Ok({}) => Ok({})
			Err(ConditionNotMet(_)) => Err(ServerNotReady(url))
		}
	}
}
