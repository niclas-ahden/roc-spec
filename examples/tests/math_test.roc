app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
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
