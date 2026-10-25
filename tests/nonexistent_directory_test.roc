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

	# Run on nonexistent directory - must error, so a typo'd test_dir can
	# never produce a green "0/0 passed" run
	match Spec.run!(PlatformHooks.basic_cli, "tests/this_directory_does_not_exist_12345", config) {
		Err(TestDirNotFound(dir)) =>
			if dir == "tests/this_directory_does_not_exist_12345" {
				Stdout.line!("PASS: Nonexistent directory returns Err(TestDirNotFound) with the directory")
			} else {
				Stdout.line!("FAIL: TestDirNotFound reported the wrong directory: ${dir}")?
				Err(WrongDirectoryReported)
			}

		Err(other) => {
			Stdout.line!("FAIL: Expected TestDirNotFound, got ${Str.inspect(other)}")?
			Err(UnexpectedError)
		}

		Ok(results) => {
			Stdout.line!("FAIL: Expected an error, got ${results.len().to_str()} results")?
			Err(ExpectedError)
		}
	}
}
