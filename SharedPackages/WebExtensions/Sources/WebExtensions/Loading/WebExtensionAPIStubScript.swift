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
/// 1Password extension calls `chrome.notifications.onClicked.addListener(...)` while wiring up its
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
/// the loader grants it, but WebKit silently drops a grant for a name it does not implement, so both
/// calls answer `false` and the toggle fails with an error dialog. Since this script is what actually
/// provides `privacy`, the permissions wrappers treat it as a *virtual* permission that is always
/// granted: they strip it from the descriptor before asking the host and answer for the rest. The
/// `privacy.services` settings are then shaped like Chrome's `ChromeSetting` — `get` answers
/// `{value, levelOfControl}` and reports `controlled_by_this_extension` once the extension has set a
/// value — and persisted in `storage.local` under one reserved key, because the popup is a fresh page on
/// every open and re-reads them to draw its checkbox, and the background page reads them too. Nothing
/// in the app reads these values; they record the extension's choice so it reads back consistently.
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
/// A handful of events WebKit leaves out of namespaces it does implement are stubbed as well, even
/// though nothing we support *listens* on them meaningfully: iCloud Passwords registers
/// `webNavigation.onHistoryStateUpdated` and `webNavigation.onTabReplaced` unguarded at the top
/// level of its background script, and the first missing one aborted the whole script. The rest of
/// that list — `onReferenceFragmentUpdated`, `tabs.onZoomChange` and the `runtime` lifecycle
/// events — were measured missing alongside them and cost nothing to include. These stubs are inert:
/// an extension that relies on `onHistoryStateUpdated` to follow single-page navigation still gets
/// no events, it just no longer crashes.
///
/// Two behaviors of the host are worth calling out, both established by measurement on macOS 26.6.2:
/// - `chrome.webNavigation`, `chrome.tabs` and friends are native wrapper objects that WebKit
///   discards once JavaScript stops referencing them, taking any property we added with them: an
///   event stub installed on `chrome.webNavigation` vanished within about half a second. The script
///   therefore parks every object it decorates in a retention array on `globalThis`, which kept the
///   stubs alive for the lifetime of the background page.
/// - A Manifest V3 background page still reports itself as MV3 Chromium to extensions that sniff
///   for it, so 1Password reaches for the ServiceWorker `clients` global, which a page does not
///   have. A minimal `clients` stub keeps that path from throwing on every use.
///
/// Note that stubs are only installed for names that are actually missing, so a future WebKit that
/// implements one of them wins automatically.
enum WebExtensionAPIStubScript {

    /// Property on `globalThis` holding the objects the script decorated, so WebKit's native
    /// namespace wrappers stay alive along with the stubs installed on them.
    static let retentionPropertyName = "__ddgRetainedExtensionAPINamespaces"

