app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst" }

import pf.Stdout

main! = |_args| {
	# This should NOT be run - it has no _test suffix
	Stdout.line!("ERROR: helper.roc should not run")?
	Err(ShouldNotRun)
}
