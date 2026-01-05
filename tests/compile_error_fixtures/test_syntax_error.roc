app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.25.0/2Qj7ggHJdVV9jAspIjvskp_cUWvAyh7B9I-Ma_sY4zk.tar.br",
}

import pf.Stdout

main! = |_args|
    # This has a syntax error - missing closing quote
    Stdout.line!("This won't compile because of syntax error
