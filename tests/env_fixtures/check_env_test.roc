app [main!] { pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst" }

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
