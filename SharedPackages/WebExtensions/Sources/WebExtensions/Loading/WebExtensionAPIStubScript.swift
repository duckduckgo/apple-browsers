//
//  WebExtensionAPIStubScript.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// JavaScript injected at document start into every page an extension owns, ahead of the
/// extension's own scripts (see the user script `WebExtensionManager` installs).
///
/// WebKit implements a subset of the `chrome.*` extension API. In a background page these
/// namespaces are undefined even when the matching permission is declared *and* granted:
/// `notifications`, `offscreen`, `downloads`, `idle`, `management`, `privacy`, `browsingData`,
/// `topSites`, `sidePanel`. Sub-namespaces and events on namespaces that *do* exist can be
/// missing too — `storage.managed` and `webNavigation.onCreatedNavigationTarget`, for instance.
///
/// Chrome builds routinely touch those APIs at the top level of their background script — the
/// Bitwarden extension calls `chrome.notifications.onClicked.addListener(...)` while wiring up its
/// listeners — and a missing namespace makes that a `TypeError` on the very first statement, which
/// aborts the whole startup: no listeners are registered and the extension never initializes.
///
/// Defining inert stubs for the missing pieces lets that top-level code run to completion, so the
/// listeners for the APIs WebKit *does* implement get registered and the extension comes up. The
/// stubbed calls themselves do nothing; the feature behind them stays unavailable either way, the
/// difference is whether the rest of the extension works. Most stubs are generic and resolve to
/// `undefined`; where callers read straight off the result — `storage.managed.get()` — the stub is
/// shaped to answer with the empty value Chrome would return.
///
/// `chrome.offscreen` goes one step further and actually works. Bitwarden copies to the clipboard by
/// opening an offscreen document, messaging it and closing it again, so a no-op `createDocument`
/// turns "copy password" into silence. An extension iframe inside the background page is itself an
/// extension page with the full `chrome.*` API, so the offscreen page's `runtime.onMessage`
/// listeners run and messages sent from the background page reach it — the stub therefore creates a
/// hidden iframe pointing at the requested document. Whether a clipboard write from that hidden
/// frame succeeds under WebKit is not measured yet; this turns a silent no-op into a real attempt,
/// and the outcome shows up in the extension's own logs.
///
/// `chrome.permissions` is the mirror image of a missing namespace: WebKit defines it, but it
/// validates permission names against the set it implements and *throws* for every other name —
/// `permissions.contains({permissions: ["privacy"]})` fails with "'privacy' is not a valid
/// permission" where Chrome simply answers `false`. Extensions probe their optional permissions at
/// startup and do not wrap the probe in a try block: Bitwarden's popup calls
/// `permissionsGranted(["privacy"])` during Angular bootstrap, and the throw takes the whole popup
/// down. The script therefore wraps `contains`, `request` and `remove` so they answer the Chrome
/// way — see makePermissionsMethod below — while leaving `getAll` and the events alone.
///
/// `chrome.privacy` is the one missing namespace that has to *answer*, not just exist. Bitwarden's
/// "Make Bitwarden your default password manager" toggle turns off the browser's own password saving
/// and autofill through `privacy.services.passwordSavingEnabled` and its two autofill siblings, and it
/// guards every call with `permissions.contains({permissions: ["privacy"]})`, falling back to
/// `permissions.request` from the click handler. `privacy` is an optional permission in its manifest;
/// WebKit rejects a grant or request for a name it does not implement, so both
/// calls answer `false` and the toggle fails with an error dialog. Since this script is what actually
/// provides `privacy`, the permissions wrappers treat it as a *virtual* permission that is always
/// granted: they strip it from the descriptor before asking the host and answer for the rest. The
/// `privacy.services` settings are then shaped like Chrome's `ChromeSetting` — `get` answers
/// `{value, levelOfControl}` and reports `controlled_by_this_extension` once the extension has set a
/// value — and persisted in `storage.local` under one reserved key, because the popup is a fresh page on
/// every open and re-reads them to draw its checkbox, and the background page reads them too. Nothing
/// in the app reads these values; they record the extension's choice so it reads back consistently.
///
/// `chrome.idle` works too, on macOS. Bitwarden's "lock vault on idle / on system lock" timeouts
/// register `idle.onStateChanged` and set `idle.setDetectionInterval`, and with inert stubs they never
/// fire. The state itself — `locked`, `idle` or `active` — is only known to the app, so `queryState`
/// asks it through a script message with a reply (`idleMessageHandlerName`); `onStateChanged` polls
/// `queryState` while it has listeners and fires them when the answer changes. A page whose host has
/// no such handler always hears `active`. `idle` is a *virtual* permission, like `privacy`, for the
/// same reason: WebKit drops the grant. `getAutoLockDelay` answers `0`, which stands for "unknown".
///
/// Chrome also exposes enum-like constant objects on its namespaces — `scripting.ExecutionWorld`,
/// `tabs.TAB_ID_NONE` and the `windows.WINDOW_ID_*` values — and extension code dereferences them
/// right where it passes them, as call arguments. WebKit implements the calls but not the
/// constants, so the dereference throws before the call is ever made: Bitwarden injects its autofill
/// scripts with `world: chrome.scripting.ExecutionWorld.ISOLATED`, which WebKit would have accepted
/// as the string `"ISOLATED"`, and instead of injecting anything the statement fails with a
/// `TypeError`. Defining the missing constants with Chrome's documented values makes those call
/// sites work as written. The list holds only the constants the supported extensions actually read,
/// rather than everything Chrome documents.
///
/// One behavior of the host is worth calling out, established by measurement on macOS 26.6.2:
/// - `chrome.webNavigation`, `chrome.tabs` and friends are native wrapper objects that WebKit
///   discards once JavaScript stops referencing them, taking any property we added with them: an
///   event stub installed on `chrome.webNavigation` vanished within about half a second. The script
///   therefore parks every object it decorates in a retention array on `globalThis`, which kept the
///   stubs alive for the lifetime of the background page.
///
/// Note that stubs are only installed for names that are actually missing, so a future WebKit that
/// implements one of them wins automatically.
///
/// The script also tells the browser which unsupported APIs an extension touches, for the API
/// compatibility log (see `WebExtensionAPICompatibilityLog`): a call to one of its stubs, a permission
/// the host does not implement, and the errors the page raises or logs (`error`, `unhandledrejection`,
/// `console.error`, `console.warn`), whose text the browser only classifies and never keeps. The
/// reports are plain strings posted to `compatibilityMessageHandlerName`.
public enum WebExtensionAPIStubScript {

