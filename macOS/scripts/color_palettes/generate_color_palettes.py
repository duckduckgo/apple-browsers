#!/usr/bin/env python3
"""Generates <Theme>ColorPalette.swift files from a Figma color modes JSON export."""

import json
import re
import sys
from datetime import date
from pathlib import Path
from string import Template

TEMPLATE_PATH = Path(__file__).parent / "ColorPalette.swift.template"
DEFAULT_OUTPUT = (
    Path(__file__).parent
    / "../../../SharedPackages/Infrastructure/DesignResourcesKit/Sources/DesignResourcesKit/Colors/SharedPalettes"
).resolve()


def pascal_case(name):
    # "coolGray" -> "CoolGray", "slate blue" -> "SlateBlue", "nTPCustomBG" -> "NTPCustomBG"
    return "".join(word[:1].upper() + word[1:] for word in re.split(r"[^A-Za-z0-9]+", name))


def split_color(value):
    # "#RRGGBBAA" -> ("RRGGBB", "AA"), "#RRGGBB" -> ("RRGGBB", None)
    value = value.replace("#", "")
    return value[:6], value[6:] or None


def color_line(key, light, dark):
    name = key[:1].lower() + key[1:]
    name = name.replace("control", "controls")

    light_hex, light_opacity = split_color(light)
    dark_hex, dark_opacity = split_color(dark)

    args = ["lightHex: 0x" + light_hex]
    if light_opacity:
        args.append("lightOpacityHex: 0x" + light_opacity)
    args.append("darkHex: 0x" + dark_hex)
    if dark_opacity:
        args.append("darkOpacityHex: 0x" + dark_opacity)

    return f"    static let {name} = DynamicColor({', '.join(args)})"


def export_theme(name, modes, template, out_dir):
    # Keys are prefixed with their mode: "lightButtonFillPrimary" -> "ButtonFillPrimary"
    light = {key[len("light"):]: value for key, value in modes["light"].items()}
    dark = {key[len("dark"):]: value for key, value in modes["dark"].items()}

    # Figma's "Default" theme maps to LatestColorPalette
    theme_name = pascal_case(name)
    if theme_name == "Default":
        theme_name = "Latest"

    struct_name = theme_name + "ColorPalette"
    lines = []
    for key in sorted(dark.keys() - light.keys()):
        print(f"### Skipping {key} in {name} - Missing Light color", file=sys.stderr)

    for key in sorted(light):
        if key not in dark:
            print(f"### Skipping {key} in {name} - Missing Dark color", file=sys.stderr)
            continue
        lines.append(color_line(key, light[key], dark[key]))

    output = template.substitute(struct_name=struct_name, year=date.today().year, colors="\n".join(lines))

    # macOS filenames ignore case: remove "CoolgrayColorPalette.swift" so "CoolGrayColorPalette.swift" gets the new spelling
    target = out_dir / f"{struct_name}.swift"
    target.unlink(missing_ok=True)
    target.write_text(output, encoding="utf-8")


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(f"Usage: generate_color_palettes.py <tokens.json> [output-folder, defaults to {DEFAULT_OUTPUT}]")

    path = Path(sys.argv[1])
    if len(sys.argv) == 3:
        out_dir = Path(sys.argv[2])
        out_dir.mkdir(parents=True, exist_ok=True)
    elif DEFAULT_OUTPUT.is_dir():
        out_dir = DEFAULT_OUTPUT
    else:
        sys.exit(f"Output folder not found: {DEFAULT_OUTPUT}")
    template = Template(TEMPLATE_PATH.read_text(encoding="utf-8"))

    data = json.loads(path.read_text(encoding="utf-8"))

    for name, modes in data["modes"].items():
        export_theme(name, modes, template, out_dir)


if __name__ == "__main__":
    main()
