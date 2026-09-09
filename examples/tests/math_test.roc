app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst",
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
