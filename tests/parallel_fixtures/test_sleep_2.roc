app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.25.0/2Qj7ggHJdVV9jAspIjvskp_cUWvAyh7B9I-Ma_sY4zk.tar.br",
}

import pf.Stdout
import pf.Sleep

main! = |_args|
    Sleep.millis!(200)
    Stdout.line!("roll_2 done")
