app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
	spec: "../package/main.roc",
}

import pf.Stdout
import spec.TestEnvironment

## TestEnvironment.start! scheduling behavior, exercised with stub effects so
## no real processes are spawned.
main! = |_args| {
	effects = { sleep!: |_ms| {} }

	# All workers ready at once
	all_ready = TestEnvironment.start!(
		effects,
		{
			count: 3,
			spawn!: |_index| Ok({}),
			ready!: |_index| Bool.True,
			max_attempts: 1,
			delay_ms: 0,
		},
	)
	match all_ready {
		Ok({}) => Stdout.line!("PASS: all workers ready")?
		Err(e) => {
			Stdout.line!("FAIL: expected Ok, got ${Str.inspect(e)}")?
			Err(AllReadyFailed)?
		}
	}

	# No worker ever ready: every index is reported after max_attempts rounds
	never_ready = TestEnvironment.start!(
		effects,
		{
			count: 3,
			spawn!: |_index| Ok({}),
			ready!: |_index| Bool.False,
			max_attempts: 2,
			delay_ms: 0,
		},
	)
	match never_ready {
		Err(WorkersNotReady(indices)) =>
			if indices == [0, 1, 2] {
				Stdout.line!("PASS: not-ready workers are all reported")?
			} else {
				Stdout.line!("FAIL: wrong indices reported: ${Str.inspect(indices)}")?
				Err(WrongIndices)?
			}
		other => {
			Stdout.line!("FAIL: expected WorkersNotReady, got ${Str.inspect(other)}")?
			Err(ExpectedWorkersNotReady)?
		}
	}

	# Only even workers become ready: exactly the odd one is reported
	partial = TestEnvironment.start!(
		effects,
		{
			count: 3,
			spawn!: |_index| Ok({}),
			ready!: |index| index % 2 == 0,
			max_attempts: 2,
			delay_ms: 0,
		},
	)
	match partial {
		Err(WorkersNotReady(indices)) =>
			if indices == [1] {
				Stdout.line!("PASS: only the not-ready worker is reported")?
			} else {
				Stdout.line!("FAIL: wrong indices reported: ${Str.inspect(indices)}")?
				Err(WrongPartialIndices)?
			}
		other => {
			Stdout.line!("FAIL: expected WorkersNotReady([1]), got ${Str.inspect(other)}")?
			Err(ExpectedPartialNotReady)?
		}
	}

	# A spawn failure propagates
	spawn_fails = TestEnvironment.start!(
		effects,
		{
			count: 3,
			spawn!: |index| if index == 1 Err(SpawnBoom(index)) else Ok({}),
			ready!: |_index| Bool.True,
			max_attempts: 1,
			delay_ms: 0,
		},
	)
	match spawn_fails {
		Err(SpawnBoom(1)) => Stdout.line!("PASS: spawn error propagates")?
		other => {
			Stdout.line!("FAIL: expected SpawnBoom(1), got ${Str.inspect(other)}")?
			Err(ExpectedSpawnBoom)?
		}
	}

	# Zero workers: trivially ready
	zero_workers = TestEnvironment.start!(
		effects,
		{
			count: 0.U16,
			spawn!: |_index| Ok({}),
			ready!: |_index| Bool.False,
			max_attempts: 1,
			delay_ms: 0,
		},
	)
	match zero_workers {
		Ok({}) => Stdout.line!("PASS: zero workers is trivially ready")
		Err(e) => {
			Stdout.line!("FAIL: expected Ok for zero workers, got ${Str.inspect(e)}")?
			Err(ZeroWorkersFailed)
		}
	}
}
