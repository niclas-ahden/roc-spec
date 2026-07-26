## Formatting utilities for test output display.
Format :: [].{

	## Format duration in human-readable form.
	## < 1000ms: "Nms"
	## >= 1000ms: "N.Ns"
	format_duration : U64 -> Str
	format_duration = |ms|
		if ms < 1000 {
			"${ms.to_str()}ms"
		} else {
			seconds = ms.to_f64() / 1000.0
			"${seconds.to_str()}s"
		}

	## Indent each line with "    | " prefix for test output display.
	indent_lines : Str -> Str
	indent_lines = |str|
		str
			.split_on("\n")
			.map(|line| "    | ${line}")
			->Str.join_with("\n")

	## Green checkmark for passing tests.
	green_check : Str
	green_check = "\u(001b)[32m✓\u(001b)[0m"

	## Red X for failing tests.
	red_x : Str
	red_x = "\u(001b)[31m✗\u(001b)[0m"
}

expect Format.format_duration(0) == "0ms"
expect Format.format_duration(500) == "500ms"
expect Format.format_duration(999) == "999ms"
expect Format.format_duration(1000) == "1s"
expect Format.format_duration(1500) == "1.5s"
expect Format.format_duration(2500) == "2.5s"

expect Format.indent_lines("hello") == "    | hello"
expect Format.indent_lines("line1\nline2") == "    | line1\n    | line2"
expect Format.indent_lines("") == "    | "