    static let source = """
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

        // Namespaces WebKit does not define at all. Without a "kind" the namespace becomes a
        // generic nestable stub; "offscreen" and "privacy" are purpose-shaped (see makeOffscreen and
        // makePrivacy below).
        var missingNamespaces = [
            { name: "notifications" },
            { name: "offscreen", kind: "offscreen" },
            { name: "downloads" },
            { name: "idle" },
            { name: "management" },
            { name: "privacy", kind: "privacy" },
            { name: "browsingData" },
            { name: "topSites" },
            { name: "sidePanel" }
        ];

        // Members missing from namespaces that WebKit does implement, addressed by dotted path.
        // A "namespace" member becomes a nestable stub, an "event" member an addListener object,
        // "managedStorage" a purpose-shaped stub (see makeManagedStorage below), and "constants" the
        // literal value carried by the entry. The events are the ones measured missing from WebKit;
        // iCloud Passwords registers webNavigation.onHistoryStateUpdated and onTabReplaced unguarded
        // at the top level, and the others are listed because they cost nothing.
        var missingMembers = [
            { path: "storage.managed", kind: "managedStorage" },
            { path: "webNavigation.onCreatedNavigationTarget", kind: "event" },
            { path: "webNavigation.onHistoryStateUpdated", kind: "event" },
            { path: "webNavigation.onReferenceFragmentUpdated", kind: "event" },
            { path: "webNavigation.onTabReplaced", kind: "event" },
            { path: "tabs.onZoomChange", kind: "event" },
            { path: "runtime.onSuspend", kind: "event" },
            { path: "runtime.onSuspendCanceled", kind: "event" },
            { path: "runtime.onUpdateAvailable", kind: "event" },
            { path: "runtime.onRestartRequired", kind: "event" }
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

        function makeEvent() {
            return {
                addListener: function() {},
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
        function makeStub() {
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
                    if (!(property in children)) {
                        children[property] = eventNamePattern.test(property) ? makeEvent() : makeStub();
                    }
                    return children[property];
                },
                apply: function(target, thisArgument, argumentsList) {
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
                network: makeStub(),
                websites: makeStub()
            };

            retain(privacy);
            return privacy;
        }

        // Constants are handed out frozen, so an extension that walks one cannot reshape what the
        // next reader sees. Primitives — `tabs.TAB_ID_NONE` is just `-1` — pass straight through.
        function makeConstants(value) {
            return value !== null && typeof value === "object" ? Object.freeze(value) : value;
        }

        function makeMember(entry) {
            if (entry.kind === "event") {
                return makeEvent();
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
            if (entry.kind === "constants") {
                return makeConstants(entry.value);
            }
            return makeStub();
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

        // Permissions WebKit rejects but this script provides itself, so they count as granted. The
        // loader does grant an extension's optional permissions, but WebKit silently drops the grant
        // for a name it does not implement, so the host would answer `false` (or throw) for these
        // forever. `privacy` is backed by makePrivacy above; Bitwarden will not touch it until
        // `contains` or `request` says it holds the permission. `permissions.onAdded` is not fired
        // for them: WebKit owns that event, and Bitwarden's Chrome path does not wait for it.
        var virtualPermissionNames = ["privacy"];

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
        var stubbedGlobals = [];
        var wrappedNamespaces = [];

        missingNamespaces.forEach(function(namespace) {
            try {
                if (api[namespace.name] !== undefined) {
                    return;
                }
                if (define(api, namespace.name, makeMember(namespace))) {
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
                if (define(owner, key, makeMember(member))) {
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

        // An MV3 background page is not a service worker, but extensions that detect MV3 Chromium
        // assume it is and reach for the ServiceWorker `clients` global.
        try {
            if (globalThis.clients === undefined) {
                var clients = {
                    claim: function() {
                        return Promise.resolve();
                    },
                    get: function() {
                        return Promise.resolve(undefined);
                    },
                    matchAll: function() {
                        return Promise.resolve([]);
                    },
                    openWindow: function() {
                        return Promise.resolve(null);
                    }
                };
                if (define(globalThis, "clients", clients)) {
                    stubbedGlobals.push("clients");
                }
            }
        } catch (error) {
            console.info("[DuckDuckGo] Could not stub clients: " + error);
        }

        // An extension page loaded in an iframe inside a website runs in that website's web
        // process. iCloud Passwords' completion list is one: it is the "Enable Password AutoFill"
        // prompt under a login field. A call to `action.openPopup()` from such a frame is a
        // message WebKit's UI process treats as invalid, and WebKit answers an invalid message by
        // terminating the web process, which takes the website down with it. Extensions feature-
        // detect `action.openPopup` and, when it is absent, open their own popup page with
        // `window.open()` instead — the path they already ship for Firefox — so the member is
        // hidden in every frame that is not the top frame. The background page's own offscreen
        // iframe loses it too, at no cost.
        var hiddenMembers = [];
        try {
            var isEmbeddedFrame = false;
            try {
                isEmbeddedFrame = globalThis.top !== undefined && globalThis.top !== globalThis;
            } catch (error) {
                // A cross-origin `top` throws on access, which also means this is not the top frame.
                isEmbeddedFrame = true;
            }
            if (isEmbeddedFrame && api.action && api.action.openPopup !== undefined) {
                if (define(api.action, "openPopup", undefined)) {
                    hiddenMembers.push("action.openPopup");
                }
            }
        } catch (error) {
            console.info("[DuckDuckGo] Could not hide chrome.action.openPopup: " + error);
        }

        if (stubbedNamespaces.length > 0 || stubbedMembers.length > 0 || stubbedGlobals.length > 0
            || wrappedNamespaces.length > 0 || hiddenMembers.length > 0) {
            console.info("[DuckDuckGo] Stubbed unavailable extension APIs — namespaces: ["
                + stubbedNamespaces.join(", ") + "], members: [" + stubbedMembers.join(", ")
                + "], globals: [" + stubbedGlobals.join(", ") + "], wrapped: ["
                + wrappedNamespaces.join(", ") + "], hidden: [" + hiddenMembers.join(", ") + "]");
        }
    })();

    """
}
