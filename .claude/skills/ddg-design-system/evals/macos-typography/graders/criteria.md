---
type: llm
weight: 1
---

Pass only if all of the following hold:
- The agent states that the DesignResourcesKit `dax...` typography modifiers are iOS only (UIKit) and are not available on macOS.
- The code does not call `.daxTitle1()` or another `dax...` modifier in macOS code.
- The agent recommends following the existing typography conventions of nearby macOS Settings views instead, ideally pointing at or describing them.
