---
type: llm
weight: 1
---

Pass only if all of the following hold:
- The text color uses a DesignResourcesKit semantic color, for example `UIColor(designSystemColor: .textSecondary)`.
- The Swift code does not use `UIColor.gray`, `.secondaryLabel`, `UIColor(baseColor:)`, hex or RGB literals, or a new asset-catalog color.
- The font uses DesignResourcesKit typography (a `UIFont.dax...()` style) rather than `UIFont.systemFont(ofSize:)`.

Judge the Swift code only. Naming these APIs in the explanation as things to avoid is fine and must not fail the answer. Do not fail the answer because the agent could not verify the API names against the repository.
