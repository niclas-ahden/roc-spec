app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	spec: "../package/main.roc",
}

import pf.Stdout
import spec.Spec
import PlatformHooks

no_envs = |_index| []

main! = |_args| {
	config = {
		test_command: ["roc", "--opt=speed"],
		max_workers: 4,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	# Run on empty directory
	results = Spec.run!(PlatformHooks.basic_cli, "tests/empty_fixtures", config)?

	if results.is_empty() {
		Stdout.line!("PASS: Empty directory returns empty results list")
	} else {
		Stdout.line!("FAIL: Expected empty results, got ${results.len().to_str()} results")?
		Err(ExpectedEmptyResults)
	}
}
