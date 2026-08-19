app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst" }

import pf.Stderr

# A server that crashes immediately with an error message
main! = |_args| {
	_ = Stderr.line!("CRASH: Server failed to start - simulated port binding error")
	Err(ServerCrashed)
}
