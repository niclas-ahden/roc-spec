app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst" }

import pf.Env
import pf.Sleep
import pf.Stdout

main! = |_args| {
	Sleep.millis!(100)?
	match Env.var_str!("WORKER_INDEX") {
		Ok(val) =>
			Stdout.line!("WORKER_INDEX=${val}")

		Err(_) => {
			Stdout.line!("FAIL: WORKER_INDEX not set")?
			Err(EnvVarNotSet)
		}
	}
}
