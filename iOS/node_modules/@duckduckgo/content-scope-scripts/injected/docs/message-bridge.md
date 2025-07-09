---
title: Message Bridge
---

## Description

Message Bridge creates a communication between a website and a browser. It sends and receives messages that conform
to our Messaging standard (eg: it's not a new format!)

- Related Privacy Configuration [feature file](https://github.com/duckduckgo/privacy-configuration/blob/main/features/message-bridge.json)
- Message formats: {@link "Messaging Schema"}

## Integration guide

## Step 1: add `messageSecret` to `$USER_PREFERENCES$`

This feature requires the following to be serialized into `$USER_PREFERENCES$`.

- `"messageSecret": "<some uuid>"`

Without this, the bridge will refuse to be installed.

Example:

```json
{
    "...": "...",
    "messageSecret": ""
}
```

## Step 2: Enable in remote config

Using the method of your choice, generate a remote config file that has the bridge feature
enabled + some feature & domain combinations.

For example, to enable `aiChat` on `duckduckgo.com` domains - you would place the following override
in the relevant platform file. This is how the per-domain restrictions are enforced in the JavaScript layer.

```json
{
    "features": {
        "...": "...",
        "messageBridge": {
            "state": "enabled",
            "settings": {
                "aiChat": "disabled",
                "domains": [
                    {
                        "domain": "duckduckgo.com",
                        "patchSettings": [
                            {
                                "op": "replace",
                                "path": "/aiChat",
                                "value": "enabled"
                            }
                        ]
                    }
                ]
            }
        }
    }
}
```

**NOTE:** Native platforms should continue to verify the sending domain when any messages are received.

## Example

In a domain where the bridge is enabled, the following API becomes available to the page.

```javascript
const bridge = navigator.duckduckgo?.createMessageBridge?.('exampleFeature');
bridge.notify('pixel');
```

That `notify` ^ call will result in a {@link "Messaging Schema".NotificationMessage "NotificationMessage"} being sent
to the 'native' layer.

```json
{
    "context": "contentScopeScriptsIsolated",
    "featureName": "exampleFeature",
    "method": "pixel"
}
```

Likewise with `Requests` and `Subscriptions` - as far as the 'native' side is concerned, they are handled with the same
Messaging Schema types.
