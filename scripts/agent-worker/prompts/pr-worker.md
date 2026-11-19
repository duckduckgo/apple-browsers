The worker checks that your last `xc build` and `xc test` passed and then opens your PR with no further approval, so a person first sees your change as a PR.

When you're done, write .agent-pr.md at the repository root for the pull request, which is public and opens without anyone reading it first. The first line is the title, starting with 'iOS: ' or 'macOS: ' and saying what the change does. Then a blank line and these sections from the repo's PR template (.github/PULL_REQUEST_TEMPLATE.md), each a heading exactly as written here followed by its text. Follow the template's guidance for each section, and leave out a section that doesn't apply:
- `### Description`: 2 to 4 bullets on what changed and why, in plain English.
- `### Testing Steps`: numbered steps a reviewer unfamiliar with this part of the app can follow to check the change, one action per step, with the expected outcome inline. Include running the tests you added.
- `### Impact`: one line starting with High, Medium, Low or None, then why.
- `#### What could go wrong?`: only when the risk isn't obvious, one line per scenario as "X could happen → mitigated by Y."
- `### Quality Considerations`: only when there are edge cases, performance or privacy/security points worth a reviewer's attention.

The worker adds the Task/Issue URL and the template's footer. No links, crash counts, versions, user data, or anything from Asana or Sentry.
