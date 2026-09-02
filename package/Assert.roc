## Assertion helpers for test files.
##
## Each assertion returns a `Try`, so failures can be propagated with `?`:
## ```roc
## Assert.eq(actual, expected)?
## Assert.eq(actual, expected) ? MyTag
## ```
##
## For values that settle asynchronously (a browser rendering, a server
## booting), `Assert.eventually` builds a retrying assertion that re-runs a
## fetch until it matches. See [Assert.eventually] and [Assert.eventually!].
Assert :: [].{

	## Assert two values are equal.
	##
	## ```roc
	## Assert.eq(actual, expected)?
	## Assert.eq(actual, expected) ? MyTag
	## ```
	eq : val, val -> Try({}, [NotEq(Str), ..]) where [val.is_eq : val, val -> Bool]
	eq = |actual, expected|
		if actual == expected {
			Ok({})
		} else {
			Err(NotEq("${Str.inspect(actual)} should equal ${Str.inspect(expected)}, but it doesn't."))
		}

	## Assert two values are not equal.
	##
	## ```roc
	## Assert.not_eq(actual, unexpected)?
	## Assert.not_eq(actual, unexpected) ? MyTag
	## ```
	not_eq : val, val -> Try({}, [IsEq(Str), ..]) where [val.is_eq : val, val -> Bool]
	not_eq = |actual, unexpected|
		if actual != unexpected {
			Ok({})
		} else {
			Err(IsEq("${Str.inspect(actual)} should not equal ${Str.inspect(unexpected)}, but it does."))
		}

	## Assert a Try is Ok, returning the inner value.
	##
	## ```roc
	## value = Assert.ok(try)?
	## value = Assert.ok(try) ? MyTag
	## ```
	ok : Try(a, err) -> Try(a, [NotOk(Str), ..])
	ok = |try|
		match try {
			Ok(value) => Ok(value)
			Err(e) => Err(NotOk("Expected Ok, but got Err(${Str.inspect(e)})."))
		}

	## Assert a Try is Err, returning the error.
	##
	## ```roc
	## error = Assert.err(try)?
	## error = Assert.err(try) ? MyTag
	## ```
	err : Try(a, e) -> Try(e, [NotErr(Str), ..])
	err = |try|
		match try {
			Err(e) => Ok(e)
			Ok(value) => Err(NotErr("Expected Err, but got Ok(${Str.inspect(value)})."))
		}

	## Assert a Maybe is Just, returning the inner value.
	##
	## ```roc
	## value = Assert.just(maybe)?
	## value = Assert.just(maybe) ? MyTag
	## ```
	just : [Just(val), Nothing] -> Try(val, [NotJust(Str), ..])
	just = |maybe|
		match maybe {
			Just(value) => Ok(value)
			Nothing => Err(NotJust("Expected Just, but got Nothing."))
		}

	## Assert a Maybe is Nothing.
	##
	## ```roc
	## Assert.nothing(maybe)?
	## Assert.nothing(maybe) ? MyTag
	## ```
	nothing : [Just(val), Nothing] -> Try({}, [NotNothing(Str), ..])
	nothing = |maybe|
		match maybe {
			Nothing => Ok({})
			Just(value) => Err(NotNothing("Expected Nothing, but got Just(${Str.inspect(value)})."))
		}

	## Assert a Bool is true.
	##
	## ```roc
	## Assert.true(condition)?
	## Assert.true(condition) ? MyTag
	## ```
	true : Bool -> Try({}, [NotTrue(Str), ..])
	true = |value|
		if value {
			Ok({})
		} else {
			Err(NotTrue("Expected true, but got false."))
		}

	## Assert a Bool is false.
	##
	## ```roc
	## Assert.false(condition)?
	## Assert.false(condition) ? MyTag
	## ```
	false : Bool -> Try({}, [NotFalse(Str), ..])
	false = |value|
		if !value {
			Ok({})
		} else {
			Err(NotFalse("Expected false, but got true."))
		}

	## Assert a collection contains an element.
	##
	## Constrained on `contains` rather than on `List`, so this works on a
	## `Str` (substring) as well as on a `List` (element).
	##
	## ```roc
	## Assert.contains([1, 2, 3], 2)?
	## Assert.contains(body, "alice") ? MyTag
	## ```
	contains : coll, elem -> Try({}, [DoesNotContain(Str), ..]) where [coll.contains : coll, elem -> Bool]
	contains = |collection, element|
		if collection.contains(element) {
			Ok({})
		} else {
			Err(DoesNotContain("${Str.inspect(collection)} should contain ${Str.inspect(element)}, but it doesn't."))
		}

	## Assert a collection does not contain an element.
	##
	## Constrained on `contains` rather than on `List`, so this works on a
	## `Str` (substring) as well as on a `List` (element).
	##
	## ```roc
	## Assert.not_contains([1, 2, 3], 4)?
	## Assert.not_contains(body, "password") ? MyTag
	## ```
	not_contains : coll, elem -> Try({}, [DoesContain(Str), ..]) where [coll.contains : coll, elem -> Bool]
	not_contains = |collection, element|
		if collection.contains(element) {
			Err(DoesContain("${Str.inspect(collection)} should not contain ${Str.inspect(element)}, but it does."))
		} else {
			Ok({})
		}

	## Assert actual is greater than threshold.
	##
	## ```roc
	## Assert.gt(count, 0)?
	## Assert.gt(count, 0) ? MyTag
	## ```
	gt : a, a -> Try({}, [NotGt(Str), ..]) where [a.is_gt : a, a -> Bool]
	gt = |actual, threshold|
		if actual > threshold {
			Ok({})
		} else {
			Err(NotGt("${Str.inspect(actual)} should be greater than ${Str.inspect(threshold)}, but it wasn't."))
		}

	## Assert actual is greater than or equal to threshold.
	##
	## ```roc
	## Assert.gte(count, 1)?
	## Assert.gte(count, 1) ? MyTag
	## ```
	gte : a, a -> Try({}, [NotGte(Str), ..]) where [a.is_gte : a, a -> Bool]
	gte = |actual, threshold|
		if actual >= threshold {
			Ok({})
		} else {
			Err(NotGte("${Str.inspect(actual)} should be greater than or equal to ${Str.inspect(threshold)}, but it wasn't."))
		}

	## Assert actual is less than threshold.
	##
	## ```roc
	## Assert.lt(errors, 10)?
	## Assert.lt(errors, 10) ? MyTag
	## ```
	lt : a, a -> Try({}, [NotLt(Str), ..]) where [a.is_lt : a, a -> Bool]
	lt = |actual, threshold|
		if actual < threshold {
			Ok({})
		} else {
			Err(NotLt("${Str.inspect(actual)} should be less than ${Str.inspect(threshold)}, but it wasn't."))
		}

	## Assert actual is less than or equal to threshold.
	##
	## ```roc
	## Assert.lte(errors, 5)?
	## Assert.lte(errors, 5) ? MyTag
	## ```
	lte : a, a -> Try({}, [NotLte(Str), ..]) where [a.is_lte : a, a -> Bool]
	lte = |actual, threshold|
		if actual <= threshold {
			Ok({})
		} else {
			Err(NotLte("${Str.inspect(actual)} should be less than or equal to ${Str.inspect(threshold)}, but it wasn't."))
		}

	## Config for [Assert.eventually] and [Assert.eventually!]. Only
	## `sleep!` is required (basic-cli's `Sleep.millis!` fits), the timeout
	## and the delays between attempts have defaults.
	EventuallyConfig := {
		sleep! : U64 => {},
		timeout_ms : U64 ?? 5000,
		intervals_ms : List(U64) ?? [100, 250, 500, 1000],
	}

	## A configured retrying assertion (see [Assert.eventually]). The
	## matchers re-run an effectful fetch until it matches, sleeping
	## between attempts, so they can assert on values that settle
	## asynchronously: a browser rendering, a server booting, a file
	## another process writes.
	Eventually :: {
		sleep! : U64 => {},
		timeout_ms : U64,
		intervals_ms : List(U64),
	}.{

		## The same matchers with a different timeout, for a one-off
		## tighter or looser call:
		## `assert.with_timeout(500).eq!(...)`
		with_timeout : Eventually, U64 -> Eventually
		with_timeout = |self, timeout_ms| { ..self, timeout_ms: timeout_ms }

		## Assert the thunk's fetched value eventually passes the check,
		## returning what the check returns.
		##
		## The check judges one fetched snapshot with any of the plain
		## `Assert` matchers (or anything else returning a `Try`), so
		## several facts can be asserted about a single consistent value.
		## Any error inside the check counts as "not yet", which makes
		## partial reads of still-settling data safe:
		##
		## ```roc
		## assert.eventually!(|| fetch_todos!(), |todos| {
		##     Assert.eq(todos.len(), 2)?
		##     # OutOfBounds while the list is short just retries
		##     Assert.contains(todos.get(1)?, "milk")
		## }) ? |e| TodosShouldSettle(e)
		## ```
		eventually! : Eventually, (() => Try(val, thunk_err)), (val -> Try(out, check_err)) => Try(out, [Timeout({ last : Str, waited_ms : U64 }), ..])
		eventually! = |self, thunk!, check|
			poll!(
				self,
				thunk!,
				|outcome| match outcome {
					Ok(value) => check(value).map_err(|e| Str.inspect(e))
					Err(e) => Err("Err(${Str.inspect(e)})")
				},
			)

		## Assert the thunk eventually returns `Ok` of the expected value.
		## Sugar for the most common check:
		##
		## ```roc
		## assert.eq!(|| fetch_count!(), "2 items left") ? |e| CountShouldSettle(e)
		## ```
		eq! : Eventually, (() => Try(val, thunk_err)), val => Try({}, [Timeout({ last : Str, waited_ms : U64 }), ..]) where [val.is_eq : val, val -> Bool]
		eq! = |self, thunk!, expected|
			Eventually.eventually!(self, thunk!, |value| Assert.eq(value, expected))

		## Assert the thunk eventually succeeds, returning what it
		## returned. For waiting on something to come up:
		##
		## ```roc
		## body = assert.ok!(|| Http.get_utf8!(health_url)) ? |e| ServerShouldBoot(e)
		## ```
		ok! : Eventually, (() => Try(val, thunk_err)) => Try(val, [Timeout({ last : Str, waited_ms : U64 }), ..])
		ok! = |self, thunk!|
			poll!(
				self,
				thunk!,
				|outcome| match outcome {
					Ok(value) => Ok(value)
					Err(e) => Err("Err(${Str.inspect(e)})")
				},
			)

		## Assert the thunk eventually errors, returning the error. For
		## waiting on something to go away: a server shutting down, a
		## file deleted.
		err! : Eventually, (() => Try(val, thunk_err)) => Try(thunk_err, [Timeout({ last : Str, waited_ms : U64 }), ..])
		err! = |self, thunk!|
			poll!(
				self,
				thunk!,
				|outcome| match outcome {
					Ok(value) => Err(Str.inspect(value))
					Err(e) => Ok(e)
				},
			)

		# The shared loop: `judge` turns the thunk's latest outcome into
		# the matcher's result, with an `Err` explaining why this attempt
		# did not match, kept for the Timeout diagnostics. Only time spent
		# sleeping counts toward the timeout, and no sleep overshoots it,
		# so `timeout_ms: 300` sleeps exactly 300ms before giving up (in
		# delays of 100 then 200).
		poll! : Eventually, (() => Try(val, thunk_err)), (Try(val, thunk_err) -> Try(out, Str)) => Try(out, [Timeout({ last : Str, waited_ms : U64 }), ..])
		poll! = |self, thunk!, judge|
			Eventually.retry!(self, thunk!, judge, 0, self.intervals_ms)

		# `waited_ms` accumulates the sleeps so far, `intervals_ms`
		# shrinks until its last delay repeats.
		retry! : Eventually, (() => Try(val, thunk_err)), (Try(val, thunk_err) -> Try(out, Str)), U64, List(U64) => Try(out, [Timeout({ last : Str, waited_ms : U64 }), ..])
		retry! = |self, thunk!, judge, waited_ms, intervals_ms|
			match judge(thunk!()) {
				Ok(out) => Ok(out)
				Err(last) =>
					if waited_ms >= self.timeout_ms {
						Err(Timeout({ last, waited_ms }))
					} else {
						(delay, rest) = next_interval(intervals_ms)
						remaining = self.timeout_ms - waited_ms
						capped = if delay > remaining remaining else delay
						sleep! = self.sleep!
						sleep!(capped)
						Eventually.retry!(self, thunk!, judge, waited_ms + capped, rest)
					}
				}

		## The next delay and the intervals left after it. The last
		## interval repeats forever, and an empty list falls back to 100ms.
		next_interval : List(U64) -> (U64, List(U64))
		next_interval = |intervals_ms| {
			delay = intervals_ms.first().ok_or(100)
			rest = if intervals_ms.len() > 1 intervals_ms.drop_first(1) else intervals_ms
			(delay, rest)
		}
	}

	## A retrying assertion for values that settle asynchronously. Build it
	## once at the top of a test, capturing `sleep!` (basic-cli's
	## `Sleep.millis!` fits), then assert with it anywhere without passing
	## `sleep!` again:
	##
	## ```roc
	## assert = Assert.eventually({ sleep!: Sleep.millis! })
	##
	## assert.eq!(|| fetch_count!(), "2 items left") ? |e| CountShouldSettle(e)
	## assert.eventually!(|| fetch_todos!(), |todos| Assert.contains(todos, "milk"))?
	## body = assert.ok!(|| Http.get_utf8!(url)) ? |e| ServerShouldBoot(e)
	## ```
	##
	## Defaults to a 5s timeout with growing delays of 100/250/500/1000ms
	## between attempts. Both can be overridden inline:
	##
	## ```roc
	## assert = Assert.eventually({ sleep!: Sleep.millis!, timeout_ms: 500, intervals_ms: [50] })
	## ```
	##
	## A thunk `Err` counts as "not yet", not as failure
	## (except in `ok!` and `err!`, where the `Try` itself is what is
	## matched), so polling something that is still starting up works
	## without special casing. The first match returns immediately, so a
	## passing assertion never waits. On timeout the error reports why the
	## last attempt did not match and how long was waited.
	##
	## For a single retrying assertion, `Assert.eventually!` skips the
	## intermediate value.
	eventually : EventuallyConfig -> Eventually
	eventually = |config| {
		sleep!: config.sleep!,
		timeout_ms: config.timeout_ms,
		intervals_ms: config.intervals_ms,
	}

	## One-shot form of [Assert.eventually], for a test with a single
	## retrying assertion:
	##
	## ```roc
	## Assert.eventually!({ sleep!: Sleep.millis! }, || fetch_count!(), |count| Assert.eq(count, 2))?
	## ```
	eventually! : EventuallyConfig, (() => Try(val, thunk_err)), (val -> Try(out, check_err)) => Try(out, [Timeout({ last : Str, waited_ms : U64 }), ..])
	eventually! = |config, thunk!, check|
		Assert.eventually(config).eventually!(thunk!, check)
}

