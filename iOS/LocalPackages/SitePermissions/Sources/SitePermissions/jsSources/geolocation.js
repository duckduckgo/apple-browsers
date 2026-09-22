/*
 * Copyright © 2026 DuckDuckGo. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * Routes the page's geolocation API through the app's per-site permission flow.
 * Injected at document start in each frame, this replacement preserves position
 * callbacks, watches, and geolocation PermissionStatus change events.
 *
 * The isolated companion checks frame restrictions. This script keeps the
 * page callbacks; Swift decides permissions, obtains locations, and returns results.
 * Other permission queries keep their native behavior. The embedding app owns
 * activation and teardown; immediate installation is for its tab web views.
 */
(() => {
    const oneShotHandler = globalThis.webkit?.messageHandlers?.sitePermissionsGeolocation;
    const watchHandler = globalThis.webkit?.messageHandlers?.sitePermissionsGeolocationWatch;
    if (!oneShotHandler || !watchHandler || globalThis.__ddgSitePermissionsGeolocation) {
        return;
    }

    // Captured methods keep the API adapter compatible with page libraries.
    // Native code obtains authoritative policy from the isolated companion script.
    const callThen = Function.prototype.call.bind(Promise.prototype.then);
    const postOneShot = oneShotHandler.postMessage.bind(oneShotHandler);
    const postWatch = watchHandler.postMessage.bind(watchHandler);
    const scheduleTask = globalThis.setTimeout.bind(globalThis);
    const apply = globalThis.Reflect.apply;
    const mapGet = globalThis.Map.prototype.get;
    const mapHas = globalThis.Map.prototype.has;
    const mapSet = globalThis.Map.prototype.set;
    const mapDelete = globalThis.Map.prototype.delete;
    const NativeEvent = globalThis.Event;
    const NativeEventTarget = globalThis.EventTarget;
    const dispatchEvent = NativeEventTarget?.prototype?.dispatchEvent;
    const freeze = globalThis.Object.freeze;
    const capability = "${CAPABILITY_TOKEN}";
    const installImmediately = ${INSTALL_IMMEDIATELY};
    const initialHostname = globalThis.location.hostname.toLowerCase();
    if (installImmediately && (initialHostname === "duck.ai" || initialHostname.endsWith(".duck.ai"))) {
        return;
    }
    const nativeGeolocation = navigator.geolocation;
    const nativePermissions = navigator.permissions;
    const nativePermissionsQuery = nativePermissions?.query;
    const activeWatches = new Map();
    const permissionStatuses = new Map();
    const randomToken = () => {
        if (typeof globalThis.crypto?.getRandomValues !== "function") {
            return null;
        }
        const values = new Uint32Array(4);
        globalThis.crypto.getRandomValues(values);
        return Array.from(values, (value) => value.toString(16).padStart(8, "0")).join("");
    };
    // Registration and callback identities are local to this document.
    const nonce = randomToken();
    const frameNonce = randomToken() ?? "unavailable";
    let nextWatchID = 1;
    let nextPermissionStatusID = 1;

    Object.defineProperty(globalThis, "__ddgSitePermissionsGeolocationDocumentID", {
        configurable: false,
        value: frameNonce
    });

    // Cross-origin frames are unsupported. Same-origin frames also need the
    // platform's effective policy: origin alone cannot prove that an iframe's
    // allow attribute or response headers permit geolocation.
    const isSameOriginAsTopLevel = (() => {
        if (globalThis.top === globalThis) {
            return true;
        }
        try {
            return globalThis.top.location.origin === globalThis.location.origin;
        } catch (_) {
            return false;
        }
    })();
    const hasNetworkOrigin = globalThis.origin !== "null" &&
        globalThis.location.hostname.length > 0 &&
        (globalThis.location.protocol === "https:" || globalThis.location.protocol === "http:");
    const nativePermissionsPolicy = document.permissionsPolicy ?? document.featurePolicy;
    const nativePolicyAllowsFeature = nativePermissionsPolicy?.allowsFeature;
    const policyAllowsGeolocation = () => {
        try {
            if (typeof nativePolicyAllowsFeature === "function") {
                return apply(nativePolicyAllowsFeature, nativePermissionsPolicy, ["geolocation"]);
            }
            // Native code checks the top-level response policy. Without this API,
            // subframe response policies cannot be verified, so deny subframes.
            return globalThis.top === globalThis;
        } catch (_) {
            return false;
        }
    };

    const isSecureContext = globalThis.isSecureContext === true;
    const isFramePolicyEligible = hasNetworkOrigin && isSameOriginAsTopLevel;
    let constraints = freeze({ isSecureContext: false, isPolicyAllowed: false, isSandboxed: true });

    const isContextEligible = () => nonce !== null && isSecureContext && isFramePolicyEligible;
    const isAllowedByPlatform = () => isContextEligible() && constraints.isSecureContext &&
        constraints.isPolicyAllowed && policyAllowsGeolocation() && !constraints.isSandboxed;

    const message = (kind, values = {}) => ({ capability, nonce, documentID: frameNonce, kind, ...values });

    // Native registration obtains policy in the isolated world and rechecks activation.
    const registerFrame = () => callThen(postOneShot(message("registerFrame")), (result) => {
        if (result?.status === "error" && result.code === 1) {
            constraints = freeze({ isSecureContext: false, isPolicyAllowed: false, isSandboxed: true });
            return false;
        }
        if (result?.status !== "registered") {
            throw new Error("Unable to register geolocation frame");
        }
        constraints = freeze({
            isSecureContext: result.constraints?.isSecureContext === true,
            isPolicyAllowed: result.constraints?.isPolicyAllowed === true,
            isSandboxed: result.constraints?.isSandboxed !== false
        });
        return result.enabled === true;
    });
    const registration = registerFrame();

    const optionsPayload = (options = {}) => {
        options = options ?? {};
        const payload = { enableHighAccuracy: Boolean(options.enableHighAccuracy) };
        if (options.timeout !== undefined && options.timeout !== Infinity) {
            const timeout = Number(options.timeout);
            payload.timeout = Number.isFinite(timeout) && timeout > 0 ? timeout : 0;
        }
        if (options.maximumAge !== undefined && options.maximumAge !== Infinity) {
            const maximumAge = Number(options.maximumAge);
            payload.maximumAge = Number.isFinite(maximumAge) && maximumAge > 0 ? maximumAge : 0;
        } else if (options.maximumAge === Infinity) {
            payload.maximumAge = "infinity";
        }
        return payload;
    };

    const positionError = (code, message) => ({ code, message, PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 });

    const deniedError = () => positionError(1, "Geolocation is not allowed in this context");
    const deniedResult = () => ({ status: "error", ...deniedError() });

    const invokeCallback = (callback, value) => {
        try {
            callback(value);
        } catch (exception) {
            scheduleTask(() => { throw exception; }, 0);
        }
    };

    const invokeError = (callback, error) => {
        if (typeof callback === "function") {
            invokeCallback(callback, error);
        }
    };

    const settlePosition = (result, success, error) => {
        if (result?.status === "success") {
            invokeCallback(success, { coords: result.coords, timestamp: result.timestamp });
        } else {
            invokeError(error, positionError(result?.code ?? 2, result?.message ?? "Geolocation is unavailable"));
        }
    };

    const normalizedPermissionState = (state) =>
        state === "granted" || state === "prompt" ? state : "denied";

    const permissionStatus = () => {
        let state = "denied";
        let initialized = false;
        let pendingState = null;
        const status = new NativeEventTarget();
        Object.defineProperties(status, {
            state: { configurable: false, enumerable: true, get: () => state },
            onchange: { configurable: true, enumerable: true, writable: true, value: null }
        });
        if (globalThis.PermissionStatus?.prototype) {
            Object.setPrototypeOf(status, globalThis.PermissionStatus.prototype);
        }
        return {
            status,
            initialize: (initialState) => {
                // A native change may arrive before the initial query reply.
                state = pendingState ?? initialState;
                initialized = true;
            },
            update: (newState) => {
                newState = normalizedPermissionState(newState);
                if (!initialized) {
                    pendingState = newState;
                    return;
                }
                if (state === newState) {
                    return;
                }
                state = newState;
                const event = new NativeEvent("change");
                apply(dispatchEvent, status, [event]);
                if (typeof status.onchange === "function") {
                    try {
                        apply(status.onchange, status, [event]);
                    } catch (exception) {
                        scheduleTask(() => { throw exception; }, 0);
                    }
                }
            }
        };
    };

    const getCurrentPosition = (success, error, options) => {
        if (typeof success !== "function") {
            throw new TypeError("The success callback must be a function");
        }

        if (!isContextEligible()) {
            queueMicrotask(() => invokeError(error, deniedError()));
            return;
        }

        callThen(
            callThen(registerFrame(), (enabled) => enabled && isAllowedByPlatform()
                ? postOneShot(message("getCurrentPosition", { options: optionsPayload(options) }))
                : deniedResult()),
            (result) => settlePosition(isAllowedByPlatform() ? result : deniedResult(), success, error),
            () => invokeError(error, positionError(2, "Geolocation is unavailable")));
    };

    const watchPosition = (success, error, options) => {
        if (typeof success !== "function") {
            throw new TypeError("The success callback must be a function");
        }

        const watchID = nextWatchID++;
        const requestID = `${frameNonce}:${watchID}`;
        apply(mapSet, activeWatches, [requestID, { success, error }]);

        if (!isContextEligible()) {
            queueMicrotask(() => {
                if (apply(mapDelete, activeWatches, [requestID])) {
                    invokeError(error, deniedError());
                }
            });
            return watchID;
        }

        callThen(
            callThen(registerFrame(), (enabled) => enabled && isAllowedByPlatform()
                ? postWatch(message("startWatch", { requestID, options: optionsPayload(options) }))
                : deniedResult()),
            (result) => {
                // clearWatch can run while native creation is pending; cancel a late start.
                if (!apply(mapHas, activeWatches, [requestID]) && result?.status === "started") {
                    callThen(postWatch(message("clearWatch", { requestID })), undefined, () => {});
                    return;
                }
                if (result?.status === "started" && !isAllowedByPlatform()) {
                    apply(mapDelete, activeWatches, [requestID]);
                    callThen(postWatch(message("clearWatch", { requestID })), undefined, () => {});
                    invokeError(error, deniedError());
                    return;
                }
                if (result?.status === "error" && apply(mapDelete, activeWatches, [requestID])) {
                    invokeError(error, positionError(result.code ?? 2, result.message ?? "Geolocation is unavailable"));
                }
            }, () => {
                if (apply(mapDelete, activeWatches, [requestID])) {
                    invokeError(error, positionError(2, "Geolocation is unavailable"));
                }
            });
        return watchID;
    };

    const clearWatch = (watchID) => {
        const requestID = `${frameNonce}:${Number(watchID)}`;
        if (!apply(mapDelete, activeWatches, [requestID])) {
            return;
        }
        callThen(
            callThen(registerFrame(), (enabled) => enabled && postWatch(message("clearWatch", { requestID }))),
            undefined, () => {});
    };

    // Receivers acknowledge ownership. Swift cancels subscriptions when the
    // document token or callback ID no longer matches, including after navigation.
    const receiveWatchResult = (requestID, result) => {
        const callbacks = apply(mapGet, activeWatches, [requestID]);
        if (callbacks) {
            if (!isAllowedByPlatform()) {
                apply(mapDelete, activeWatches, [requestID]);
                callThen(postWatch(message("clearWatch", { requestID })), undefined, () => {});
                invokeError(callbacks.error, deniedError());
                return false;
            }
            settlePosition(result, callbacks.success, callbacks.error);
            return true;
        }
        return false;
    };

    const receiveTerminalWatchResult = (requestID, result) => {
        const callbacks = apply(mapGet, activeWatches, [requestID]);
        if (callbacks) {
            apply(mapDelete, activeWatches, [requestID]);
            if (isAllowedByPlatform()) {
                settlePosition(result, callbacks.success, callbacks.error);
            } else {
                invokeError(callbacks.error, deniedError());
            }
            return true;
        }
        return false;
    };

    const receivePermissionState = (statusID, state) => {
        const record = apply(mapGet, permissionStatuses, [statusID]);
        if (record) {
            record.update(isAllowedByPlatform() ? state : "denied");
            return true;
        }
        return false;
    };

    const shim = Object.freeze({ getCurrentPosition, watchPosition, clearWatch });
    const permissionsQuery = function (descriptor) {
        if (descriptor?.name !== "geolocation" && typeof nativePermissionsQuery === "function") {
            return nativePermissionsQuery.call(nativePermissions, descriptor);
        }
        if (descriptor?.name !== "geolocation" || !isContextEligible()) {
            const record = permissionStatus();
            record.initialize("denied");
            return Promise.resolve(record.status);
        }
        const statusID = `${frameNonce}:${nextPermissionStatusID++}`;
        const record = permissionStatus();
        apply(mapSet, permissionStatuses, [statusID, record]);
        return callThen(
            callThen(registerFrame(), (enabled) => enabled && isAllowedByPlatform()
                ? postOneShot(message("queryPermission", { statusID }))
                : null),
            (result) => {
                if (result?.status !== "permission") {
                    apply(mapDelete, permissionStatuses, [statusID]);
                }
                record.initialize(isAllowedByPlatform() ? normalizedPermissionState(result?.state) : "denied");
                return record.status;
            }, () => {
                apply(mapDelete, permissionStatuses, [statusID]);
                record.initialize("denied");
                return record.status;
            });
    };

    const lockValue = (target, name, value) => {
        if (!target) {
            return false;
        }
        try {
            Object.defineProperty(target, name, {
                configurable: false,
                enumerable: false,
                writable: false,
                value
            });
            return target[name] === value;
        } catch (_) {
            return false;
        }
    };

    // Replace instances and prototypes so a page cannot recover the original API
    // through its prototype. Locked properties keep the replacement in place.
    const installShim = () => {
        const nativeGeolocationPrototype = nativeGeolocation && Object.getPrototypeOf(nativeGeolocation);
        const geolocationPrototypeLocked = !nativeGeolocation || [
            ["getCurrentPosition", getCurrentPosition],
            ["watchPosition", watchPosition],
            ["clearWatch", clearWatch]
        ].every(([name, value]) => lockValue(nativeGeolocationPrototype, name, value));
        const navigatorPrototypeLocked = lockValue(globalThis.Navigator?.prototype, "geolocation", shim);
        const navigatorLocked = lockValue(navigator, "geolocation", shim);
        const permissionsPrototypeLocked = !nativePermissions || lockValue(Object.getPrototypeOf(nativePermissions), "query", permissionsQuery);
        const permissionsLocked = !nativePermissions || lockValue(nativePermissions, "query", permissionsQuery);

        if (!(navigatorLocked && (geolocationPrototypeLocked || navigatorPrototypeLocked) &&
              permissionsPrototypeLocked && permissionsLocked)) {
            return false;
        }

        Object.defineProperty(globalThis, "__ddgSitePermissionsGeolocation", {
            configurable: false,
            value: freeze({ documentID: frameNonce, receiveWatchResult, receiveTerminalWatchResult, receivePermissionState })
        });
        return true;
    };

    if (installImmediately) {
        installShim();
    }

    callThen(registration, (enabled) => {
        if (enabled && !installImmediately) {
            installShim();
        }
    }, () => {});
})();
