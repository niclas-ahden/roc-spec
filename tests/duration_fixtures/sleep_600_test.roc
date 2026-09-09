app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst" }

import pf.Sleep
import pf.Stdout

main! = |_args| {
	Sleep.millis!(600)
	Stdout.line!("slept 600ms")
}
