app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
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
