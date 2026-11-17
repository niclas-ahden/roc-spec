app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst" }

import pf.Stdout

main! = |_args| {
	Stdout.line!("QUIET_TEST_FAIL_MARKER")?
	Err(IntentionalFailure)
}
