#!/usr/bin/env python3
"""Print the plural forms Smartling returned for each locale of the plural test String Catalog."""
import json
import sys
from pathlib import Path

CLDR_FORMS = {
    'pl': {'one', 'few', 'many', 'other'},
    'ru': {'one', 'few', 'many', 'other'},
    'cs': {'one', 'few', 'many', 'other'},
    'hr': {'one', 'few', 'other'},
    'sk': {'one', 'few', 'many', 'other'},
    'lt': {'one', 'few', 'many', 'other'},
    'lv': {'zero', 'one', 'other'},
    'ro': {'one', 'few', 'other'},
    'sl': {'one', 'two', 'few', 'other'},
}


def main(download_dir: str) -> None:
    print('## Smartling String Catalog plural test\n')
    for path in sorted(Path(download_dir).glob('PluralTest_*.xcstrings')):
        locale = path.stem.split('_', 1)[1]
        catalog = json.loads(path.read_text())
        print(f'### {locale}\n')
        print(f'CATALOG {locale} {json.dumps(catalog, ensure_ascii=False, separators=(",", ":"))}')
        for key, entry in catalog.get('strings', {}).items():
            for catalog_locale, localization in entry.get('localizations', {}).items():
                if catalog_locale == catalog.get('sourceLanguage', 'en'):
                    continue
                plural = localization.get('variations', {}).get('plural')
                if plural is None:
                    value = localization.get('stringUnit', {}).get('value')
                    print(f'- `{key}` ({catalog_locale}): no plural variations, value `{value}`')
                    continue
                forms = {form: unit.get('stringUnit', {}).get('value') for form, unit in plural.items()}
                expected = CLDR_FORMS.get(catalog_locale.split('-')[0], {'one', 'other'})
                missing = sorted(expected - set(forms))
                verdict = 'OK' if not missing else f'MISSING {", ".join(missing)}'
                print(f'- `{key}` ({catalog_locale}) {verdict}: {json.dumps(forms, ensure_ascii=False)}')
        print()


if __name__ == '__main__':
    main(sys.argv[1])
