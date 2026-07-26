app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst" }

import pf.Sleep
import pf.Stdout

main! = |_args| {
	# Sleep for 10 seconds - should be killed by timeout
	Sleep.millis!(10000)
	Stdout.line!("This should never print")
}
