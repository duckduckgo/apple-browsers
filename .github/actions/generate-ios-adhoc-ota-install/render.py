#!/usr/bin/env python3
"""
Render a template file with $VAR / ${VAR} placeholders, substituting from the
current process environment.

Usage:
  render.py <template-path> <output-path>

Uses string.Template.safe_substitute, so any placeholder that isn't present in
the environment is left in the output verbatim (no error). If you need a
literal "$" in the rendered file, write "$$" in the template.
"""
import os
import sys
from string import Template


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <template> <output>", file=sys.stderr)
        return 1

    template_path, output_path = sys.argv[1], sys.argv[2]

    with open(template_path, "r", encoding="utf-8") as f:
        template = Template(f.read())

    rendered = template.safe_substitute(os.environ)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(rendered)

    return 0


if __name__ == "__main__":
    sys.exit(main())
