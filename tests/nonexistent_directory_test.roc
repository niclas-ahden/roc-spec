app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
	spec: "../package/main.roc",
}

import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stdout
import pf.Utc
import spec.Spec

effects = {
	spawn_test!: |file, envs|
		Cmd.new(OsStr.utf8("roc"))
			.args_str(["--opt=speed", file])
			.envs_str(envs)
			.spawn_grouped!(),
	poll!: Cmd.Child.poll!,
	kill_wait!: Cmd.Child.kill_wait!,
	list_dir!: |dir| Path.list!(Path.utf8(dir)).map_ok(|entries| entries.map(Path.display)),
	print!: Stdout.line!,
	utc_now!: Utc.now!,
	sleep_millis!: Sleep.millis!,
}

no_envs = |_index| []

main! = |_args| {
	config = {
		max_workers: 4,
		worker_envs: no_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 30_000,
		quiet: Bool.True,
		fail_fast: Bool.False,
	}

	# Run on nonexistent directory - must error, so a typo'd test_dir can
	# never produce a green "0/0 passed" run
	match Spec.run!(effects, "tests/this_directory_does_not_exist_12345", config) {
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
