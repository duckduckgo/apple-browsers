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
 * Evaluates document policy in the app's isolated content world. Signing state
 * and asynchronous sandbox verdicts never enter the page's JavaScript realm.
 */
(() => {
    if (globalThis.__ddgSitePermissionsGeolocationPolicy) {
        return;
    }
    const callThen = Function.prototype.call.bind(Promise.prototype.then);
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
    const signingToken = "${SIGNING_TOKEN}";
    const randomToken = () => {
        if (typeof globalThis.crypto?.getRandomValues !== "function") {
            return null;
        }
        const values = new Uint32Array(4);
        globalThis.crypto.getRandomValues(values);
        return Array.from(values, (value) => value.toString(16).padStart(8, "0")).join("");
    };
    const nonce = randomToken();
    const documentID = randomToken();

    const textEncoder = globalThis.TextEncoder ? new globalThis.TextEncoder() : null;
    const encodeText = textEncoder?.encode.bind(textEncoder);
    const subtleCrypto = globalThis.crypto?.subtle;
    const importHMACKey = subtleCrypto?.importKey.bind(subtleCrypto);
    const signHMAC = subtleCrypto?.sign.bind(subtleCrypto);
    const NativeUint8Array = globalThis.Uint8Array;
    const hmacKey = importHMACKey && encodeText
        ? callThen(importHMACKey("raw", encodeText(signingToken), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]), undefined, () => null)
        : Promise.resolve(null);
    const numberToString = globalThis.Number.prototype.toString;
    const noncePattern = /^[0-9a-f]{32}$/;
    const testPattern = globalThis.RegExp.prototype.test;

    // This entire Promise graph belongs to the isolated content world.
    const signSandboxProbe = (value, completion) => {
        callThen(hmacKey, (key) => {
            if (!key || !signHMAC || !encodeText) {
                completion(null);
                return;
            }
            try {
                callThen(signHMAC("HMAC", key, encodeText(value)), (signature) => {
                    const bytes = new NativeUint8Array(signature);
                    let result = "";
                    for (let index = 0; index < 32; index++) {
                        const hex = apply(numberToString, bytes[index], [16]);
                        result += bytes[index] < 16 ? `0${hex}` : hex;
                    }
                    completion(result);
                }, () => completion(null));
            } catch (_) {
                completion(null);
            }
        }, () => completion(null));
    };

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

    // A child cannot reliably inspect its embedding element. Parent and child
    // scripts exchange signed sandbox verdicts, including ancestor restrictions.
    // Signing authenticates these public messages without exposing the signing key.
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

    // Removing a sandbox attribute does not unsandbox the current document.
    // Remember observed restrictions so a later probe cannot overlook them.
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
    // Missing or unverifiable parent replies deny access after the timeout.
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

    const handleSandboxProbeMessage = (event) => {
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
                signSandboxProbe(sandboxResponseValue(childNonce, reportedSandboxed), (expectedProof) => {
                    if (expectedProof !== null && childNonce === nonce && proof === expectedProof) {
                        finishSandboxProbe(reportedSandboxed);
                    }
                });
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
            const clearPendingSource = () => { apply(mapDelete, pendingSandboxProbeSources, [childNonce]); };
            signSandboxProbe(sandboxRequestValue(childNonce), (expectedProof) => {
                if (expectedProof === null || proof !== expectedProof) {
                    clearPendingSource();
                    return;
                }
                try {
                    callThen(sandboxVerdict, (ancestorSandboxed) => {
                        const sandboxed = ancestorSandboxed || directlySandboxed;
                        signSandboxProbe(sandboxResponseValue(childNonce, sandboxed), (responseProof) => {
                            clearPendingSource();
                            if (responseProof !== null) {
                                try {
                                    apply(postWindowMessage, source, [{
                                        channel: sandboxProbeChannel,
                                        kind: "response",
                                        nonce: childNonce,
                                        sandboxed,
                                        proof: responseProof
                                    }, "*"]);
                                } catch (_) {}
                            }
                        });
                    }, clearPendingSource);
                } catch (_) {
                    clearPendingSource();
                }
            });
        } catch (_) {}
    };

    apply(addWindowEventListener, globalThis, ["message", (event) => {
        handleSandboxProbeMessage(event);
    }, false]);

    if (parentWindow !== globalThis) {
        try {
            if (nonce === null) {
                finishSandboxProbe(true);
            } else {
                signSandboxProbe(sandboxRequestValue(nonce), (proof) => {
                    if (proof === null) {
                        finishSandboxProbe(true);
                        return;
                    }
                    try {
                        apply(postWindowMessage, parentWindow, [{
                            channel: sandboxProbeChannel,
                            kind: "request",
                            nonce,
                            proof
                        }, "*"]);
                    } catch (_) {
                        finishSandboxProbe(true);
                    }
                });
            }
        } catch (_) {
            finishSandboxProbe(true);
        }
    }

    const isSecureContext = globalThis.isSecureContext === true;
    const isFramePolicyEligible = hasNetworkOrigin && isSameOriginAsTopLevel;
    const getConstraints = () => {
        const requestedDocumentID = documentID;
        return callThen(sandboxVerdict, (isSandboxed) => freeze({
            documentID: requestedDocumentID,
            isSecureContext,
            isPolicyAllowed: requestedDocumentID !== null && isFramePolicyEligible && policyAllowsGeolocation(),
            isSandboxed
        }));
    };

    Object.defineProperty(globalThis, "__ddgSitePermissionsGeolocationPolicy", {
        configurable: false,
        value: freeze({ documentID, getConstraints })
    });
})();
