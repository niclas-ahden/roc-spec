app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst" }

import pf.Env
import pf.Stdout

main! = |_args|
	match Env.var_str!("TEST_WORKER_ID") {
		Ok(val) =>
			Stdout.line!("Worker ID: ${val}")

		Err(_) => {
			Stdout.line!("FAIL: TEST_WORKER_ID not set")?
			Err(EnvVarNotSet)
		}
	}
