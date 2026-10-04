app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst" }

import pf.Stderr
import pf.Stdout

main! = |_args| {
	Stdout.line!("STDOUT_MARKER_11111")?
	Stderr.line!("STDERR_MARKER_67890")?
	Err(IntentionalFailure)
}
