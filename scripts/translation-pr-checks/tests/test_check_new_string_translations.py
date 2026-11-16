#!/usr/bin/env python3

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location(
    'check_new_string_translations', SCRIPTS_DIR / 'check_new_string_translations.py'
)
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class RequiresTranslationsTests(unittest.TestCase):

    def test_release_and_hotfix_branches_of_the_platform_require_translations(self):
        bases = [
            ('iOS', 'release/ios/7.245.0'),
            ('iOS', 'hotfix/ios/7.244.1'),
            ('macOS', 'release/macos/1.215.0'),
            ('macOS', 'hotfix/macos/1.214.1'),
        ]

        results = [CHECK.requires_translations(platform, base) for platform, base in bases]

        self.assertEqual(results, [True] * len(bases))

    def test_other_bases_only_warn(self):
        bases = [
            ('iOS', 'main'),
            ('iOS', 'andremartingo/feature-a'),
            ('iOS', 'release/macos/1.215.0'),
            ('macOS', 'hotfix/htang/duckai-fire-onboarding-loop'),
            ('macOS', 'releases/macos/1.215.0'),
            ('macOS', ''),
        ]

        results = [CHECK.requires_translations(platform, base) for platform, base in bases]

        self.assertEqual(results, [False] * len(bases))


if __name__ == '__main__':
    unittest.main()
