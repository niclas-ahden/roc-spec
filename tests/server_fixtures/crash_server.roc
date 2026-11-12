app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst" }

import pf.Stderr

# A server that crashes immediately with an error message
main! = |_args| {
	_ = Stderr.line!("CRASH: Server failed to start - simulated port binding error")
	Err(ServerCrashed)
}
