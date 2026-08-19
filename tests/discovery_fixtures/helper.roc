app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst" }

import pf.Stdout

main! = |_args| {
	# This should NOT be run - it has no _test suffix
	Stdout.line!("ERROR: helper.roc should not run")?
	Err(ShouldNotRun)
}
