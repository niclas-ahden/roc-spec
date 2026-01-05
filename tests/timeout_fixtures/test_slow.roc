app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.25.0/2Qj7ggHJdVV9jAspIjvskp_cUWvAyh7B9I-Ma_sY4zk.tar.br",
}

import pf.Sleep
import pf.Stdout

main! = |_args|
    # Sleep for 10 seconds - should be killed by timeout
    Sleep.millis!(10000)
    Stdout.line!("This should never print")
