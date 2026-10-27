# Release translations checks

Two scripts check the translations that the **Smartling - Release Import** workflow brings into a release branch:

| Script | Runs | Compares | Outcome |
| --- | --- | --- | --- |
| [`check_translation_integrity.py`](check_translation_integrity.py) | In `smartling_release_import.sh`, before the pull request is opened | The downloaded files with the release branch | One pass/fail line in the pull request description |
| [`check_release_translations.py`](check_release_translations.py) | In [`smartling_release_translations_check.yml`](../../.github/workflows/smartling_release_translations_check.yml), on every push to a `smartling/release-*` pull request into `release/**` | Each translation the pull request changes with the release branch's English | A pull request comment with a verdict, an Asana comment when the verdict changes, and a failed run when something needs a fix |

## `check_release_translations.py`

### Verdict

| Verdict | When | What the release DRI does |
| --- | --- | --- |
| ✅ `ready` | No findings | Merge once the required checks are green |
| ⚠️ `warning` | Only warnings | Check each warning, then merge |
| ❌ `fix` | At least one finding needs a fix | Don't merge. Fix it in Smartling and run the import again with **reimport** checked |

### What it asserts

Only non-English values the pull request adds or changes are checked. `en.lproj`, `Base.lproj` and the `en` localization in `.xcstrings` files are skipped.

| Check | Files | Result | Example that fails |
| --- | --- | --- | --- |
| Only localization files change | Any | ❌ Needs a fix | `AppDelegate.swift` in the pull request |
| The file parses | `.strings`, `.stringsdict`, `.xcstrings` | ❌ Needs a fix | `"open.in" = "Öffnen "in" %@";`, a missing `;`, invalid JSON, an empty `.stringsdict` or `.xcstrings`, a property list that isn't a dictionary, a catalog without a `strings` dictionary |
| The file wasn't deleted | `.strings`, `.stringsdict`, `.xcstrings` | ❌ Needs a fix | `de.lproj/Localizable.strings` removed |
| No format specifier is missing | All | ❌ Needs a fix | `Open in %@` → `Öffnen in`, or `Von % @` |
| No format specifier is extra | All | ❌ Needs a fix | `and %@` → `%@ und %@` |
| Each argument keeps its type | All | ❌ Needs a fix | `%@ item` → `%d Element` (types: integer, decimal, object, C string, pointer) |
| Plural variables match English | `.stringsdict`, `.xcstrings` | ❌ Needs a fix | `%#@items@` → `1$#@items@` (missing) or `%#@sites@` (unknown) |
| The plural value type matches English | `.stringsdict` | ❌ Needs a fix | `NSStringFormatValueTypeKey` `d` → `@` |
| Bold `**` markers match English | All | ⚠️ Warning | `Get **more** today` → `Hol dir heute mehr` |
| The translation isn't empty | All | ⚠️ Warning | `Close` → `` |
| The translation wasn't removed | All | ⚠️ Warning | `open.in` deleted from `de.lproj` while English still has it |
| The translation wasn't replaced by English | All | ⚠️ Warning | `Optionale Cookies ablehnen` → `Reject optional cookies` |
| The translation didn't shrink by more than half | All | ⚠️ Warning | `Cookie-Pop-ups automatisch verwalten` → `Cookies` |
| The English file parses | `.strings`, `.stringsdict` | ⚠️ Warning, and the file isn't checked | A malformed `en.lproj/Localizable.strings` |

### How the comparisons work

- **English:** `.strings` and `.stringsdict` files use `en.lproj`, or `Base.lproj` when there's no `en.lproj`. `.xcstrings` files use the `en` localization, or the key when there isn't one.
- **Specifier positions:** positional specifiers (`%2$@`) keep their position. Unnumbered ones are numbered in order. `%%` is text.
- **Plural variants:** each variant is compared with every English variant of the same plural. A translated variant may leave out a specifier, such as `Eine Website` for `%d sites`, since languages word their plural categories differently.
- **English without specifiers:** this English is never formatted, so a `%` in the translation is just text: `25%` → `25 %` passes.
- **Replaced by English:** flagged only when the previous translation differed from English and the text has at least three words. Short strings such as `Tab` often stay the same.
- **Removed translations:** flagged only when English still has the key. A key deleted from English too is an expected cleanup.

### Release DRI notifications

The pull request comment starts with `<!-- smartling-release-translations-check verdict=… notified=… -->`. Each push updates the same comment. The workflow comments on the Translations subtask linked in the pull request's `Task/Issue URL` whenever the verdict differs from the last one posted there, and records the new verdict only once Asana accepts the comment. A failed Asana post is therefore retried on the next run.

## `check_translation_integrity.py`

| Check | Result |
| --- | --- |
| No key was deleted | Fails the integrity check |
| No value became empty | Fails the integrity check |
| No value shrank by more than half | Fails the integrity check |

A failed integrity check doesn't stop the import. The pull request description says `Integrity check: ⚠️ found deleted or much shorter translations` instead of `passed`.

## Running the tests

```bash
python3 -m unittest discover -s scripts/smartling/tests
```

`test_localization_tool` needs `aiohttp` (`pip install aiohttp`).
