app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst" }

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
