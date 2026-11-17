app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst" }

import pf.Stderr
import pf.Stdout

main! = |_args| {
	Stdout.line!("STDOUT_MARKER_11111")?
	Stderr.line!("STDERR_MARKER_67890")?
	Err(IntentionalFailure)
}
