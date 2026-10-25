app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst" }

import pf.Stdout

main! = |_args| {
	Stdout.line!("QUIET_TEST_FAIL_MARKER")?
	Err(IntentionalFailure)
}
