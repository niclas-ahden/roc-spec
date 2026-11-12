app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst" }

import pf.Sleep
import pf.Stderr
import pf.Stdout

main! = |_args| {
	# Print first, then hang. The runner kills this test when it times out and
	# should still report everything printed up to that point.
	Stdout.line!("chatty stdout before hanging")?
	Stderr.line!("chatty stderr before hanging")?
	Sleep.millis!(10000)?
	Stdout.line!("This should never print")
}
