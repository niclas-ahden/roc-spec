app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst" }

import pf.Sleep
import pf.Stdout

main! = |_args| {
	# Sleep for 10 seconds - should be killed by timeout
	Sleep.millis!(10000)?
	Stdout.line!("This should never print")
}
