app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.25.0/2Qj7ggHJdVV9jAspIjvskp_cUWvAyh7B9I-Ma_sY4zk.tar.br",
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
