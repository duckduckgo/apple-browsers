# On-device PIR action generation

A Debug-only Foundation Models proof of concept: read a broker recipe, runner position,
and the current page DOM; propose one PIR action that can continue or repair the flow.
It generates JSON only and does not execute actions or make removal requests.

## Demo

1. Check out `sam/pir-foundation-model-demo`, open `DuckDuckGo.xcworkspace` in Xcode 27,
   and run the **macOS Browser** scheme in Debug on macOS 27. Enable Apple Intelligence
   and let its on-device model finish downloading before generating.
2. Choose **Debug → On-Device Page Analysis → Open PIR Recovery Demo…**
   (or press **Control–Option–Command–Shift–P**).
   This opens the bundled local page in a new tab and the inspector with matching
   **Broker JSON** and **Runner state**. No server, file picker, or copy/paste is needed.
3. Once the page loads, click **Generate next action**.
4. Expect a `click` action targeting the current **Remove this listing** button. Use **Copy** to copy that action alone.

Choose **Open PIR Recovery Demo…** again to start fresh; it resets the inspector inputs
and opens a fresh copy of the page. For other tabs, use **Analyze Current Tab…** or
**Control–Option–Command–P** and supply the corresponding recipe and runner state.

The HTML and both JSON files in [the demo resources](../DuckDuckGo/Resources/PageAnalysisPrototype) ship with the app. The inspector reads
these JSON files directly, so the checked-in examples and preloaded inputs stay identical.
The menu and generator are Debug-only; this branch is a prototype for local testing.

The page is a simplified Spokeo-style opt-out form. Both fields are populated,
verification is locally simulated as complete, and the submit button works. The broker
recipe has completed navigation, two fills, and the two simulated verification actions.
Its next action, `submit-removal`, still refers to `#remove-listing`. That ID no longer exists;
the current button uses `.responsive-button`. The defect is in the recipe, not the site.

The model chooses the appropriate captured control; code derives a selector from its live
DOM node and emits a normal PIR action. The input does not contain the replacement selector.
Manual submission reaches a local confirmation-email page and sends nothing. Reload before
repeating the demo. This is an independent reconstruction from the checked-in Spokeo recipe,
not a live site or a saved copy of it. All field values are fictional.

- [pir-demo-broker.json](../DuckDuckGo/Resources/PageAnalysisPrototype/pir-demo-broker.json): recipe containing the stale click.
- [pir-demo-progress.json](../DuckDuckGo/Resources/PageAnalysisPrototype/pir-demo-progress.json): five completed actions, then the failed click.
- **Page DOM**: captured evidence with input values omitted.
- **Diagnostics**: proposal attempts, validation results, and the exact model instructions and latest request.

## Input and output

The first input accepts an unchanged PIR broker with a `steps` array, or a single step with
`stepType` and `actions`. The selected step is decoded using `DataBrokerProtectionCore.Step`.
The second input supplies runner state separately from the broker format:

```json
{
  "stepIndex": 0,
  "completedActionCount": 5,
  "failedActionID": "submit-removal",
  "availableData": ["fetchedEmail.email", "extractedProfile.profileUrl"]
}
```

`stepIndex` is zero-based; use 0 for a single step. `completedActionCount` counts successful
actions at the beginning of the sequence. Optional `failedActionID` identifies the next
unsuccessful action and prevents replaying it unchanged. To request an additional action
from a partial recipe, supply its completed prefix and omit `failedActionID`.
`availableData` contains binding names, never personal values. The model receives the selected
step and cursor, not the broker's scheduling metadata or unselected steps.

The generator can produce a `fillForm` for first/last name, fetched email, or extracted listing
URL, or a native-button `click`. It can also select the exact next configured action, preserving
all authored fields, including existing extraction or email-confirmation settings. It cannot
invent new extraction schemas or verification logic; `wait` and `unsupported` return no action.
Diagnostic status/reason/validation fields are separate from the emitted PIR action JSON.

## What the model does

The pipeline is: **PIR recipe + runner position + page capture → eligible actions → model intent
→ live validation → one PIR action JSON**.

Code enumerates supported fills and clicks from the current DOM. The Foundation Model chooses
an intent and explains it using the sequence and page evidence. Code then resolves the original
DOM node, derives its selector, and validates the resulting action with PIR's existing decoder.
The prompt contains no Spokeo-specific rules or expected answer. Open **Diagnostics** to inspect
what was sent and why a proposal passed or failed validation.

This fixture deliberately has one eligible click. It demonstrates the generation and validation
path for a stale selector; it does not establish reliability across brokers or ambiguous pages.
The input recipe and runner position are simulated. Production integration would need real
execution outcomes, recovery limits, and PIR's existing completion checks.

## Implementation and limits

- `PageAnalysisDebugMenu.swift`: bundled-demo loading, input/output UI, cancellation, context
  budgeting, model calls, and one optional retry after structural rejection.
- `PageAnalysisSnapshot.swift`: bounded main-document capture and live selector validation.
- `PageAnalysisPIRAction.swift`: the generated intent schema, model instructions and request,
  runner-context parsing, candidate validation, and PIR Step serialization.

Requires Xcode 27 / Swift 6.4 and macOS 27 with the on-device model available. Older compilers,
older macOS releases, and non-Debug builds do not expose the prototype.

Capture omits field values and does not inspect iframe or shadow-root contents. Page labels
may still contain personal data. Generated fills/clicks must reference eligible controls;
code checks disabled/invalid/populated state, live node identity, form scope, unique selectors,
and document identity. Prompt size is bounded by token counting and DOM trimming. Generation
uses the on-device model's normal guardrails and has no network fallback.

The caller supplies the execution history; the inspector is not connected to PIR's runner.
A usable action JSON object does not establish execution, progress, or opt-out success.
Runner integration and production reliability remain future work. Logs include phase/timing
and token counts, not raw page text or model output; filter Xcode for `[PageAnalysis]`.
