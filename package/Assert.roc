module [eq, not_eq, ok, err, just, nothing, true, false, contains, not_contains, gt, gte, lt, lte]

## Assert two values are equal.
##
## ```roc
## Assert.eq(actual, expected)?
## Assert.eq(actual, expected) ? MyTag
## ```
eq : val, val -> Result {} [NotEq Str] where val implements Inspect & Eq
eq = |actual, expected|
    if actual == expected then
        Ok({})
    else
        Err(NotEq("$(Inspect.to_str(actual)) should equal $(Inspect.to_str(expected)), but it doesn't."))

## Assert two values are not equal.
##
## ```roc
## Assert.not_eq(actual, unexpected)?
## Assert.not_eq(actual, unexpected) ? MyTag
## ```
not_eq : val, val -> Result {} [IsEq Str] where val implements Inspect & Eq
not_eq = |actual, unexpected|
    if actual != unexpected then
        Ok({})
    else
        Err(IsEq("$(Inspect.to_str(actual)) should not equal $(Inspect.to_str(unexpected)), but it does."))

## Assert a Result is Ok, returning the inner value.
##
## ```roc
## value = Assert.ok(result)?
## value = Assert.ok(result) ? MyTag
## ```
ok : Result a err -> Result a [NotOk Str] where err implements Inspect
ok = |result|
    when result is
        Ok(value) -> Ok(value)
        Err(e) -> Err(NotOk("Expected Ok, but got Err($(Inspect.to_str(e)))."))

## Assert a Result is Err, returning the error.
##
## ```roc
## error = Assert.err(result)?
## error = Assert.err(result) ? MyTag
## ```
err : Result a e -> Result e [NotErr Str] where a implements Inspect
err = |result|
    when result is
        Err(e) -> Ok(e)
        Ok(value) -> Err(NotErr("Expected Err, but got Ok($(Inspect.to_str(value)))."))

## Assert a Maybe is Just, returning the inner value.
##
## ```roc
## value = Assert.just(maybe)?
## value = Assert.just(maybe) ? MyTag
## ```
just : [Just val, Nothing] -> Result val [NotJust Str]
just = |maybe|
    when maybe is
        Just(value) -> Ok(value)
        Nothing -> Err(NotJust("Expected Just, but got Nothing."))

## Assert a Maybe is Nothing.
##
## ```roc
## Assert.nothing(maybe)?
## Assert.nothing(maybe) ? MyTag
## ```
nothing : [Just val, Nothing] -> Result {} [NotNothing Str] where val implements Inspect
nothing = |maybe|
    when maybe is
        Nothing -> Ok({})
        Just(value) -> Err(NotNothing("Expected Nothing, but got Just($(Inspect.to_str(value)))."))

## Assert a Bool is true.
##
## ```roc
## Assert.true(condition)?
## Assert.true(condition) ? MyTag
## ```
true : Bool -> Result {} [NotTrue Str]
true = |value|
    if value then
        Ok({})
    else
        Err(NotTrue("Expected true, but got false."))

## Assert a Bool is false.
##
## ```roc
## Assert.false(condition)?
## Assert.false(condition) ? MyTag
## ```
false : Bool -> Result {} [NotFalse Str]
false = |value|
    if Bool.not(value) then
        Ok({})
    else
        Err(NotFalse("Expected false, but got true."))

## Assert a List contains an element.
##
## ```roc
## Assert.contains(list, element)?
## Assert.contains(list, element) ? MyTag
## ```
contains : List a, a -> Result {} [DoesNotContain Str] where a implements Inspect & Eq
contains = |list, element|
    if List.contains(list, element) then
        Ok({})
    else
        Err(DoesNotContain("List should contain $(Inspect.to_str(element)), but it doesn't."))

## Assert a List does not contain an element.
##
## ```roc
## Assert.not_contains(list, element)?
## Assert.not_contains(list, element) ? MyTag
## ```
not_contains : List a, a -> Result {} [DoesContain Str] where a implements Inspect & Eq
not_contains = |list, element|
    if List.contains(list, element) then
        Err(DoesContain("List should not contain $(Inspect.to_str(element)), but it does."))
    else
        Ok({})

