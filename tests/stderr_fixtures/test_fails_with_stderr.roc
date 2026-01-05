app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.25.0/2Qj7ggHJdVV9jAspIjvskp_cUWvAyh7B9I-Ma_sY4zk.tar.br",
}

import pf.Stdout
import pf.Stderr

main! = |_args|
    Stdout.line!("STDOUT_MARKER_11111")?
    Stderr.line!("STDERR_MARKER_67890")?
    Err(IntentionalFailure)
