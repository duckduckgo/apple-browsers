Remove the `$flag` feature flag from the $platform app.

- **Decision:** the flag was $decision. Keep the code path that runs when the flag is $kept_path, and delete the other one.
- **How:** read `.claude/skills/ddg-remove-feature-flag/SKILL.md` and follow every step.
- **Scope:** change only what removing this flag requires. Don't refactor or fix unrelated code.
- **Done:** `$flag` no longer appears in the $platform code and tests, every platform you touched builds, and the tests you changed pass.
