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

(() => {
    const oneShotHandler = globalThis.webkit?.messageHandlers?.sitePermissionsGeolocation;
    const watchHandler = globalThis.webkit?.messageHandlers?.sitePermissionsGeolocationWatch;
    if (!oneShotHandler || !watchHandler || globalThis.__ddgSitePermissionsGeolocation) {
        return;
    }

    const postOneShot = oneShotHandler.postMessage.bind(oneShotHandler);
    const postWatch = watchHandler.postMessage.bind(watchHandler);
    const scheduleTask = globalThis.setTimeout.bind(globalThis);
    const cancelTask = globalThis.clearTimeout.bind(globalThis);
    const apply = globalThis.Reflect.apply;
    const addWindowEventListener = globalThis.addEventListener;
    const postWindowMessage = globalThis.postMessage;
    const querySelectorAll = globalThis.Document?.prototype?.querySelectorAll;
    const elementQuerySelectorAll = globalThis.Element?.prototype?.querySelectorAll;
    const elementMatches = globalThis.Element?.prototype?.matches;
    const hasAttribute = globalThis.Element?.prototype?.hasAttribute;
    const nodeListLength = Object.getOwnPropertyDescriptor(globalThis.NodeList?.prototype ?? {}, "length")?.get;
    const nodeListItem = globalThis.NodeList?.prototype?.item;
    const mapGet = globalThis.Map.prototype.get;
    const mapSet = globalThis.Map.prototype.set;
    const mapDelete = globalThis.Map.prototype.delete;
    const weakSetAdd = globalThis.WeakSet.prototype.add;
    const weakSetHas = globalThis.WeakSet.prototype.has;
    const NativeMutationObserver = globalThis.MutationObserver;
    const observeMutations = NativeMutationObserver?.prototype?.observe;
    const mutationRecordPrototype = globalThis.MutationRecord?.prototype ?? {};
    const mutationRecordType = Object.getOwnPropertyDescriptor(mutationRecordPrototype, "type")?.get;
    const mutationRecordTarget = Object.getOwnPropertyDescriptor(mutationRecordPrototype, "target")?.get;
    const mutationRecordAttributeName = Object.getOwnPropertyDescriptor(mutationRecordPrototype, "attributeName")?.get;
    const mutationRecordOldValue = Object.getOwnPropertyDescriptor(mutationRecordPrototype, "oldValue")?.get;
    const mutationRecordAddedNodes = Object.getOwnPropertyDescriptor(mutationRecordPrototype, "addedNodes")?.get;
    const freeze = globalThis.Object.freeze;
    const contentWindowGetters = [
        Object.getOwnPropertyDescriptor(globalThis.HTMLIFrameElement?.prototype ?? {}, "contentWindow")?.get,
        Object.getOwnPropertyDescriptor(globalThis.HTMLFrameElement?.prototype ?? {}, "contentWindow")?.get
    ].filter(Boolean);
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
    const randomToken = () => {
        if (typeof globalThis.crypto?.getRandomValues !== "function") {
            return null;
        }
        const values = new Uint32Array(4);
        globalThis.crypto.getRandomValues(values);
        return Array.from(values, (value) => value.toString(16).padStart(8, "0")).join("");
    };
    const nonce = randomToken();
    const frameNonce = randomToken() ?? "unavailable";
    let nextWatchID = 1;

    const textEncoder = globalThis.TextEncoder ? new globalThis.TextEncoder() : null;
    const encodeText = textEncoder?.encode.bind(textEncoder);
    const subtleCrypto = globalThis.crypto?.subtle;
    const importHMACKey = subtleCrypto?.importKey.bind(subtleCrypto);
    const signHMAC = subtleCrypto?.sign.bind(subtleCrypto);
    const NativeUint8Array = globalThis.Uint8Array;
    const hmacKey = importHMACKey && encodeText
        ? importHMACKey("raw", encodeText(capability), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]).catch(() => null)
        : Promise.resolve(null);
    const numberToString = globalThis.Number.prototype.toString;
    const noncePattern = /^[0-9a-f]{32}$/;
    const testPattern = globalThis.RegExp.prototype.test;

    const signSandboxProbe = async (value) => {
        const key = await hmacKey;
        if (!key || !signHMAC || !encodeText) {
            return null;
        }
        const signature = await signHMAC("HMAC", key, encodeText(value));
        const bytes = new NativeUint8Array(signature);
        let result = "";
        for (let index = 0; index < 32; index++) {
            const hex = apply(numberToString, bytes[index], [16]);
            result += bytes[index] < 16 ? `0${hex}` : hex;
        }
        return result;
    };

    // WebKit does not currently expose Permissions Policy introspection on every
    // supported OS. V1 therefore applies the platform's `self` default itself:
    // top-level and same-origin frames may continue, while every cross-origin
    // frame is denied. This deliberately excludes delegated cross-origin frames
    // until an OS-managed API can enforce their full policy chain reliably.
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
            return true;
        } catch (_) {
            return false;
        }
    };

    const sandboxProbeChannel = "ddg-site-permissions-geolocation-sandbox";
    const sandboxRequestValue = (childNonce) => `${sandboxProbeChannel}:request:${childNonce}`;
    const sandboxResponseValue = (childNonce, sandboxed) =>
        `${sandboxProbeChannel}:response:${childNonce}:${sandboxed ? "1" : "0"}`;
    const parentWindow = globalThis.parent;
    const hasOpaqueOrigin = globalThis.origin === "null";
    const pendingSandboxProbeSources = new Map();
    const sandboxedEmbeddingFrames = new WeakSet();

    const rememberSandboxedFrame = (element, force = false) => {
        try {
            if (apply(elementMatches, element, ["iframe,frame"]) &&
                (force || apply(hasAttribute, element, ["sandbox"]))) {
                apply(weakSetAdd, sandboxedEmbeddingFrames, [element]);
            }
        } catch (_) {}
    };

    const rememberSandboxedFrames = (root) => {
        rememberSandboxedFrame(root);
        if (!elementQuerySelectorAll || !nodeListLength || !nodeListItem) {
            return;
        }
        try {
            const elements = apply(elementQuerySelectorAll, root, ["iframe[sandbox],frame[sandbox]"]);
            const elementCount = apply(nodeListLength, elements, []);
            for (let index = 0; index < elementCount; index++) {
                rememberSandboxedFrame(apply(nodeListItem, elements, [index]), true);
            }
        } catch (_) {}
    };

    let sandboxHistoryAvailable = false;
    let sandboxHistoryObserver;
    if (NativeMutationObserver && observeMutations && elementMatches && hasAttribute &&
        mutationRecordType && mutationRecordTarget && mutationRecordAttributeName &&
        mutationRecordOldValue && mutationRecordAddedNodes) {
        try {
            sandboxHistoryObserver = new NativeMutationObserver((records) => {
                for (let recordIndex = 0; recordIndex < records.length; recordIndex++) {
                    const record = records[recordIndex];
                    const recordType = apply(mutationRecordType, record, []);
                    if (recordType === "attributes" && apply(mutationRecordAttributeName, record, []) === "sandbox") {
                        const target = apply(mutationRecordTarget, record, []);
                        if (apply(mutationRecordOldValue, record, []) !== null || apply(hasAttribute, target, ["sandbox"])) {
                            rememberSandboxedFrame(target, true);
                        }
                    } else if (recordType === "childList") {
                        const addedNodes = apply(mutationRecordAddedNodes, record, []);
                        const addedNodeCount = apply(nodeListLength, addedNodes, []);
                        for (let nodeIndex = 0; nodeIndex < addedNodeCount; nodeIndex++) {
                            rememberSandboxedFrames(apply(nodeListItem, addedNodes, [nodeIndex]));
                        }
                    }
                }
            });
            apply(observeMutations, sandboxHistoryObserver, [document, {
                attributes: true,
                attributeFilter: ["sandbox"],
                attributeOldValue: true,
                childList: true,
                subtree: true
            }]);
            sandboxHistoryAvailable = true;
            const existingFrames = apply(querySelectorAll, document, ["iframe[sandbox],frame[sandbox]"]);
            const existingFrameCount = apply(nodeListLength, existingFrames, []);
            for (let index = 0; index < existingFrameCount; index++) {
                rememberSandboxedFrame(apply(nodeListItem, existingFrames, [index]), true);
            }
        } catch (_) {}
    }

    const embeddingFrameForSource = (source) => {
        if (!source || !querySelectorAll || !hasAttribute || !nodeListLength || !nodeListItem || contentWindowGetters.length === 0) {
            return null;
        }
        const elements = apply(querySelectorAll, document, ["iframe,frame"]);
        const elementCount = apply(nodeListLength, elements, []);
        for (let index = 0; index < elementCount; index++) {
            const element = apply(nodeListItem, elements, [index]);
            for (let getterIndex = 0; getterIndex < contentWindowGetters.length; getterIndex++) {
                try {
                    if (apply(contentWindowGetters[getterIndex], element, []) === source) {
                        return element;
                    }
                } catch (_) {}
            }
        }
        return null;
    };

    let finishSandboxProbe;
    let sandboxProbeTimeout;
    const sandboxVerdict = parentWindow === globalThis
        ? Promise.resolve(hasOpaqueOrigin)
        : new Promise((resolve) => {
            let finished = false;
            finishSandboxProbe = (sandboxed) => {
                if (finished) {
                    return;
                }
                finished = true;
                cancelTask(sandboxProbeTimeout);
                resolve(sandboxed || hasOpaqueOrigin);
            };
            sandboxProbeTimeout = scheduleTask(() => finishSandboxProbe(true), 1_000);
        });

    const handleSandboxProbeMessage = async (event) => {
        try {
            const data = event.data;
            const source = event.source;
            const kind = data?.kind;
            const childNonce = data?.nonce;
            const proof = data?.proof;
            const reportedSandboxed = data?.sandboxed;
            if (data?.channel !== sandboxProbeChannel ||
                typeof childNonce !== "string" ||
                !apply(testPattern, noncePattern, [childNonce])) {
                return;
            }

            if (kind === "response") {
                if (source !== parentWindow ||
                    typeof reportedSandboxed !== "boolean" ||
                    typeof proof !== "string" || proof.length !== 64 ||
                    !finishSandboxProbe) {
                    return;
                }
                const expectedProof = await signSandboxProbe(sandboxResponseValue(childNonce, reportedSandboxed));
                if (expectedProof !== null && childNonce === nonce && proof === expectedProof) {
                    finishSandboxProbe(reportedSandboxed);
                }
                return;
            }

            if (kind !== "request" || typeof proof !== "string" || proof.length !== 64) {
                return;
            }
            const pinnedSource = apply(mapGet, pendingSandboxProbeSources, [childNonce]);
            if (pinnedSource && pinnedSource !== source) {
                return;
            }
            const embeddingFrame = embeddingFrameForSource(source);
            if (!embeddingFrame) {
                return;
            }
            apply(mapSet, pendingSandboxProbeSources, [childNonce, source]);
            const directlySandboxed = !sandboxHistoryAvailable ||
                apply(weakSetHas, sandboxedEmbeddingFrames, [embeddingFrame]) ||
                apply(hasAttribute, embeddingFrame, ["sandbox"]);
            const expectedProof = await signSandboxProbe(sandboxRequestValue(childNonce));
            if (expectedProof === null || proof !== expectedProof) {
                apply(mapDelete, pendingSandboxProbeSources, [childNonce]);
                return;
            }
            const ancestorSandboxed = await sandboxVerdict;
            const sandboxed = ancestorSandboxed || directlySandboxed;
            const responseProof = await signSandboxProbe(sandboxResponseValue(childNonce, sandboxed));
            if (responseProof !== null) {
                apply(postWindowMessage, source, [{
                    channel: sandboxProbeChannel,
                    kind: "response",
                    nonce: childNonce,
                    sandboxed,
                    proof: responseProof
                }, "*"]);
            }
            apply(mapDelete, pendingSandboxProbeSources, [childNonce]);
        } catch (_) {}
    };

    apply(addWindowEventListener, globalThis, ["message", (event) => {
        void handleSandboxProbeMessage(event);
    }, false]);

    if (parentWindow !== globalThis) {
        void (async () => {
            try {
                if (nonce === null) {
                    finishSandboxProbe(true);
                    return;
                }
                const proof = await signSandboxProbe(sandboxRequestValue(nonce));
                if (proof === null) {
                    finishSandboxProbe(true);
                    return;
                }
                apply(postWindowMessage, parentWindow, [{
                    channel: sandboxProbeChannel,
                    kind: "request",
                    nonce,
                    proof
                }, "*"]);
            } catch (_) {
                finishSandboxProbe(true);
            }
        })();
    }

    const isSecureContext = globalThis.isSecureContext === true;
    const isFramePolicyEligible = hasNetworkOrigin && isSameOriginAsTopLevel;
    const currentConstraints = (isSandboxed) => freeze({
        isSecureContext,
        isPolicyAllowed: isFramePolicyEligible && policyAllowsGeolocation(),
        isSandboxed
    });
    let constraints = currentConstraints(true);

    const isContextEligible = () => nonce !== null && isSecureContext && isFramePolicyEligible;
    const isAllowedByPlatform = () => {
        constraints = currentConstraints(constraints.isSandboxed);
        return isContextEligible() && constraints.isPolicyAllowed && !constraints.isSandboxed;
    };

    const message = (kind, values = {}) => ({ capability, nonce, ...constraints, kind, ...values });

    const registerFrame = () => sandboxVerdict
        .then((isSandboxed) => {
            constraints = currentConstraints(isSandboxed);
            return postOneShot(message("registerFrame"));
        })
        .then((result) => {
            if (result?.status !== "registered") {
                throw new Error("Unable to register geolocation frame");
            }
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

    const positionError = (code, message) => ({ code, message });

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

    const permissionStatus = (state) => {
        const status = new EventTarget();
        Object.defineProperties(status, {
            state: { configurable: false, enumerable: true, value: state },
            onchange: { configurable: true, enumerable: true, writable: true, value: null }
        });
        if (globalThis.PermissionStatus?.prototype) {
            Object.setPrototypeOf(status, globalThis.PermissionStatus.prototype);
        }
        return status;
    };

    const getCurrentPosition = (success, error, options) => {
        if (typeof success !== "function") {
            throw new TypeError("The success callback must be a function");
        }

        if (!isContextEligible()) {
            queueMicrotask(() => invokeError(error, deniedError()));
            return;
        }

        registerFrame().then((enabled) => enabled && isAllowedByPlatform()
            ? postOneShot(message("getCurrentPosition", { options: optionsPayload(options) }))
            : deniedResult())
            .then((result) => settlePosition(isAllowedByPlatform() ? result : deniedResult(), success, error),
                  () => invokeError(error, positionError(2, "Geolocation is unavailable")));
    };

    const watchPosition = (success, error, options) => {
        if (typeof success !== "function") {
            throw new TypeError("The success callback must be a function");
        }

        const watchID = nextWatchID++;
        const requestID = `${frameNonce}:${watchID}`;
        activeWatches.set(requestID, { success, error });

        if (!isContextEligible()) {
            queueMicrotask(() => {
                if (activeWatches.delete(requestID)) {
                    invokeError(error, deniedError());
                }
            });
            return watchID;
        }

        registerFrame().then((enabled) => enabled && isAllowedByPlatform()
            ? postWatch(message("startWatch", { requestID, options: optionsPayload(options) }))
            : deniedResult()).then((result) => {
            if (!activeWatches.has(requestID) && result?.status === "started") {
                postWatch(message("clearWatch", { requestID })).catch(() => {});
                return;
            }
            if (result?.status === "started" && !isAllowedByPlatform()) {
                activeWatches.delete(requestID);
                postWatch(message("clearWatch", { requestID })).catch(() => {});
                invokeError(error, deniedError());
                return;
            }
            if (result?.status === "error" && activeWatches.delete(requestID)) {
                invokeError(error, positionError(result.code ?? 2, result.message ?? "Geolocation is unavailable"));
            }
        }, () => {
            if (activeWatches.delete(requestID)) {
                invokeError(error, positionError(2, "Geolocation is unavailable"));
            }
        });
        return watchID;
    };

    const clearWatch = (watchID) => {
        const requestID = `${frameNonce}:${Number(watchID)}`;
        if (!activeWatches.delete(requestID)) {
            return;
        }
        registerFrame().then((enabled) => enabled &&
            postWatch(message("clearWatch", { requestID }))).catch(() => {});
    };

    const receiveWatchResult = (requestID, result) => {
        const callbacks = activeWatches.get(requestID);
        if (callbacks) {
            if (!isAllowedByPlatform()) {
                activeWatches.delete(requestID);
                postWatch(message("clearWatch", { requestID })).catch(() => {});
                invokeError(callbacks.error, deniedError());
                return;
            }
            settlePosition(result, callbacks.success, callbacks.error);
        }
    };

    const receiveTerminalWatchResult = (requestID, result) => {
        const callbacks = activeWatches.get(requestID);
        if (callbacks) {
            activeWatches.delete(requestID);
            if (isAllowedByPlatform()) {
                settlePosition(result, callbacks.success, callbacks.error);
            } else {
                invokeError(callbacks.error, deniedError());
            }
        }
    };

    const shim = Object.freeze({ getCurrentPosition, watchPosition, clearWatch });
    const permissionsQuery = function (descriptor) {
        if (descriptor?.name !== "geolocation" && typeof nativePermissionsQuery === "function") {
            return nativePermissionsQuery.call(nativePermissions, descriptor);
        }
        if (descriptor?.name !== "geolocation" || !isContextEligible()) {
            return Promise.resolve(permissionStatus("denied"));
        }
        return registerFrame().then((enabled) => enabled && isAllowedByPlatform()
            ? postOneShot(message("queryPermission"))
            : null)
            .then((result) => permissionStatus(isAllowedByPlatform() ? (result?.state ?? "denied") : "denied"),
                  () => permissionStatus("denied"));
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
            value: Object.freeze({ receiveWatchResult, receiveTerminalWatchResult })
        });
        return true;
    };

    if (installImmediately) {
        installShim();
    }

    registration.then((enabled) => {
        if (enabled && !installImmediately) {
            installShim();
        }
    }).catch(() => {});
})();
