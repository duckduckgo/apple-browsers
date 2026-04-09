# Tech Design: NTP Omnibar — Image Generation Mode

**Author:** Alex Lavrenchuk
**Reviewer:** Shane Osbourne
**Stakeholders:** Tom Strba, Andrew, Juan Pereira
**Project:** [Frontend: Provide quick access to image generation](https://app.asana.com/1/137249556945/project/1213083312441631/task/1213493651880757?focus=true)

## Background & Requirements

Duck.ai supports image generation via `mode: "image-generation"` in the native prompt handoff ([already deployed](https://app.asana.com/1/137249556945/project/1213083312441631/task/1213833201148521?focus=true), works from the address bar). The NTP omnibar has AI chat submission (`omnibar_submitChat`) with model selection and image attachments, but no way to indicate which Duck.ai mode to open.

## Problem Statement

Add a "Create Image" toggle to the NTP omnibar and pass the selected mode to native via the existing `omnibar_submitChat` notification.

## Recommended Approach

One modified notification, one new config field. No new messages needed.

```
    JS (NTP)                                 Native
    │                                           │
    │  omnibar_getConfig (existing)             │
    ├──────────────────────────────────────────►│
    │◄──────────────────────────────────────────┤
    │  { ..., enableImageGeneration: true }     │
    │                                           │
    │  omnibar_submitChat (modified)            │
    │  { chat, target, mode?, ... }             │
    ├──────────────────────────────────────────►│
    │                                           │  Forward mode to Duck.ai
```

### Schema changes

**`omnibar_submitChat`** — add optional `mode` property:

```jsonc
"mode": {
  "description": "Duck.ai mode. If omitted, defaults to 'chat'.",
  "type": "string",
  "enum": ["chat", "image-generation"]
}
```

- Optional → fully backward-compatible
- Frontend omits `modelId` in image generation mode (Duck.ai ignores it)[1]
- Existing `images` field reused for reference images

**`OmnibarConfig`** — add `enableImageGeneration` flag:

```jsonc
"enableImageGeneration": {
  "description": "Show 'Create Image' toggle.",
  "type": "boolean",
  "default": false
}
```

### Native

1. Add `enableImageGeneration: true` to `omnibar_getConfig` response when feature is enabled.
2. Read the optional `mode` field from `omnibar_submitChat` and forward to Duck.ai — same mechanism as the address bar.

### Frontend

"Create Image" toggle button in the AI chat toolbar. When active: visual detent indicator, model selector hides, placeholder changes to "Describe the image you want to create", recent chats list hides.

Image generation mode is transient local state — resets on submit and when switching to search mode[2].

## Notes

[1] Native should not break if `modelId` is present alongside `mode: "image-generation"`.

[2] Not persisted to config — it's a per-interaction toggle, matching address bar behavior.

## Testing

| Scenario                          | Expected                                            |
| --------------------------------- | --------------------------------------------------- |
| Flags enabled                     | "Create Image" button visible                       |
| Flags absent/false                | No button, unchanged behavior                       |
| Toggle on → submit                | `mode: "image-generation"` in payload, no `modelId` |
| Toggle off → submit               | No `mode`, `modelId` included                       |
| Toggle on → attach image → submit | Both `mode` and `images` in payload                 |
| After submit                      | Toggle resets to off                                |

Mock transport: `?omnibar.enableImageGeneration=true`

---

## Update: Web Search Tool Support

Same pattern as image generation — one config flag, one new field.

1. **`OmnibarConfig`** — add `enableWebSearch: boolean` (default `false`). Controls visibility of the web search option.

2. **`omnibar_submitChat`** — add optional `toolChoice: string[]` (enum: `["WebSearch"]`). Array type to allow future tool additions without schema changes.

Native reads `toolChoice` from the notification and forwards to Duck.ai. Mock transport: `?omnibar.enableWebSearch=true`
