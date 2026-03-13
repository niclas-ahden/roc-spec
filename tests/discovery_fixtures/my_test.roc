app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
}

import pf.Stdout

main! = |_args|
    # This should NOT be run - it doesn't start with test_
    Stdout.line!("ERROR: my_test.roc should not run")?
    Err(ShouldNotRun)
