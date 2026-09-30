app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.27.0/HZanbveSUDoJF8LypR663eH7PpaKEKG36eErEQzmV1Qs.tar.zst" }

import pf.Stderr
import pf.Stdout

main! = |_args| {
	Stdout.line!("STDOUT_MARKER_11111")?
	Stderr.line!("STDERR_MARKER_67890")?
	Err(IntentionalFailure)
}