    /// Property on `globalThis` holding the objects the script decorated, so WebKit's native
    /// namespace wrappers stay alive along with the stubs installed on them.
    static let retentionPropertyName = "__ddgRetainedExtensionAPINamespaces"

    /// Name of the script message handler `chrome.idle.queryState` asks for the idle state. It is
    /// optional: a page with no handler of this name hears `active`.
    public static let idleMessageHandlerName = "ddgWebExtensionIdle"

    /// Name of the script message handler the page reports unsupported API use to. It is optional:
    /// a page with no handler of this name reports nothing.
    public static let compatibilityMessageHandlerName = "ddgWebExtensionAPICompatibility"

    public static let source = """
    // Generated by DuckDuckGo. Defines inert stubs for chrome.* APIs that WebKit does not
    // implement, so an extension's background script survives touching them at the top level.
    (function() {
        "use strict";

        // Whichever global the host exposes. We deliberately do not alias `chrome` to `browser`
        // (or the other way round) — that is WebKit's call to make, not ours.
        var api = globalThis.chrome || globalThis.browser;
        if (!api) {
            return;
        }

        // The script must leave ordinary web content alone: some websites define their own
        // `window.chrome` object to look like Chrome, and they must not get stubs installed on it,
        // nor the retention array leaked into them. Only extension pages are served over
        // `webkit-extension:`. A bare `JSContext` in tests has no `location`, so an absent
        // `location` still lets the script run.
        try {
            if (globalThis.location !== undefined && typeof globalThis.location.protocol === "string"
                && globalThis.location.protocol !== "webkit-extension:") {
                return;
            }
        } catch (error) {
            // Reading `location` should not throw; if it does, treat the frame as not ours.
            return;
        }

        // Our own extensions (autoconsent, content blocker, Dark Reader, …) declare
        // `browser_specific_settings.duckduckgo` and need no Chrome shims. Keep in sync with
        // `WKWebExtension.needsChromeCompatibility`.
        try {
            var settings = api.runtime && typeof api.runtime.getManifest === "function"
                ? api.runtime.getManifest().browser_specific_settings : undefined;
            if (settings && settings.duckduckgo) {
                return;
            }
        } catch (error) {
            // A page that cannot read its manifest is treated like any other extension page.
        }

        // `Symbol.dispose` and `Symbol.asyncDispose` (explicit resource management, `using`
        // declarations) ship in Chrome but not in this WebKit. TypeScript's `using` helpers throw
        // "Symbol.dispose is not defined." without them, which stops Bitwarden's SDK from unlocking
        // the vault. Defining them here, before any extension code runs, also lets generated code
        // that only attaches `[Symbol.dispose]` methods when the symbol exists do so. Only the
        // symbols are needed: the helpers do the disposing themselves.
        ["dispose", "asyncDispose"].forEach(function(name) {
            try {
                if (typeof Symbol[name] !== "symbol") {
                    Object.defineProperty(Symbol, name, {
                        value: Symbol("Symbol." + name),
                        writable: false, enumerable: false, configurable: false
                    });
                }
            } catch (error) {
                console.info("[DuckDuckGo] Could not define Symbol." + name + ": " + error);
            }
        });

        // Namespaces WebKit does not define at all. Without a "kind" the namespace becomes a
        // generic nestable stub; "offscreen", "privacy" and "idle" are purpose-shaped (see
        // makeOffscreen, makePrivacy and makeIdle below).
        var missingNamespaces = [
            { name: "notifications" },
            { name: "offscreen", kind: "offscreen" },
            { name: "downloads" },
            { name: "idle", kind: "idle" },
            { name: "management" },
            { name: "privacy", kind: "privacy" },
            { name: "browsingData" },
            { name: "topSites" },
            { name: "sidePanel" }
        ];

        // Members missing from namespaces that WebKit does implement, addressed by dotted path.
        // A "namespace" member becomes a nestable stub, an "event" member an addListener object,
        // "managedStorage" a purpose-shaped stub (see makeManagedStorage below), and "constants" the
        // literal value carried by the entry.
        var missingMembers = [
            { path: "storage.managed", kind: "managedStorage" },
            { path: "webNavigation.onCreatedNavigationTarget", kind: "event" },
            { path: "runtime.onSuspend", kind: "event" }
        ];

        // The enum-like constants Chrome hangs off its namespaces, with Chrome's documented values.
        // Extension code dereferences these as call arguments — Bitwarden passes
        // `world: chrome.scripting.ExecutionWorld.ISOLATED` to `scripting.executeScript` — and WebKit
        // implements the call but not the constant, so the argument throws before the call happens.
        // Only the constants the supported extensions actually read are listed here.
        var missingConstants = [
            { path: "scripting.ExecutionWorld", value: { ISOLATED: "ISOLATED", MAIN: "MAIN" } },
            { path: "tabs.TAB_ID_NONE", value: -1 },
            { path: "windows.WINDOW_ID_NONE", value: -1 },
            { path: "windows.WINDOW_ID_CURRENT", value: -2 }
        ];

        // Constants are installed exactly like the members above — same "is it missing?" check, same
        // `define` — so they join that list rather than getting a loop of their own.
        missingConstants.forEach(function(constant) {
            missingMembers.push({ path: constant.path, kind: "constants", value: constant.value });
        });

        var retentionPropertyName = "\(Self.retentionPropertyName)";
        var eventNamePattern = /^on[A-Z]/;
        var stubDescription = "[DuckDuckGo API stub]";

        // WebKit hands out short-lived wrapper objects for its native namespaces and throws away
        // anything we added to one as soon as JavaScript stops referencing it. Parking every
        // decorated object here keeps both the wrapper and its stubs alive for the whole session.
        var retained = globalThis[retentionPropertyName];
        if (!Array.isArray(retained)) {
            retained = [];
            try {
                Object.defineProperty(globalThis, retentionPropertyName, {
                    value: retained,
                    writable: false,
                    enumerable: false,
                    configurable: true
                });
            } catch (error) {
                globalThis[retentionPropertyName] = retained;
            }
        }

        function retain(object) {
            // `globalThis` outlives everything, so keeping it here would only add noise.
            if (object && object !== globalThis && retained.indexOf(object) === -1) {
                retained.push(object);
            }
        }

        retain(api);

        // Reports unsupported API use to the browser, which logs the kind and the API path only.
        // "stubbed" and "missing" carry the API path; "error" carries an error message that the
        // browser classifies and discards. Everything here is best effort: it never throws, never
        // prevents an event's default action and stays quiet when the host has no such handler.
        var compatibilityHandlerName = "\(Self.compatibilityMessageHandlerName)";
        var compatibilityReports = Object.create(null);
        var apiReportCount = 0;
        var errorReportCount = 0;
        var maximumAPIReports = 200;
        // Errors get a budget of their own, so a page that logs a lot of errors cannot use up the
        // reports for stubbed and missing APIs.
        var maximumErrorReports = 50;
        var maximumErrorMessageLength = 300;
        var isReporting = false;

        // Only text shaped like an error about an API leaves the page; everything else stays here.
        // The browser classifies these further (and is the one place that decides what is logged).
        var reportableErrorFragments = ["is not an object (evaluating '", "is not a function. (In '", "Invalid call to ",
            "Can't find variable: ", " is not defined."];

        function isReportableErrorMessage(message) {
            return reportableErrorFragments.some(function(fragment) {
                return message.indexOf(fragment) !== -1;
            });
        }

        function postCompatibilityReport(payload, dedupeKey) {
            var isError = payload.kind === "error";
            if (isReporting || compatibilityReports[dedupeKey]
                || (isError ? errorReportCount >= maximumErrorReports : apiReportCount >= maximumAPIReports)) {
                return;
            }
            isReporting = true;
            try {
                var handlers = globalThis.webkit && globalThis.webkit.messageHandlers;
                var handler = handlers && handlers[compatibilityHandlerName];
                if (handler && typeof handler.postMessage === "function") {
                    compatibilityReports[dedupeKey] = true;
                    if (isError) {
                        errorReportCount += 1;
                    } else {
                        apiReportCount += 1;
                    }
                    handler.postMessage(payload);
                }
            } catch (error) {
                // Reporting must never disturb the page.
            } finally {
                isReporting = false;
            }
        }

        function reportAPI(kind, path) {
            if (typeof path === "string") {
                postCompatibilityReport({ kind: kind, api: path }, kind + " " + path);
            }
        }

        function reportErrorMessage(message) {
            if (typeof message === "string" && isReportableErrorMessage(message)) {
                var trimmed = message.slice(0, maximumErrorMessageLength);
                postCompatibilityReport({ kind: "error", message: trimmed }, "error " + trimmed);
            }
        }

        function messageOf(value) {
            try {
                if (typeof value === "string") {
                    return value;
                }
                if (value && typeof value.message === "string") {
                    return value.message;
                }
            } catch (error) {
                // A value that throws on access carries no usable message.
            }
            return undefined;
        }

        function installCompatibilityHooks() {
            var installedMarker = "__ddgAPICompatibilityHooksInstalled";
            try {
                if (globalThis[installedMarker] === true || typeof globalThis.addEventListener !== "function") {
                    return;
                }
                Object.defineProperty(globalThis, installedMarker, {
                    value: true,
                    writable: false,
                    enumerable: false,
                    configurable: true
                });
            } catch (error) {
                return;
            }

            globalThis.addEventListener("error", function(event) {
                reportErrorMessage(messageOf(event && event.error) || messageOf(event && event.message));
            });
            globalThis.addEventListener("unhandledrejection", function(event) {
                reportErrorMessage(messageOf(event && event.reason));
            });

            // The wrapper is what Web Inspector shows as the top frame of a logged message, instead of
            // the caller. That is accepted: wrapping is the only way to see what Angular's
            // ErrorHandler prints, which is how Bitwarden surfaces caught errors.
            ["error", "warn"].forEach(function(methodName) {
                try {
                    var original = globalThis.console && globalThis.console[methodName];
                    if (typeof original !== "function") {
                        return;
                    }
                    globalThis.console[methodName] = function() {
                        try {
                            for (var index = 0; index < Math.min(arguments.length, 5); index++) {
                                reportErrorMessage(messageOf(arguments[index]));
                            }
                        } catch (error) {
                            // Never let reporting stop the page from logging.
                        }
                        return original.apply(this, arguments);
                    };
                } catch (error) {
                    // A frozen console is left as it is.
                }
            });
        }

        installCompatibilityHooks();

        // Hands a trailing Chrome-style callback its value once, out of band, so a throwing
        // callback cannot take down the caller.
        function invokeCallback(callback, value) {
            Promise.resolve().then(function() {
                try {
                    callback(value);
                } catch (error) {
                    console.info("[DuckDuckGo] Stubbed API callback threw: " + error);
                }
            });
        }

        // A stubbed API method that answers with `makeValue()`, promise-style and callback-style.
        function makeResolver(makeValue) {
            return function() {
                var value = makeValue();
                var callback = arguments.length > 0 ? arguments[arguments.length - 1] : undefined;
                if (typeof callback === "function") {
                    invokeCallback(callback, value);
                }
                return Promise.resolve(value);
            };
        }

        // `path`, when given, names the API for the compatibility log: registering a listener counts
        // as using a stub. The events inside working shims pass no path.
        function makeEvent(path) {
            return {
                addListener: function() {
                    reportAPI("stubbed", path === undefined ? undefined : path + ".addListener");
                },
                removeListener: function() {},
                hasListener: function() {
                    return false;
                },
                hasListeners: function() {
                    return false;
                }
            };
        }

        // A callable, infinitely nestable placeholder: `chrome.privacy.services.passwordSavingEnabled.get()`
        // resolves through it without ever throwing, and any `onSomething` property is an event object.
        // `path` is the stub's API path, reported when it is called; reading a property is not a use.
        function makeStub(path) {
            var children = Object.create(null);

            return new Proxy(function() {}, {
                get: function(target, property) {
                    if (property === "then") {
                        // Never look like a thenable: awaiting or resolving a namespace must not hang.
                        return undefined;
                    }
                    if (property === Symbol.toPrimitive) {
                        return function() {
                            return stubDescription;
                        };
                    }
                    if (property === "toString") {
                        return function() {
                            return stubDescription;
                        };
                    }
                    if (typeof property !== "string") {
                        return undefined;
                    }
                    if (property === "call" || property === "apply" || property === "bind") {
                        // `stub.call(...)` is a call of the stub itself: the function's own methods must
                        // not extend the API path, or `chrome.downloads.download.call(...)` would be
                        // reported as `chrome.downloads.download.call`.
                        return Reflect.get(target, property);
                    }
                    if (!(property in children)) {
                        var childPath = path + "." + property;
                        children[property] = eventNamePattern.test(property) ? makeEvent(childPath) : makeStub(childPath);
                    }
                    return children[property];
                },
                apply: function(target, thisArgument, argumentsList) {
                    reportAPI("stubbed", path);
                    // Support both API styles: hand `undefined` to a trailing callback, and return a
                    // promise for callers that await instead.
                    var callback = argumentsList.length > 0 ? argumentsList[argumentsList.length - 1] : undefined;
                    if (typeof callback === "function") {
                        invokeCallback(callback, undefined);
                    }
                    return Promise.resolve(undefined);
                }
            });
        }

        // `storage.managed` needs more than the generic stub: Chrome resolves `get()` to an object
        // (empty when no policy is set) and extensions read a key straight off the result, so
        // resolving to `undefined` would throw at their call site rather than ours. Every call gets
        // a fresh object, so a caller mutating one result cannot leak into the next.
        function makeManagedStorage() {
            return {
                get: makeResolver(function() {
                    return {};
                }),
                getBytesInUse: makeResolver(function() {
                    return 0;
                }),
                onChanged: makeEvent()
            };
        }

        // Resolves a document URL against the background page, the way the page itself would.
        function resolveDocumentURL(url) {
            return new URL(url === undefined || url === null ? "" : String(url), globalThis.location.href).href;
        }

        var offscreenReasonNames = [
            "TESTING", "AUDIO_PLAYBACK", "IFRAME_SCRIPTING", "DOM_SCRAPING", "BLOBS", "DOM_PARSER",
            "USER_MEDIA", "DISPLAY_MEDIA", "WEB_RTC", "CLIPBOARD", "LOCAL_STORAGE", "WORKERS",
            "BATTERY_STATUS", "MATCH_MEDIA", "GEOLOCATION"
        ];

        // `chrome.offscreen` is the one stub that does real work. Bitwarden copies to the clipboard
        // by opening an offscreen document, sending it a message and closing it again, so a no-op
        // `createDocument` makes "copy password" do nothing at all. An extension iframe inside the
        // background page is itself an extension page with the full API: the offscreen page's
        // `runtime.onMessage` listeners run there and messages from the background page reach them.
        // Whether the clipboard write from that hidden frame is allowed under WebKit has not been
        // measured — this turns a silent no-op into a real attempt whose outcome shows up in the
        // extension's own logs.
        function makeOffscreen() {
            var documentFrame = null;
            var loadTimeoutInMilliseconds = 5000;

            var reason = {};
            offscreenReasonNames.forEach(function(name) {
                reason[name] = name;
            });

            var offscreen = {
                Reason: Object.freeze(reason),
                hasDocument: makeResolver(function() {
                    return documentFrame !== null;
                }),
                createDocument: function(parameters) {
                    var callback = arguments.length > 1 ? arguments[arguments.length - 1] : undefined;
                    if (documentFrame !== null) {
                        // Chrome's own wording, so an extension matching on the message still matches.
                        return Promise.reject(new Error("Only a single offscreen document may be created."));
                    }

                    var frame = document.createElement("iframe");
                    frame.setAttribute("hidden", "hidden");
                    frame.setAttribute("aria-hidden", "true");
                    frame.style.width = "0";
                    frame.style.height = "0";
                    frame.style.border = "0";
                    frame.src = resolveDocumentURL(parameters ? parameters.url : undefined);
                    documentFrame = frame;
                    (document.body || document.documentElement).appendChild(frame);

                    return new Promise(function(resolve) {
                        var isSettled = false;
                        function finish() {
                            if (isSettled) {
                                return;
                            }
                            isSettled = true;
                            if (typeof callback === "function") {
                                invokeCallback(callback, undefined);
                            }
                            resolve(undefined);
                        }
                        frame.addEventListener("load", finish);
                        // A document that never loads must not leave the caller awaiting forever.
                        setTimeout(finish, loadTimeoutInMilliseconds);
                    });
                },
                closeDocument: function() {
                    var callback = arguments.length > 0 ? arguments[arguments.length - 1] : undefined;
                    if (documentFrame === null) {
                        return Promise.reject(new Error("No current offscreen document."));
                    }
                    var frame = documentFrame;
                    documentFrame = null;
                    if (typeof frame.remove === "function") {
                        frame.remove();
                    } else if (frame.parentNode) {
                        frame.parentNode.removeChild(frame);
                    }
                    if (typeof callback === "function") {
                        invokeCallback(callback, undefined);
                    }
                    return Promise.resolve(undefined);
                }
            };

            // The namespace owns the open document, so it has to outlive the wrapper it hangs off.
            retain(offscreen);
            return offscreen;
        }

        // The `privacy.services` settings the stub answers for — the three Bitwarden turns off to
        // become the default password manager — and the one `storage.local` key holding the values
        // the extension has set, as `{ passwordSavingEnabled: false, ... }`. A setting that was never
        // set, or was cleared, is absent from that object.
        var privacySettingNames = ["passwordSavingEnabled", "autofillAddressEnabled", "autofillCreditCardEnabled"];
        var privacySettingsStorageKey = "__ddgPrivacySettings";

        // Keeps only the known settings, as booleans, so whatever sits under the key cannot reshape
        // the answers.
        function sanitizePrivacySettings(stored) {
            var settings = {};
            if (stored === null || typeof stored !== "object") {
                return settings;
            }
            privacySettingNames.forEach(function(name) {
                if (Object.prototype.hasOwnProperty.call(stored, name)) {
                    settings[name] = stored[name] === true;
                }
            });
            return settings;
        }

        // Calls a `storage.local` method and settles once, whichever way the host answers: through the
        // trailing callback, through a returned promise, or both.
        function callStorageArea(area, methodName, argument) {
            return new Promise(function(resolve, reject) {
                var isSettled = false;
                function finish(value) {
                    if (!isSettled) {
                        isSettled = true;
                        resolve(value);
                    }
                }
                function fail(error) {
                    if (!isSettled) {
                        isSettled = true;
                        reject(error);
                    }
                }
                try {
                    var result = area[methodName](argument, finish);
                    if (result && typeof result.then === "function") {
                        result.then(finish, fail);
                    }
                } catch (error) {
                    fail(error);
                }
            });
        }

        // The state shared by the three settings. `storage.local` is shared by every page of the
        // extension and survives a restart, like the browser setting it stands in for; when it is
        // unavailable, or a call to it fails, the settings live in memory for this page instead so
        // nothing ever throws. Operations run one after another, so a `set` that follows another
        // `set` reads the state the first one wrote rather than racing it.
        function makePrivacySettingsStore() {
            var memory = {};
            var queue = Promise.resolve();

            function storageArea() {
                var storage = api.storage;
                var local = storage ? storage.local : undefined;
                if (!local || typeof local.get !== "function" || typeof local.set !== "function") {
                    return null;
                }
                return local;
            }

            function enqueue(operation) {
                var result = queue.then(operation);
                queue = result.catch(function() {});
                return result;
            }

            function readSettings() {
                var area = storageArea();
                if (area === null) {
                    return Promise.resolve(sanitizePrivacySettings(memory));
                }
                return callStorageArea(area, "get", privacySettingsStorageKey).then(function(items) {
                    if (items === null || typeof items !== "object") {
                        // A failed callback-style read answers `undefined`; keep what this page knows.
                        return sanitizePrivacySettings(memory);
                    }
                    return sanitizePrivacySettings(items[privacySettingsStorageKey]);
                }, function(error) {
                    console.info("[DuckDuckGo] Could not read the privacy settings: " + error);
                    return sanitizePrivacySettings(memory);
                });
            }

            function writeSettings(settings) {
                memory = sanitizePrivacySettings(settings);
                var area = storageArea();
                if (area === null) {
                    return Promise.resolve(undefined);
                }
                var items = {};
                items[privacySettingsStorageKey] = sanitizePrivacySettings(settings);
                return callStorageArea(area, "set", items).then(function() {
                    return undefined;
                }, function(error) {
                    console.info("[DuckDuckGo] Could not store the privacy settings: " + error);
                    return undefined;
                });
            }

            return {
                read: function() {
                    return enqueue(readSettings);
                },
                update: function(mutate) {
                    return enqueue(function() {
                        return readSettings().then(function(settings) {
                            mutate(settings);
                            return writeSettings(settings);
                        });
                    });
                }
            };
        }

        // Hands a trailing callback the value the promise settles with, and returns the promise, the
        // way Chrome's dual-style APIs behave. The callback stays silent if the promise rejects.
        function answerBothStyles(promise, callback) {
            if (typeof callback === "function") {
                promise.then(function(value) {
                    invokeCallback(callback, value);
                }, function() {});
            }
            return promise;
        }

        // One `ChromeSetting`. Nothing stored means the browser default: enabled, and the extension
        // could take control of it. Once the extension sets a value it controls the setting, which
        // is what Bitwarden checks for — `controlled_by_this_extension` with `value === false`.
        function makeChromeSetting(store, name) {
            function trailingCallback(argumentsList) {
                var last = argumentsList.length > 0 ? argumentsList[argumentsList.length - 1] : undefined;
                return typeof last === "function" ? last : undefined;
            }

            return {
                get: function() {
                    var answer = store.read().then(function(settings) {
                        if (Object.prototype.hasOwnProperty.call(settings, name)) {
                            return { value: settings[name], levelOfControl: "controlled_by_this_extension" };
                        }
                        return { value: true, levelOfControl: "controllable_by_this_extension" };
                    });
                    return answerBothStyles(answer, trailingCallback(arguments));
                },
                set: function(details) {
                    var value = details !== null && typeof details === "object" ? Boolean(details.value) : false;
                    var answer = store.update(function(settings) {
                        settings[name] = value;
                    });
                    return answerBothStyles(answer, trailingCallback(arguments));
                },
                clear: function() {
                    var answer = store.update(function(settings) {
                        delete settings[name];
                    });
                    return answerBothStyles(answer, trailingCallback(arguments));
                },
                onChange: makeEvent()
            };
        }

        // `chrome.privacy` with working `services` settings; `network` and `websites` stay generic
        // stubs so other code paths that touch them keep running.
        function makePrivacy() {
            var store = makePrivacySettingsStore();
            var services = {};
            privacySettingNames.forEach(function(name) {
                services[name] = makeChromeSetting(store, name);
            });

            var privacy = {
                services: services,
                network: makeStub("privacy.network"),
                websites: makeStub("privacy.websites")
            };

            retain(privacy);
            return privacy;
        }

        var idleMessageHandlerName = "\(Self.idleMessageHandlerName)";
        var idleStates = ["active", "idle", "locked"];
        var idleDefaultDetectionInterval = 60;
        // Chrome's lower bound for a detection interval, in seconds.
        var idleMinimumDetectionInterval = 15;
        var idlePollIntervalInMilliseconds = 15000;

        function clampIdleDetectionInterval(seconds) {
            var value = Math.floor(Number(seconds));
            return isFinite(value) ? Math.max(idleMinimumDetectionInterval, value) : idleDefaultDetectionInterval;
        }

        // Asks the app for the idle state. Never rejects: no handler, a failed reply or an unknown
        // answer all read as `active`.
        function askForIdleState(detectionInterval) {
            try {
                var handlers = globalThis.webkit && globalThis.webkit.messageHandlers;
                var handler = handlers && handlers[idleMessageHandlerName];
                if (!handler || typeof handler.postMessage !== "function") {
                    return Promise.resolve("active");
                }
                return Promise.resolve(handler.postMessage({ detectionInterval: detectionInterval })).then(function(state) {
                    return idleStates.indexOf(state) !== -1 ? state : "active";
                }, function() {
                    return "active";
                });
            } catch (error) {
                return Promise.resolve("active");
            }
        }

        // `chrome.idle`. While `onStateChanged` has listeners, a single timer polls the app and the
        // listeners hear about changes only; the state before the first answer is `active`.
        function makeIdle() {
            var detectionInterval = idleDefaultDetectionInterval;
            var listeners = [];
            var timer = null;
            var lastState = "active";
            var isPolling = false;

            function poll() {
                if (isPolling) {
                    return;
                }
                isPolling = true;
                askForIdleState(detectionInterval).then(function(state) {
                    isPolling = false;
                    if (state === lastState) {
                        return;
                    }
                    lastState = state;
                    listeners.slice().forEach(function(listener) {
                        try {
                            listener(state);
                        } catch (error) {
                            console.info("[DuckDuckGo] An idle.onStateChanged listener threw: " + error);
                        }
                    });
                });
            }

            var idle = {
                queryState: function(seconds) {
                    var callback = arguments.length > 1 ? arguments[arguments.length - 1] : undefined;
                    return answerBothStyles(askForIdleState(clampIdleDetectionInterval(seconds)), callback);
                },
                setDetectionInterval: function(seconds) {
                    detectionInterval = clampIdleDetectionInterval(seconds);
                },
                getAutoLockDelay: makeResolver(function() {
                    return 0;
                }),
                onStateChanged: {
                    addListener: function(listener) {
                        if (typeof listener !== "function" || listeners.indexOf(listener) !== -1) {
                            return;
                        }
                        listeners.push(listener);
                        if (timer === null) {
                            timer = setInterval(poll, idlePollIntervalInMilliseconds);
                        }
                    },
                    removeListener: function(listener) {
                        var index = listeners.indexOf(listener);
                        if (index === -1) {
                            return;
                        }
                        listeners.splice(index, 1);
                        if (listeners.length === 0 && timer !== null) {
                            clearInterval(timer);
                            timer = null;
                        }
                    },
                    hasListener: function(listener) {
                        return listeners.indexOf(listener) !== -1;
                    },
                    hasListeners: function() {
                        return listeners.length > 0;
                    }
                }
            };

            // The namespace owns the poll timer and the listeners, so it has to outlive the wrapper
            // it hangs off.
            retain(idle);
            return idle;
        }

        // Constants are handed out frozen, so an extension that walks one cannot reshape what the
        // next reader sees. Primitives — `tabs.TAB_ID_NONE` is just `-1` — pass straight through.
        function makeConstants(value) {
            return value !== null && typeof value === "object" ? Object.freeze(value) : value;
        }

        function makeMember(entry, path) {
            if (entry.kind === "event") {
                return makeEvent(path);
            }
            if (entry.kind === "managedStorage") {
                return makeManagedStorage();
            }
            if (entry.kind === "offscreen") {
                return makeOffscreen();
            }
            if (entry.kind === "privacy") {
                return makePrivacy();
            }
            if (entry.kind === "idle") {
                return makeIdle();
            }
            if (entry.kind === "constants") {
                return makeConstants(entry.value);
            }
            return makeStub(path);
        }

        function define(owner, key, value) {
            try {
                owner[key] = value;
                if (owner[key] === value) {
                    retain(owner);
                    return true;
                }
            } catch (error) {
                // A read-only or accessor-backed property; retry with defineProperty below.
            }
            try {
                Object.defineProperty(owner, key, {
                    value: value,
                    writable: true,
                    enumerable: true,
                    configurable: true
                });
                if (owner[key] === value) {
                    retain(owner);
                    return true;
                }
                return false;
            } catch (error) {
                return false;
            }
        }

        // WebKit checks every name handed to `chrome.permissions` against the permissions it
        // implements and rejects the whole call for one it does not recognize, where Chrome answers
        // `false`. The wrappers below ask the host for the descriptor as given first — so a host that
        // knows every name behaves exactly as before — and only translate when that call comes back
        // with the validation error, which they recognize by message since no error code is exposed.
        var invalidPermissionPattern = /is not a valid permission|invalid.*permission/i;
        var reportedUnknownPermissions = Object.create(null);
        var wrappedMarkerName = "__ddgWrapped";
        // `answerWithoutHost` is the answer for a descriptor that named only virtual permissions (see
        // below): they are always held, so `contains` and `request` succeed, and they cannot be
        // taken away, so `remove` reports that nothing was removed.
        var wrappedPermissionsMethods = [
            { name: "contains", unknownNameFails: true, answerWithoutHost: true },
            { name: "request", unknownNameFails: true, answerWithoutHost: true },
            { name: "remove", unknownNameFails: false, answerWithoutHost: false }
        ];

        // Permissions WebKit rejects but this script provides itself, so they count as granted.
        // WebKit does not know these names, so the host would answer `false` (or throw) for these
        // forever. `privacy` is backed by makePrivacy and `idle` by makeIdle above; Bitwarden will not touch it until
        // `contains` or `request` says it holds the permission. `permissions.onAdded` is not fired
        // for them: WebKit owns that event, and Bitwarden's Chrome path does not wait for it.
        var virtualPermissionNames = ["privacy", "idle"];

        function isVirtualPermission(name) {
            return virtualPermissionNames.indexOf(name) !== -1;
        }

        // The descriptor to hand the host with the virtual names taken out, or the descriptor itself
        // when it names none, so a call without them reaches the host exactly as the caller made it.
        // `isEmpty` means nothing is left to ask the host about.
        function stripVirtualPermissions(descriptor) {
            var names = descriptor && Array.isArray(descriptor.permissions) ? descriptor.permissions : null;
            if (names === null || !names.some(isVirtualPermission)) {
                return { descriptor: descriptor, isEmpty: false };
            }
            var stripped = {};
            Object.keys(descriptor).forEach(function(key) {
                stripped[key] = descriptor[key];
            });
            stripped.permissions = names.filter(function(name) {
                return !isVirtualPermission(name);
            });
            var origins = Array.isArray(descriptor.origins) ? descriptor.origins : [];
            return { descriptor: stripped, isEmpty: stripped.permissions.length === 0 && origins.length === 0 };
        }

        function isInvalidPermissionError(error) {
            if (error === undefined || error === null) {
                return false;
            }
            var message = error.message === undefined || error.message === null ? String(error) : String(error.message);
            return invalidPermissionPattern.test(message);
        }

        function reportUnknownPermission(name) {
            if (reportedUnknownPermissions[name]) {
                return;
            }
            reportedUnknownPermissions[name] = true;
            if (typeof name === "string") {
                reportAPI("missing", "permission:" + name);
            }
            console.info("[DuckDuckGo] The host does not implement the '" + name
                + "' permission; answering the way Chrome would instead of throwing");
        }

        // Always hands back a promise, so a host that throws synchronously and one that rejects take
        // the same path through the wrapper.
        function callPermissionsMethod(method, owner, descriptor) {
            try {
                return Promise.resolve(method.call(owner, descriptor));
            } catch (error) {
                return Promise.reject(error);
            }
        }

        // Asks about a single descriptor, reporting whether the host recognized it rather than
        // letting one unrecognized name take the surrounding query down. Errors that are not the
        // validation error are real failures and travel on untouched.
        function probePermissionsDescriptor(method, owner, descriptor, name) {
            return callPermissionsMethod(method, owner, descriptor).then(function(result) {
                return { isKnown: true, isSatisfied: result === true };
            }, function(error) {
                if (!isInvalidPermissionError(error)) {
                    throw error;
                }
                if (name !== undefined) {
                    reportUnknownPermission(name);
                }
                return { isKnown: false, isSatisfied: false };
            });
        }

        function probePermissionsIndividually(method, owner, descriptor) {
            var names = descriptor && Array.isArray(descriptor.permissions) ? descriptor.permissions : [];
            var origins = descriptor && Array.isArray(descriptor.origins) ? descriptor.origins : [];
            var probes = names.map(function(name) {
                return probePermissionsDescriptor(method, owner, { permissions: [name] }, name);
            });
            if (origins.length > 0) {
                // Origins are never the reason for the validation error, so they stay one call.
                probes.push(probePermissionsDescriptor(method, owner, { origins: origins }, undefined));
            }
            return Promise.all(probes);
        }

        // `contains` and `request` cannot honestly answer `true` for a name the host does not know —
        // it can neither hold nor grant such a permission — so an unknown name makes the whole answer
        // `false`. `remove` has nothing to remove for one, so it ignores it and reports on the rest.
        function combinePermissionOutcomes(outcomes, unknownNameFails) {
            var isSatisfied = true;
            for (var index = 0; index < outcomes.length; index++) {
                if (!outcomes[index].isKnown) {
                    if (unknownNameFails) {
                        return false;
                    }
                } else if (!outcomes[index].isSatisfied) {
                    isSatisfied = false;
                }
            }
            return isSatisfied;
        }

        // The wrapper binds its owner, so destructured calls — `const {contains} = chrome.permissions`
        // — keep working, and it answers both API styles the way the method it replaces did.
        // Virtual permissions are taken out first; whatever remains goes to the host, and the answer
        // for the remainder is the answer for the whole descriptor.
        function makePermissionsMethod(owner, methodName, unknownNameFails, answerWithoutHost) {
            var original = owner[methodName];
            if (typeof original !== "function" || original[wrappedMarkerName] === true) {
                return null;
            }

            var wrapper = function(descriptor) {
                var callback = arguments.length > 0 ? arguments[arguments.length - 1] : undefined;
                var hostQuery = stripVirtualPermissions(descriptor);
                var promise;
                if (hostQuery.isEmpty) {
                    promise = Promise.resolve(answerWithoutHost);
                } else {
                    promise = callPermissionsMethod(original, owner, hostQuery.descriptor).catch(function(error) {
                        if (!isInvalidPermissionError(error)) {
                            throw error;
                        }
                        return probePermissionsIndividually(original, owner, hostQuery.descriptor).then(function(outcomes) {
                            return combinePermissionOutcomes(outcomes, unknownNameFails);
                        });
                    });
                }
                if (typeof callback === "function") {
                    promise.then(function(value) {
                        invokeCallback(callback, value);
                    }, function() {
                        // A real failure is reported through the returned promise; Chrome's callback
                        // form stays silent for it, so there is nothing to hand the callback here.
                    });
                }
                return promise;
            };

            try {
                Object.defineProperty(wrapper, wrappedMarkerName, {
                    value: true,
                    writable: false,
                    enumerable: false,
                    configurable: true
                });
            } catch (error) {
                console.info("[DuckDuckGo] Could not mark the chrome.permissions." + methodName + " wrapper: " + error);
            }
            return wrapper;
        }

        var stubbedNamespaces = [];
        var stubbedMembers = [];
        var wrappedNamespaces = [];

        missingNamespaces.forEach(function(namespace) {
            try {
                if (api[namespace.name] !== undefined) {
                    return;
                }
                if (define(api, namespace.name, makeMember(namespace, namespace.name))) {
                    stubbedNamespaces.push(namespace.name);
                }
            } catch (error) {
                console.info("[DuckDuckGo] Could not stub chrome." + namespace.name + ": " + error);
            }
        });

        missingMembers.forEach(function(member) {
            try {
                var segments = member.path.split(".");
                var key = segments[segments.length - 1];
                var owner = api;
                for (var index = 0; index < segments.length - 1; index++) {
                    if (owner === undefined || owner === null) {
                        return;
                    }
                    owner = owner[segments[index]];
                }
                if (owner === undefined || owner === null || owner[key] !== undefined) {
                    return;
                }
                if (define(owner, key, makeMember(member, member.path))) {
                    stubbedMembers.push(member.path);
                }
            } catch (error) {
                console.info("[DuckDuckGo] Could not stub chrome." + member.path + ": " + error);
            }
        });

        // `chrome.permissions` exists; only the three methods that validate names are replaced, so
        // `getAll` and the `onAdded`/`onRemoved` events stay exactly as the host defined them.
        try {
            var permissions = api.permissions;
            if (permissions !== undefined && permissions !== null) {
                var wrappedMethodNames = [];
                wrappedPermissionsMethods.forEach(function(method) {
                    var wrapper = makePermissionsMethod(permissions, method.name, method.unknownNameFails,
                        method.answerWithoutHost);
                    if (wrapper !== null && define(permissions, method.name, wrapper)) {
                        wrappedMethodNames.push(method.name);
                    }
                });
                if (wrappedMethodNames.length > 0) {
                    wrappedNamespaces.push("permissions");
                }
            }
        } catch (error) {
            console.info("[DuckDuckGo] Could not wrap chrome.permissions: " + error);
        }

        if (stubbedNamespaces.length > 0 || stubbedMembers.length > 0
            || wrappedNamespaces.length > 0) {
            console.info("[DuckDuckGo] Stubbed unavailable extension APIs — namespaces: ["
                + stubbedNamespaces.join(", ") + "], members: [" + stubbedMembers.join(", ")
                + "], wrapped: ["
                + wrappedNamespaces.join(", ") + "]");
        }
    })();

    """
}
