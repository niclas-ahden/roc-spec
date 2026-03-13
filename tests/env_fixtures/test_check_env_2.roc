app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
}

import pf.Stdout
import pf.Env

main! = |_args|
    when Env.var!("TEST_WORKER_ID") is
        Ok(val) ->
            Stdout.line!("Worker ID: $(val)")

        Err(_) ->
            Stdout.line!("FAIL: TEST_WORKER_ID not set")?
            Err(EnvVarNotSet)
