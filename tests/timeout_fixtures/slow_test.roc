app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst" }

import pf.Sleep
import pf.Stdout

main! = |_args| {
	# Sleep for 10 seconds - should be killed by timeout
	Sleep.millis!(10000)
	Stdout.line!("This should never print")
}