## Assert actual is greater than threshold.
##
## ```roc
## Assert.gt(count, 0)?
## Assert.gt(count, 0) ? MyTag
## ```
gt : Num a, Num a -> Result {} [NotGt Str] where a implements Inspect
gt = |actual, threshold|
    if actual > threshold then
        Ok({})
    else
        Err(NotGt("$(Inspect.to_str(actual)) should be greater than $(Inspect.to_str(threshold)), but it wasn't."))

## Assert actual is greater than or equal to threshold.
##
## ```roc
## Assert.gte(count, 1)?
## Assert.gte(count, 1) ? MyTag
## ```
gte : Num a, Num a -> Result {} [NotGte Str] where a implements Inspect
gte = |actual, threshold|
    if actual >= threshold then
        Ok({})
    else
        Err(NotGte("$(Inspect.to_str(actual)) should be greater than or equal to $(Inspect.to_str(threshold)), but it wasn't."))

## Assert actual is less than threshold.
##
## ```roc
## Assert.lt(errors, 10)?
## Assert.lt(errors, 10) ? MyTag
## ```
lt : Num a, Num a -> Result {} [NotLt Str] where a implements Inspect
lt = |actual, threshold|
    if actual < threshold then
        Ok({})
    else
        Err(NotLt("$(Inspect.to_str(actual)) should be less than $(Inspect.to_str(threshold)), but it wasn't."))

## Assert actual is less than or equal to threshold.
##
## ```roc
## Assert.lte(errors, 5)?
## Assert.lte(errors, 5) ? MyTag
## ```
lte : Num a, Num a -> Result {} [NotLte Str] where a implements Inspect
lte = |actual, threshold|
    if actual <= threshold then
        Ok({})
    else
        Err(NotLte("$(Inspect.to_str(actual)) should be less than or equal to $(Inspect.to_str(threshold)), but it wasn't."))

# Tests for eq
expect eq(1, 1) == Ok({})
expect eq("hello", "hello") == Ok({})
expect
    when eq(1, 2) is
        Err(NotEq(_)) -> Bool.true
        _ -> Bool.false

# Tests for not_eq
expect not_eq(1, 2) == Ok({})
expect
    when not_eq(1, 1) is
        Err(IsEq(_)) -> Bool.true
        _ -> Bool.false

# Tests for ok
expect
    input : Result U64 Str
    input = Ok(42)
    ok(input) == Ok(42)
expect
    input : Result U64 Str
    input = Err("failed")
    ok(input) |> Result.is_err

# Tests for err
expect
    input : Result U64 Str
    input = Err("failed")
    err(input) == Ok("failed")
expect
    input : Result U64 Str
    input = Ok(42)
    err(input) |> Result.is_err

# Tests for just
expect just(Just(42)) == Ok(42)
expect just(Nothing) |> Result.is_err

# Tests for nothing
expect
    input : [Just U64, Nothing]
    input = Nothing
    nothing(input) == Ok({})
expect
    input : [Just U64, Nothing]
    input = Just(42)
    nothing(input) |> Result.is_err

# Tests for true
expect true(Bool.true) == Ok({})
expect true(Bool.false) |> Result.is_err

# Tests for false
expect false(Bool.false) == Ok({})
expect false(Bool.true) |> Result.is_err

# Tests for contains
expect contains([1, 2, 3], 2) == Ok({})
expect contains([1, 2, 3], 4) |> Result.is_err
expect contains([], 1) |> Result.is_err

# Tests for not_contains
expect not_contains([1, 2, 3], 4) == Ok({})
expect not_contains([1, 2, 3], 2) |> Result.is_err
expect not_contains([], 1) == Ok({})

# Tests for gt
expect gt(5, 3) == Ok({})
expect gt(3, 3) |> Result.is_err
expect gt(2, 3) |> Result.is_err

# Tests for gte
expect gte(5, 3) == Ok({})
expect gte(3, 3) == Ok({})
expect gte(2, 3) |> Result.is_err

# Tests for lt
expect lt(2, 3) == Ok({})
expect lt(3, 3) |> Result.is_err
expect lt(5, 3) |> Result.is_err

# Tests for lte
expect lte(2, 3) == Ok({})
expect lte(3, 3) == Ok({})
expect lte(5, 3) |> Result.is_err
