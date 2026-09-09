app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst" }

import pf.Stderr

# A server that crashes immediately with an error message
main! = |_args| {
	_ = Stderr.line!("CRASH: Server failed to start - simulated port binding error")
	Err(ServerCrashed)
}
