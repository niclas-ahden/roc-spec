app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	spec: "../../package/main.roc",
}

import pf.Stdout
import spec.Assert

main! = |_args| {
	Assert.eq(1 + 1, 2)?
	Assert.contains(["a", "b", "c"], "b")?
	Assert.gt([1, 2, 3].len(), 0)?
	Stdout.line!("math works")
}
