app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
}

import pf.Stdout
import pf.Stderr

main! = |_args|
    Stdout.line!("STDOUT_MARKER_11111")?
    Stderr.line!("STDERR_MARKER_67890")?
    Err(IntentionalFailure)
