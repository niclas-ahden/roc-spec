app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst" }

import pf.Stdout

main! = |_args| {
	# This should NOT be run - the old test_ prefix no longer marks a test file
	Stdout.line!("ERROR: test_prefix_only.roc should not run")?
	Err(ShouldNotRun)
}
