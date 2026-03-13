app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
}

import pf.Sleep
import pf.Stdout

main! = |_args|
    # Sleep for 10 seconds - should be killed by timeout
    Sleep.millis!(10000)
    Stdout.line!("This should never print")
