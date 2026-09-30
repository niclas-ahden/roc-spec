app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.27.0/HZanbveSUDoJF8LypR663eH7PpaKEKG36eErEQzmV1Qs.tar.zst" }

import pf.Sleep

# A server that takes too long to start (never becomes HTTP ready within timeout)
# Just sleeps forever - process is running but no HTTP server
main! = |_args| {
	# Sleep for 10 minutes - much longer than any reasonable timeout
	Sleep.millis!(600_000)
	Ok({})
}
