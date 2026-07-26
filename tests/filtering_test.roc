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

config = {
	max_workers: 4,
	worker_envs: no_envs,
	before_each!: |_index| Ok({}),
	per_test_timeout_ms: 30_000,
	quiet: Bool.True,
	fail_fast: Bool.False,
}

main! = |_args| {
	# Test 1: No filter -> runs all 3 tests
	results_all = Spec.run_filtered!(effects, "tests/filter_fixtures", config, "")?
	count_all = results_all.len()
	names_all = results_all.map(|r| r.name)
	has_alpha = names_all.any(|n| n.contains("alpha"))
	has_beta = names_all.any(|n| n.contains("beta"))
	has_gamma = names_all.any(|n| n.contains("gamma"))
	all_ok = count_all == 3 and has_alpha and has_beta and has_gamma

	# Test 2: Filter "alpha" -> runs only alpha_test
	results_alpha = Spec.run_filtered!(effects, "tests/filter_fixtures", config, "alpha")?
	count_alpha = results_alpha.len()
	alpha_has_alpha = results_alpha.any(|r| r.name.contains("alpha"))
	alpha_has_others = results_alpha.any(|r| r.name.contains("beta") or r.name.contains("gamma"))
	alpha_ok = count_alpha == 1 and alpha_has_alpha and !alpha_has_others

	# Test 3: Filter "eta" -> runs beta_test (contains "eta")
	results_eta = Spec.run_filtered!(effects, "tests/filter_fixtures", config, "eta")?
	count_eta = results_eta.len()
	eta_has_beta = results_eta.any(|r| r.name.contains("beta"))
	eta_has_others = results_eta.any(|r| r.name.contains("alpha") or r.name.contains("gamma"))
	eta_ok = count_eta == 1 and eta_has_beta and !eta_has_others

	# Test 4: Filter "nonexistent" -> runs nothing
	results_none = Spec.run_filtered!(effects, "tests/filter_fixtures", config, "nonexistent")?
	count_none = results_none.len()
	none_ok = count_none == 0

	# Test 5: The pattern matches the whole test name, not just the filename,
	# so a directory prefix selects everything under that directory
	results_dir = Spec.run_filtered!(effects, "tests/nested_fixtures", config, "level1/")?
	names_dir = results_dir.map(|r| r.name)
	dir_ok =
		results_dir.len() == 3
			and names_dir.contains("level1/level1_test")
				and names_dir.contains("level1/level2/level2_test")
					and names_dir.contains("level1/level2/level3/level3_test")

	# Test 6: A full name pinpoints a single test in a subdirectory
	results_exact = Spec.run_filtered!(effects, "tests/nested_fixtures", config, "level1/level1_test")?
	exact_ok = results_exact.map(|r| r.name) == ["level1/level1_test"]

	if all_ok and alpha_ok and eta_ok and none_ok and dir_ok and exact_ok {
		Stdout.line!("PASS: Filtering works correctly (all:3, alpha:1, eta:1, none:0, level1/:3, exact:1)")
	} else if !all_ok {
		Stdout.line!("FAIL: Empty filter should run all 3 tests (alpha, beta, gamma)")?
		Err(AllFilterFailed)
	} else if !alpha_ok {
		Stdout.line!("FAIL: 'alpha' filter should run only alpha_test")?
		Err(AlphaFilterFailed)
	} else if !eta_ok {
		Stdout.line!("FAIL: 'eta' filter should run only beta_test (contains 'eta')")?
		Err(EtaFilterFailed)
	} else if !none_ok {
		Stdout.line!("FAIL: 'nonexistent' filter should run no tests")?
		Err(NoneFilterFailed)
	} else if !dir_ok {
		Stdout.line!("FAIL: 'level1/' filter should run the 3 tests under level1")?
		Err(DirFilterFailed)
	} else {
		Stdout.line!("FAIL: 'level1/level1_test' filter should run exactly that test")?
		Err(ExactFilterFailed)
	}
}
