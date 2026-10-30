# Translations

The iOS and macOS apps are translated in Smartling. Strings reach Smartling without anyone having to send them, and each
release imports all of its translations in one pull request.

## How it works

1. **Merge to `main` in English only.** The "Translated Strings" check still reports untranslated strings on pull
   requests into `main`, as a warning that doesn't block the merge.
2. **Nightly job** (`smartling_nightly.yml`): every night, new strings on `main` are sent to Smartling. Jobs under the
   cost cap are authorized automatically; above it, a review task is opened for the maintenance DRI. Nothing is
   committed to `main`.
3. **Code freeze** (`smartling_submit.yml`): the release branch is submitted as the Smartling job
   `Release <platform> <version>`.
4. **Release import** (`smartling_release_import.yml`): once that job is complete, a pull request with the translations
   is opened into the release branch. If the translations still aren't ready on the Wednesday of code freeze week, a
   task is opened for the release DRI.

Builds from `main` show English for new strings until the next release import.

## Release and hotfix branches

Nothing above covers changes merged into `release/<platform>/*` or `hotfix/<platform>/*` after code freeze. Pull
requests into those branches must include their translations, and the "Translated Strings" check fails until they do.
Translate them with the labels:

1. Add `start ios translation` or `start macos translation` to create a Smartling job for the pull request's branch.
2. Add `authorize translation` to authorize it.
3. Once Smartling is done (`check translation status` tells you), add `download translations` to commit the
   translations to the branch.

The labels also work on pull requests into `main`, if you need translations there sooner.

## FAQ

**Do I still need to translate my pull request before merging to `main`?**
No. Merge in English. The nightly job sends your strings to Smartling, and they ship translated with the next release.

**When will a string I merge today be translated?**
It goes to Smartling that night. Its translations are imported after the next code freeze, so they show up in an
internal build during code freeze week, and at the latest in the release build.

**My feature is behind a feature flag. Anything to watch out for?**
Strings merged before a release's code freeze ship translated in that release; strings merged after it ship in the
next one, so plan the flag change for that release. To keep strings out of Smartling for now (for example, while the
feature is internal only), use `NotLocalizedString`. Those strings aren't sent.

**I found a bad translation. Can I fix it in the repo?**
Fix it in Smartling. The next release import overwrites edits made only in the repo.
