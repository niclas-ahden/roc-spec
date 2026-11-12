app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst" }

import pf.Sleep
import pf.Stdout

main! = |_args| {
	Sleep.millis!(200)?
	Stdout.line!("roll_2 done")
}
