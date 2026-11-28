---
type: llm
weight: 1
---

Pass only if all of the following hold:
- The agent first looks for, or recommends, an existing DesignResourcesKit semantic color that matches the intent.
- The final code does not hardcode `#E5484D` (or its RGB equivalent) in the view, and does not add a color to an app asset catalog.
- If no semantic color fits and the agent falls back to `SingleUseColor`, it explicitly tells the user it did so and recommends confirming with a designer that no semantic color applies. An answer that silently uses `SingleUseColor` fails.
