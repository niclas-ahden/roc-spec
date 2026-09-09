app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.25.0/EsdzLgcAyudLYkMqiHXGuq2xMhPhoP1GRQWb14jZxZbY.tar.zst",
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
