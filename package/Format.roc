## Formatting utilities for test output display.
##
## Note: This module exists separately from Spec.roc because of a compiler bug
## that crashes `roc test` when expect tests are added to modules with complex
## effectful code. Once the new Roc compiler is released, these could be inlined
## back into Spec.roc.
module [
    format_duration,
    indent_lines,
    green_check,
    red_x,
]

## Format duration in human-readable form.
## < 1000ms: "Nms"
## >= 1000ms: "N.Ns"
format_duration : I128 -> Str
format_duration = |ms|
    if ms < 1000 then
        "$(Num.to_str(ms))ms"
    else
        seconds = Num.to_f64(ms) / 1000.0
        "$(Num.to_str(seconds))s"

expect format_duration(0) == "0ms"
expect format_duration(500) == "500ms"
expect format_duration(999) == "999ms"
expect format_duration(1000) == "1s"
expect format_duration(1500) == "1.5s"
expect format_duration(2500) == "2.5s"

## Indent each line with "    | " prefix for test output display.
indent_lines : Str -> Str
indent_lines = |str|
    str
    |> Str.split_on("\n")
    |> List.map(|line| "    | $(line)")
    |> Str.join_with("\n")

expect indent_lines("hello") == "    | hello"
expect indent_lines("line1\nline2") == "    | line1\n    | line2"
expect indent_lines("") == "    | "

## Green checkmark for passing tests.
green_check : Str
green_check = "\u(001b)[32m✓\u(001b)[0m"

## Red X for failing tests.
red_x : Str
red_x = "\u(001b)[31m✗\u(001b)[0m"
