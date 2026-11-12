app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst" }

import pf.Stdout

main! = |_args| {
	# This should NOT be run - it has no _test suffix
	Stdout.line!("ERROR: helper.roc should not run")?
	Err(ShouldNotRun)
}
