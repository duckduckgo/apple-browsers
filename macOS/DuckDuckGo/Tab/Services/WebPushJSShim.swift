//
//  WebPushJSShim.swift
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
import WebKit

/// Monkey-patches `PushManager.prototype` so that `pushManager.subscribe(...)`
/// returns a synthesised `PushSubscription` instead of routing through
/// WebKit's native PushManager → webpushd → APNs path.
///
/// PoC only. The site sees a `PushSubscription`-shaped object with a fake
/// endpoint; it dutifully posts `{endpoint, keys}` to its backend, but the
/// backend can't reach the fake endpoint. To verify the receive path, fire a
/// synthetic push at the site's origin via Debug → Web Push → Fire Test Push
/// at Current Tab Origin.
enum WebPushJSShim {

    static func userScript() -> WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private static let source = #"""
    (function() {
        const LOG_PREFIX = '🟣 [shim]';

        function base64UrlEncode(buf) {
            const bytes = new Uint8Array(buf);
            let str = '';
            for (let i = 0; i < bytes.length; i++) {
                str += String.fromCharCode(bytes[i]);
            }
            return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
        }

        function randomBytes(len) {
            const buf = new Uint8Array(len);
            crypto.getRandomValues(buf);
            return buf;
        }

        // RFC 8291 expects a 65-byte uncompressed P-256 public key (0x04 prefix)
        // for p256dh and 16 random bytes for auth. We don't actually do ECDH —
        // the keys here are decorative; receive path goes via _processPushMessage:.
        let stashed = null;
        function makeSubscription(opts) {
            const id = (crypto.randomUUID && crypto.randomUUID()) || (Date.now() + '-' + Math.random());
            const p256dh = randomBytes(65); p256dh[0] = 0x04;
            const auth   = randomBytes(16);

            return {
                endpoint: 'https://ddg-webpush-poc.invalid/' + id,
                expirationTime: null,
                options: opts || { userVisibleOnly: true, applicationServerKey: null },
                getKey(name) {
                    if (name === 'p256dh') return p256dh.buffer;
                    if (name === 'auth')   return auth.buffer;
                    return null;
                },
                toJSON() {
                    return {
                        endpoint: this.endpoint,
                        expirationTime: this.expirationTime,
                        keys: {
                            p256dh: base64UrlEncode(p256dh.buffer),
                            auth:   base64UrlEncode(auth.buffer)
                        }
                    };
                },
                unsubscribe() {
                    console.log(LOG_PREFIX, 'unsubscribe()');
                    notifyNative('unsubscribe');
                    stashed = null;
                    return Promise.resolve(true);
                }
            };
        }

        // (1) Ensure a PushManager constructor exists on `window` so feature
        // detection (`'PushManager' in window`) passes even if WebKit's native
        // class isn't exposed.
        if (typeof window.PushManager === 'undefined') {
            window.PushManager = function PushManager() {};
            console.log(LOG_PREFIX, 'PushManager synthesised (native was missing)');
        }

        async function callNative(action) {
            const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ddgWebPushBridge;
            if (!bridge) {
                console.log(LOG_PREFIX, 'callNative SKIPPED (no bridge):', action);
                return null;
            }
            try {
                const result = await bridge.postMessage({ action });
                console.log(LOG_PREFIX, 'callNative →', action, '=', result);
                return result;
            } catch (e) {
                console.log(LOG_PREFIX, 'callNative ERROR:', action, e);
                return null;
            }
        }

        function notifyNative(action) {
            // Fire-and-forget shorthand for actions whose result we don't use.
            callNative(action);
        }

        // (2) Override the prototype methods so any PushManager instance
        // (native or synthesised, registration-bound) uses our subscribe path.
        const proto = window.PushManager.prototype;
        proto.subscribe = function(opts) {
            console.log(LOG_PREFIX, 'PushManager.subscribe', opts);
            stashed = makeSubscription(opts);
            notifyNative('subscribe');
            return Promise.resolve(stashed);
        };
        proto.getSubscription = async function() {
            if (stashed) {
                console.log(LOG_PREFIX, 'PushManager.getSubscription → cached');
                return stashed;
            }
            // Native may know about a subscription from before this page load.
            // Rehydrate a synthetic one — new keys (PoC), but page UI is correct.
            const knownToNative = await callNative('isSubscribed');
            console.log(LOG_PREFIX, 'PushManager.getSubscription → native says:', knownToNative);
            if (knownToNative) {
                stashed = makeSubscription({ userVisibleOnly: true, applicationServerKey: null });
            }
            return stashed || null;
        };
        proto.permissionState = function(_opts) {
            return Promise.resolve('granted');
        };

        // (3) Make sure `registration.pushManager` returns something useful even
        // if WebKit didn't define the property. Patch the SW registration
        // prototype's pushManager getter so it lazily creates an instance.
        if (typeof ServiceWorkerRegistration !== 'undefined') {
            const swrProto = ServiceWorkerRegistration.prototype;
            const desc = Object.getOwnPropertyDescriptor(swrProto, 'pushManager');
            if (!desc || !desc.get) {
                Object.defineProperty(swrProto, 'pushManager', {
                    configurable: true,
                    enumerable: true,
                    get() {
                        if (!this._ddgPushManager) {
                            this._ddgPushManager = Object.create(window.PushManager.prototype);
                        }
                        return this._ddgPushManager;
                    }
                });
                console.log(LOG_PREFIX, 'ServiceWorkerRegistration.pushManager getter synthesised');
            }
        }

        // (4) Shim navigator.permissions.query for push/notifications so sites
        // that gate subscribe() behind a Permissions-API precondition pass.
        if (navigator.permissions && typeof navigator.permissions.query === 'function') {
            const originalQuery = navigator.permissions.query.bind(navigator.permissions);
            navigator.permissions.query = function(descriptor) {
                if (descriptor && (descriptor.name === 'push' || descriptor.name === 'notifications')) {
                    return Promise.resolve({
                        state: 'granted',
                        status: 'granted',
                        onchange: null,
                        addEventListener() {},
                        removeEventListener() {},
                        dispatchEvent() { return false; }
                    });
                }
                return originalQuery(descriptor);
            };
        }

        console.log(LOG_PREFIX, 'PushManager shimmed');
    })();
    """#
}
