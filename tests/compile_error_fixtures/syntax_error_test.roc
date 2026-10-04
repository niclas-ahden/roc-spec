app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst" }

import pf.Stdout

main! = |_args|
    # This has a syntax error - missing closing quote
    Stdout.line!("This won't compile because of syntax error
