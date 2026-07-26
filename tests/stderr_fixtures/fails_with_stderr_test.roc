app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst" }

import pf.Stderr
import pf.Stdout

main! = |_args| {
	Stdout.line!("STDOUT_MARKER_11111")?
	Stderr.line!("STDERR_MARKER_67890")?
	Err(IntentionalFailure)
}
