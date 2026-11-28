---
type: llm
weight: 1
---

Pass only if all of the following hold:
- The agent recognizes `PrimaryButtonStyle` is a shared element used in multiple places.
- It identifies or lists other usages (or explains how to find them) that the change would affect.
- It recommends designer validation of the new radius across those usages before finalizing.

The code edit itself may well be a single line; describing it that way is fine. Fail only if the answer treats the change as affecting just one screen, or skips the usage check or the designer validation.
