app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst" }

import pf.Stdout

main! = |_args| {
	Stdout.line!("QUIET_TEST_FAIL_MARKER")?
	Err(IntentionalFailure)
}
