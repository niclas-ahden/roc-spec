app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.25.0/2Qj7ggHJdVV9jAspIjvskp_cUWvAyh7B9I-Ma_sY4zk.tar.br",
}

import pf.Arg
import pf.Stderr

# A server that crashes immediately with an error message
main! : List Arg.Arg => Result {} _
main! = |_args|
    _ = Stderr.line!("CRASH: Server failed to start - simulated port binding error")
    Err(ServerCrashed)
