#!/usr/bin/env python3
"""
Render a template file with $VAR / ${VAR} placeholders, substituting from the
variables passed as explicit KEY=VALUE arguments.

Usage:
  render.py <template-path> <output-path> [KEY=VALUE ...]

Uses string.Template.substitute, so any placeholder that isn't present in the
provided variables fails the render. If you need a literal "$" in the template,
write "$$".
"""
import sys
from string import Template


def parse_variables(raw_variables):
    variables = {}
    for raw_variable in raw_variables:
        name, separator, value = raw_variable.partition("=")
        if not separator or not name:
            raise ValueError(f"expected KEY=VALUE argument, got {raw_variable!r}")
        variables[name] = value
    return variables


def main() -> int:
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <template> <output> [KEY=VALUE ...]", file=sys.stderr)
        return 1

    template_path, output_path = sys.argv[1], sys.argv[2]

    with open(template_path, "r", encoding="utf-8") as f:
        template = Template(f.read())

    try:
        rendered = template.substitute(parse_variables(sys.argv[3:]))
    except KeyError as e:
        print(f"missing template variable: {e.args[0]}", file=sys.stderr)
        return 1
    except ValueError as e:
        print(f"render error: {e}", file=sys.stderr)
        return 1

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(rendered)

    return 0


if __name__ == "__main__":
    sys.exit(main())
