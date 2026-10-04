app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst" }

import pf.Stdout

main! = |_args| {
	# This should NOT be run - it has no _test suffix
	Stdout.line!("ERROR: helper.roc should not run")?
	Err(ShouldNotRun)
}
