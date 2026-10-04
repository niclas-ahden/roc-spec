app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst" }

import pf.Sleep
import pf.Stdout

main! = |_args| {
	Sleep.millis!(200)
	Stdout.line!("roll_3 done")
}
