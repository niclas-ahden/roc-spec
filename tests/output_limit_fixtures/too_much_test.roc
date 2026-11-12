app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst" }

import pf.Stdout

## Prints well past the 10 KB capture budget the test that runs this sets,
## and would exit 0 if it were allowed to finish.
main! = |_args| {
	Stdout.line!("START_MARKER")?
	line = Str.repeat("x", 99)
	var $n = 0
	while $n < 2000 {
		Stdout.line!(line)?
		$n = $n + 1
	}
	Stdout.line!("END_MARKER")
}
