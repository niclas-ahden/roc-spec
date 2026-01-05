app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.25.0/2Qj7ggHJdVV9jAspIjvskp_cUWvAyh7B9I-Ma_sY4zk.tar.br",
}

import pf.Stdout

main! = |_args|
    # Output a marker at the start
    Stdout.line!("START_MARKER")?

    # Output ~10KB of text (100 lines of 100 chars each)
    output_lines!(100)?

    # Output a marker at the end
    Stdout.line!("END_MARKER")

output_lines! = |remaining|
    if remaining == 0 then
        Ok({})
    else
        # 100 character line
        Stdout.line!("LINE_$(Num.to_str(remaining))_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")?
        output_lines!(remaining - 1)
