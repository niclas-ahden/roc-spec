app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst" }

import pf.Stdout

main! = |_args|
    # This has a syntax error - missing closing quote
    Stdout.line!("This won't compile because of syntax error
