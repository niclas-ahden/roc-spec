## Assertion helpers for test files.
##
## Each assertion returns a `Try`, so failures can be propagated with `?`:
## ```roc
## Assert.eq(actual, expected)?
## Assert.eq(actual, expected) ? MyTag
## ```
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
