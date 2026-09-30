app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.27.0/HZanbveSUDoJF8LypR663eH7PpaKEKG36eErEQzmV1Qs.tar.zst",
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
