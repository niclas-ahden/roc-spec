app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst" }

import pf.Stderr

# A server that crashes immediately with an error message
main! = |_args| {
	_ = Stderr.line!("CRASH: Server failed to start - simulated port binding error")
	Err(ServerCrashed)
}
