app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	spec: "../../package/main.roc",
}

import pf.Env
import pf.Stdout
import spec.Assert

# The example runner sets ROC_SPEC_EXAMPLE_WORKER via `worker_envs`.
main! = |_args| {
	worker = Env.var_str!("ROC_SPEC_EXAMPLE_WORKER") ? |_| WorkerEnvNotSet
	Assert.true(!worker.is_empty())?
	Stdout.line!("running on worker ${worker}")
}
