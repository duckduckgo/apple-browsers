# On-device PIR action generation

A Debug-only Foundation Models proof of concept: read a broker recipe, runner position,
and the current page DOM; propose one PIR action that can continue or repair the flow.
The standalone inspector is a dry run. The opt-in recovery toggle in the real PIR debug view
executes validated replacement actions on the broker site.

## Recovery in the real PIR debug runner

1. Set up PIR locally so the broker list is populated. If needed, run
   `./scripts/toggle-macos-debug-deployment.sh on`, rebuild, and complete PIR setup.
2. Open **Debug → Personal Information Removal → Run Personal Information Removal Debug Mode**
   (**Control–Option–Command–R**). Enable **Recover failed actions with on-device model**.
   The checkbox is off by default and applies to both scan and opt-out runs from this window.
3. Select a broker and enter the profile to scan. First run the unmodified recipe to establish
   that the broker and your test data work.
4. In the debug view's JSON editor, change only the selector in a single-element native-button
   `click` action, e.g. change `elements[0].selector` to `#intentionally-missing-button`.
   Keep the action ID, element type, and all later extraction/expectation steps intact.
   Edit a local copy in this view; do not change the shared broker database.
5. Run the scan, or select an extracted profile and run its opt-out with the edited recipe.
   The existing retry runs first. An action timeout currently takes up to 60 seconds per attempt.
   Then look for **[PIR Recovery]** rows in the event log. Select their details to see the
   model proposal, validation result, replacement JSON, and whether the replacement succeeded.
6. The generator returns one ordinary PIR `Action`. The runner replaces the failed action in
   memory and executes it through its existing `runNextAction` path. `replacement-executed`
   means the interaction ran; following authored actions establish progress, and the original
   extraction/confirmation logic decides whether the scan or opt-out succeeded.

The runner supplies the actual action cursor, dynamically inserted actions, and available binding
names. It captures its own live web view, not the browser's selected tab. One recovery invocation
is allowed per job, with at most two model proposals if the first fails structural validation.
The generated replacement executes once. A failure, unsupported proposal, unavailable model,
changed document, cancellation, or exhausted job timeout falls back to normal failure handling.
The checkbox does not affect scheduled/background jobs or non-Debug builds.

This first integration repairs target selectors for **single-element click or fillForm actions**.
Fills must preserve the original supported binding (first/last name, fetched email, or profile URL);
multi-field fills, extraction schemas, navigation, CAPTCHA, and email verification are not repaired.
Already valid populated fields are not overwritten. Authored action options are retained, and the
page/target is validated when generation finishes. Execution uses PIR's normal delays and failure handling. The repaired
JSON is used only in memory; the input broker recipe remains unchanged.

For live recovery, the model receives the failed action, the preceding action, and the next two
authored actions, with an explicit objective derived from the next form when applicable. DOM
evidence includes control labels, bounded surrounding text, and page landmarks, with editable
values omitted. Footer and navigation controls are excluded for opening the next authored form;
if that is where a site's legitimate entry control lives, this prototype declines recovery.
There is no separate execution or outcome-checking layer. `webViewForInspection` exposes the
runner's existing web view for DOM capture; it does not create another browser or run actions.

Filter Xcode's console for `[PIR Recovery]` to see lifecycle phases, or `[PageAnalysis]` for inference
phases and token counts. Page-derived details are private in system logs; full details remain in the
existing local debug event view. Keep configured job timeouts in mind when choosing a broker with
many slow actions. No request is made to an external model service.

## Standalone dry-run demo

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
Selectors prefer unique IDs, attributes, and classes, then a short ancestor scope. Positional
paths are a fallback and stop as soon as they uniquely identify the selected node. Code checks
the selector against the live node and, for form controls, its form scope before returning it.
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
The standalone fixture uses simulated progress. The opt-in debug runner integration described
above uses actual execution outcomes and recovery limits; it is not enabled in production.

## Implementation and limits

- `PageAnalysisDebugMenu.swift`: bundled-demo loading, input/output UI, and cancellation.
- `PageAnalysisPIRRecovery.swift`: shared context budgeting, model calls, bounded proposal retry,
  live target revalidation, and the real-runner adapter.
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

The standalone inspector still uses manually supplied history. The live debug runner uses actual
runtime state and injects the app's generator through `DebugPIRRecoverySession` in Core.
`PageAnalysisPIRRecovery.swift` owns the shared generator and its live-runner adapter. Production
reliability, broader action support, and broker-specific semantic validation remain future work.
