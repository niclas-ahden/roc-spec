app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst" }

import pf.Stdout

main! = |_args| {
	# This should NOT be run - it has no _test suffix
	Stdout.line!("ERROR: helper.roc should not run")?
	Err(ShouldNotRun)
}
