app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst" }

import pf.Sleep
import pf.Stderr
import pf.Stdout

main! = |_args| {
	# Print first, then hang. The runner kills this test when it times out and
	# should still report everything printed up to that point.
	Stdout.line!("chatty stdout before hanging")?
	Stderr.line!("chatty stderr before hanging")?
	Sleep.millis!(10000)
	Stdout.line!("This should never print")
}