# Tests for eq
expect Assert.eq(1, 1) == Ok({})
expect Assert.eq("hello", "hello") == Ok({})
expect
	match Assert.eq(1, 2) {
		Err(NotEq(_)) => Bool.True
		_ => Bool.False
	}

# Tests for not_eq
expect Assert.not_eq(1, 2) == Ok({})
expect
	match Assert.not_eq(1, 1) {
		Err(IsEq(_)) => Bool.True
		_ => Bool.False
	}

# Tests for ok
expect {
	input : Try(U64, Str)
	input = Ok(42)
	Assert.ok(input) == Ok(42)
}
expect {
	input : Try(U64, Str)
	input = Err("failed")
	Assert.ok(input).is_err()
}

# Tests for err
expect {
	input : Try(U64, Str)
	input = Err("failed")
	Assert.err(input) == Ok("failed")
}
expect {
	input : Try(U64, Str)
	input = Ok(42)
	Assert.err(input).is_err()
}

# Tests for just
expect Assert.just(Just(42)) == Ok(42)
expect Assert.just(Nothing).is_err()

# Tests for nothing
expect {
	input : [Just(U64), Nothing]
	input = Nothing
	Assert.nothing(input) == Ok({})
}
expect {
	input : [Just(U64), Nothing]
	input = Just(42)
	Assert.nothing(input).is_err()
}

