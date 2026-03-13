app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
}

import pf.Stdout
import pf.Sleep

main! = |_args|
    Sleep.millis!(200)
    Stdout.line!("roll_6 done")
