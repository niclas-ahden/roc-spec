app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.25.0/2Qj7ggHJdVV9jAspIjvskp_cUWvAyh7B9I-Ma_sY4zk.tar.br",
}

import pf.Arg
import pf.Sleep

# A server that takes too long to start (never becomes HTTP ready within timeout)
# Just sleeps forever - process is running but no HTTP server
main! : List Arg.Arg => Result {} _
main! = |_args|
    # Sleep for 10 minutes - much longer than any reasonable timeout
    Sleep.millis!(600_000)
    Ok({})