# Tests for true
expect Assert.true(Bool.True) == Ok({})
expect Assert.true(Bool.False).is_err()

# Tests for false
expect Assert.false(Bool.False) == Ok({})
expect Assert.false(Bool.True).is_err()

# Tests for contains
expect Assert.contains([1, 2, 3], 2) == Ok({})
expect Assert.contains([1, 2, 3], 4).is_err()
expect Assert.contains([], 1).is_err()
expect Assert.contains("alice and bob", "alice") == Ok({})
expect Assert.contains("alice and bob", "carol").is_err()

# Tests for not_contains
expect Assert.not_contains([1, 2, 3], 4) == Ok({})
expect Assert.not_contains([1, 2, 3], 2).is_err()
expect Assert.not_contains([], 1) == Ok({})
expect Assert.not_contains("alice and bob", "carol") == Ok({})
expect Assert.not_contains("alice and bob", "alice").is_err()

# Tests for gt
expect Assert.gt(5, 3) == Ok({})
expect Assert.gt(3, 3).is_err()
expect Assert.gt(2, 3).is_err()

# Tests for gte
expect Assert.gte(5, 3) == Ok({})
expect Assert.gte(3, 3) == Ok({})
expect Assert.gte(2, 3).is_err()

# Tests for lt
expect Assert.lt(2, 3) == Ok({})
expect Assert.lt(3, 3).is_err()
expect Assert.lt(5, 3).is_err()

# Tests for lte
expect Assert.lte(2, 3) == Ok({})
expect Assert.lte(3, 3) == Ok({})
expect Assert.lte(5, 3).is_err()

# Tests for Eventually.next_interval: delays are consumed until the last
# one, which repeats.
expect Assert.Eventually.next_interval([100, 250, 500]) == (100, [250, 500])
expect Assert.Eventually.next_interval([250, 500]) == (250, [500])
expect Assert.Eventually.next_interval([500]) == (500, [500])
expect Assert.Eventually.next_interval([]) == (100, [])
