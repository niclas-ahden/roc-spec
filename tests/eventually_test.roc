app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	spec: "../package/main.roc",
}

import pf.Sleep
import pf.Stdout
import pf.Utc
import spec.Assert

now_ms! = |{}| Utc.to_millis_since_epoch(Utc.now!()).to_u64_wrap()

main! = |_args| {
	# The one-shot form works without any setup
	Assert.eventually!({ sleep!: Sleep.millis! }, || Ok(42), |v| Assert.eq(v, 42)) ? |e| OneShotShouldPass(e)

	assert = Assert.eventually({ sleep!: Sleep.millis! })

	# An immediate match passes without any waiting
	assert.eq!(|| Ok(42), 42) ? |e| ImmediateMatchShouldPass(e)

	# A value that only settles after 400ms is waited for, and a check can
	# assert several facts about one fetched snapshot. Indexing into the
	# still-short list with ? is safe: its error counts as "not yet".
	settle_start = now_ms!({})
	settling! = || {
		if now_ms!({}).minus_saturated(settle_start) >= 400 {
			Ok(["first", "second"])
		} else {
			Ok(["first"])
		}
	}
	assert.eventually!(settling!, |todos| {
		Assert.eq(todos.len(), 2)?
		Assert.contains(todos.get(1)?, "second")
	}) ? |e| SettlingValueShouldPass(e)
	settle_waited = now_ms!({}).minus_saturated(settle_start)
	if settle_waited < 400 {
		Stdout.line!("FAIL: passed after ${settle_waited.to_str()}ms, before the value settled")?
		return Err(PassedBeforeSettling)
	} else {}

	# A thunk that errors while something boots counts as "not yet",
	# and ok! returns the value once it comes up
	boot_start = now_ms!({})
	erroring! = || {
		if now_ms!({}).minus_saturated(boot_start) >= 300 {
			Ok("up")
		} else {
			Err(ConnectionRefused)
		}
	}
	came_up = assert.ok!(erroring!) ? |e| ErrorsShouldCountAsNotYet(e)
	if came_up != "up" {
		Stdout.line!("FAIL: ok! should return the Ok value, got ${came_up}")?
		return Err(OkReturnedWrongValue)
	} else {}

	# eventually! returns what the check returns, so a settled value can
	# be unwrapped and used
	second = assert.eventually!(|| Ok(["a", "b"]), |items| items.get(1)) ? |e| CheckShouldUnwrap(e)
	if second != "b" {
		Stdout.line!("FAIL: the check's value should flow out, got ${second}")?
		return Err(WrongUnwrappedValue)
	} else {}

	# err! inverts the polarity: it passes once the thunk errors
	stopping! : () => Try(Str, [Refused])
	stopping! = || Err(Refused)
	gone = assert.err!(stopping!) ? |e| ErrShouldPass(e)
	match gone {
		Refused => {}
	}

	# A value that never matches fails after exactly the configured
	# timeout of sleeping, reporting why the last attempt did not match
	mismatch_start = now_ms!({})
	outcome = assert.with_timeout(300).eq!(|| Ok("wrong"), "right")
	mismatch_elapsed = now_ms!({}).minus_saturated(mismatch_start)
	match outcome {
		Ok({}) => {
			Stdout.line!("FAIL: a mismatch should time out")?
			return Err(MismatchShouldTimeOut)
		}
		Err(Timeout({ last, waited_ms })) => {
			if waited_ms != 300 {
				Stdout.line!("FAIL: expected 300ms of sleeping, got ${waited_ms.to_str()}ms")?
				return Err(WrongWaitedMs)
			} else if mismatch_elapsed < 300 {
				Stdout.line!("FAIL: timed out after only ${mismatch_elapsed.to_str()}ms of real time")?
				return Err(TimedOutTooEarly)
			} else if !last.contains("wrong") or !last.contains("right") {
				Stdout.line!("FAIL: diagnostics should name both sides, got last=${last}")?
				return Err(WrongDiagnostics)
			} else {}
		}
		Err(_) => {
			Stdout.line!("FAIL: expected a Timeout error")?
			return Err(WrongErrorTag)
		}
	}

	# The timeout and the retry delays can also be set inline when the
	# assertion is built, instead of through with_timeout
	quick = Assert.eventually({ sleep!: Sleep.millis!, timeout_ms: 200, intervals_ms: [50] })
	quick_outcome = quick.eq!(|| Ok("wrong"), "right")
	match quick_outcome {
		Err(Timeout({ waited_ms, .. })) => {
			if waited_ms != 200 {
				Stdout.line!("FAIL: inline config should time out after 200ms, got ${waited_ms.to_str()}ms")?
				return Err(InlineConfigWrongTimeout)
			} else {}
		}
		_ => {
			Stdout.line!("FAIL: inline config mismatch should time out")?
			return Err(InlineConfigShouldTimeOut)
		}
	}

	# The one-shot form takes the same inline overrides
	one_shot = Assert.eventually!(
		{ sleep!: Sleep.millis!, timeout_ms: 100 },
		|| Ok("wrong"),
		|v| Assert.eq(v, "right"),
	)
	match one_shot {
		Err(Timeout({ waited_ms, .. })) => {
			if waited_ms != 100 {
				Stdout.line!("FAIL: one-shot inline timeout should be 100ms, got ${waited_ms.to_str()}ms")?
				return Err(OneShotWrongTimeout)
			} else {}
		}
		_ => {
			Stdout.line!("FAIL: one-shot mismatch should time out")?
			return Err(OneShotShouldTimeOut)
		}
	}

	# A thunk that never stops erroring also times out, with the error
	# as the last thing seen
	stuck = assert.with_timeout(200).eq!(|| Err(StillBooting), "never")
	match stuck {
		Err(Timeout({ last, .. })) => {
			if !last.contains("StillBooting") {
				Stdout.line!("FAIL: the last error should be reported, got ${last}")?
				return Err(LastErrorNotReported)
			} else {}
		}
		_ => {
			Stdout.line!("FAIL: a stuck thunk should time out")?
			return Err(StuckThunkShouldTimeOut)
		}
	}

	Stdout.line!("PASS: Assert.eventually retries, waits through errors, and times out with diagnostics")
}
