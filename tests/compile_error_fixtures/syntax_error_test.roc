app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst" }

import pf.Stdout

main! = |_args|
    # This has a syntax error - missing closing quote
    Stdout.line!("This won't compile because of syntax error
