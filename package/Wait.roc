module { http_send!, sleep!, http_header } -> [until!, for_server!, ServerConfig]

## Retry a condition until it succeeds or max attempts reached.
##
## ```roc
## Wait.until!(|| check_something!(), { max_attempts: 10, delay_ms: 100 }) ? ConditionNotMet
## ```
until! : ({} => Result {} err), { max_attempts : U64, delay_ms : U64 } => Result {} [ConditionNotMet err]
until! = |condition!, { max_attempts, delay_ms }|
    when condition!({}) is
        Ok({}) -> Ok({})
        Err(e) ->
            if max_attempts <= 1 then
                Err(ConditionNotMet(e))
            else
                sleep!(delay_ms)
                until!(condition!, { max_attempts: max_attempts - 1, delay_ms })

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
    headers : List (Str, Str),
}

## Wait for an HTTP server to be ready by polling the given URL.
##
## ```roc
## # Simple usage (2.5 second timeout)
## Wait.for_server!("http://localhost:8000/health", {
##     max_attempts: 50,
##     delay_ms: 50,
##     request_timeout_ms: 5000,
##     headers: [],
## })?
##
## # With custom Host header for reverse proxy (60 second timeout)
## Wait.for_server!("http://127.0.0.1:9100/", {
##     max_attempts: 300,
##     delay_ms: 200,
##     request_timeout_ms: 5000,
##     headers: [("Host", "myapp.localhost:9100")],
## })?
## ```
for_server! : Str, ServerConfig => Result {} [ServerNotReady Str]
for_server! = |url, config|
    condition! = |{}|
        request = {
            method: GET,
            headers: List.map(config.headers, http_header),
            uri: url,
            body: [],
            timeout_ms: TimeoutMilliseconds(config.request_timeout_ms),
        }
        when http_send!(request) is
            Ok(response) ->
                # Accept any non-5xx response (server is running)
                if response.status < 500 then
                    Ok({})
                else
                    Err(ServerError(response.status))
            Err(e) -> Err(ConnectionFailed(e))

    when until!(condition!, { max_attempts: config.max_attempts, delay_ms: config.delay_ms }) is
        Ok({}) -> Ok({})
        Err(ConditionNotMet(_)) -> Err(ServerNotReady(url))
