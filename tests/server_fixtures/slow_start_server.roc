app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst" }

import pf.Sleep

# A server that takes too long to start (never becomes HTTP ready within timeout)
# Just sleeps forever - process is running but no HTTP server
main! = |_args| {
	# Sleep for 10 minutes - much longer than any reasonable timeout
	Sleep.millis!(600_000)?
	Ok({})
}
