app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst" }

import pf.Stderr

# A server that crashes immediately with an error message
main! = |_args| {
	_ = Stderr.line!("CRASH: Server failed to start - simulated port binding error")
	Err(ServerCrashed)
}
