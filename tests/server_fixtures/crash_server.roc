app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
}

import pf.Arg
import pf.Stderr

# A server that crashes immediately with an error message
main! : List Arg.Arg => Result {} _
main! = |_args|
    _ = Stderr.line!("CRASH: Server failed to start - simulated port binding error")
    Err(ServerCrashed)
