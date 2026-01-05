app [main!] {
    pf: platform "../../growthagent/basic-cli/platform/main.roc",
    spec: "../package/main.roc",
}

import pf.Arg
import pf.Stdout
import pf.Cmd
import pf.Dir
import pf.Path
import pf.Utc
import pf.Sleep

dir_list! : Str => Result (List Str) _
dir_list! = |path|
    Dir.list!(path)
    |> Result.map_ok(|paths| List.map(paths, Path.display))

utc_now! : {} => I128
utc_now! = |{}|
    Utc.now!({}) |> Utc.to_millis_since_epoch

no_envs : U64 -> List (Str, Str)
no_envs = |_index| []

import spec.Spec {
    cmd_new: Cmd.new,
    cmd_args: Cmd.args,
    cmd_envs: Cmd.envs,
    cmd_spawn_grouped!: Cmd.spawn_grouped!,
    stdout_line!: Stdout.line!,
    dir_list!: dir_list!,
    utc_now!: utc_now!,
    sleep_millis!: Sleep.millis!,
}

config : Spec.Config []
config = {
    max_workers: 4,
    worker_envs: no_envs,
    before_each!: |_index| Ok({}),
    per_test_timeout_ms: 30_000,
    quiet: Bool.true,
}

main! : List Arg.Arg => Result {} _
main! = |_args|
    # Test 1: No filter -> runs all 3 tests
    results_all = Spec.run_filtered!("tests/filter_fixtures", config, "")?
    count_all = List.len(results_all)
    names_all = List.map(results_all, |r| r.name)
    has_alpha = List.any(names_all, |n| Str.contains(n, "alpha"))
    has_beta = List.any(names_all, |n| Str.contains(n, "beta"))
    has_gamma = List.any(names_all, |n| Str.contains(n, "gamma"))
    all_ok = count_all == 3 && has_alpha && has_beta && has_gamma

    # Test 2: Filter "alpha" -> runs only test_alpha
    results_alpha = Spec.run_filtered!("tests/filter_fixtures", config, "alpha")?
    count_alpha = List.len(results_alpha)
    alpha_has_alpha = List.any(results_alpha, |r| Str.contains(r.name, "alpha"))
    alpha_has_others = List.any(results_alpha, |r| Str.contains(r.name, "beta") || Str.contains(r.name, "gamma"))
    alpha_ok = count_alpha == 1 && alpha_has_alpha && !alpha_has_others

    # Test 3: Filter "eta" -> runs test_beta (contains "eta")
    results_eta = Spec.run_filtered!("tests/filter_fixtures", config, "eta")?
    count_eta = List.len(results_eta)
    eta_has_beta = List.any(results_eta, |r| Str.contains(r.name, "beta"))
    eta_has_others = List.any(results_eta, |r| Str.contains(r.name, "alpha") || Str.contains(r.name, "gamma"))
    eta_ok = count_eta == 1 && eta_has_beta && !eta_has_others

    # Test 4: Filter "nonexistent" -> runs nothing
    results_none = Spec.run_filtered!("tests/filter_fixtures", config, "nonexistent")?
    count_none = List.len(results_none)
    none_ok = count_none == 0

    if all_ok && alpha_ok && eta_ok && none_ok then
        Stdout.line!("PASS: Filtering works correctly (all:3 with alpha/beta/gamma, alpha:1 with alpha, eta:1 with beta, none:0)")
    else if !all_ok then
        Stdout.line!("FAIL: Empty filter should run all 3 tests (alpha, beta, gamma)")?
        Err(AllFilterFailed)
    else if !alpha_ok then
        Stdout.line!("FAIL: 'alpha' filter should run only test_alpha")?
        Err(AlphaFilterFailed)
    else if !eta_ok then
        Stdout.line!("FAIL: 'eta' filter should run only test_beta (contains 'eta')")?
        Err(EtaFilterFailed)
    else
        Stdout.line!("FAIL: 'nonexistent' filter should run no tests")?
        Err(NoneFilterFailed)
