app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst" }

import pf.Stdout

main! = |_args| {
	Stdout.line!("exit_1")?
	Err(ExitCode1)
}
