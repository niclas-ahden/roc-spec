app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
}

import pf.Stdout
import pf.Env
import pf.Sleep

main! = |_args|
    Sleep.millis!(100)
    when Env.var!("WORKER_INDEX") is
        Ok(idx) -> Stdout.line!("WORKER_INDEX=$(idx)")
        Err(_) -> Stdout.line!("WORKER_INDEX=unset")
