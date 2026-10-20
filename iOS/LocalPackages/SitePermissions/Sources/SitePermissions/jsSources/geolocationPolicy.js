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
 * Evaluates document policy in the app's isolated content world. A subframe
 * asks its parent's copy of this script about its embedding element directly,
 * so the page never observes these checks.
 */
(() => {
    if (globalThis.__ddgSitePermissionsGeolocationPolicy) {
        return;
    }
    const apply = globalThis.Reflect.apply;
    const querySelectorAll = globalThis.Document?.prototype?.querySelectorAll;
    const elementQuerySelectorAll = globalThis.Element?.prototype?.querySelectorAll;
    const elementMatches = globalThis.Element?.prototype?.matches;
    const hasAttribute = globalThis.Element?.prototype?.hasAttribute;
    const getAttribute = globalThis.Element?.prototype?.getAttribute;
    const baseURI = Object.getOwnPropertyDescriptor(globalThis.Node?.prototype ?? {}, "baseURI")?.get;
    const nodeListLength = Object.getOwnPropertyDescriptor(globalThis.NodeList?.prototype ?? {}, "length")?.get;
    const nodeListItem = globalThis.NodeList?.prototype?.item;
    const weakSetAdd = globalThis.WeakSet.prototype.add;
    const weakSetHas = globalThis.WeakSet.prototype.has;
    const NativeURL = globalThis.URL;
    const NativeMutationObserver = globalThis.MutationObserver;
    const observeMutations = NativeMutationObserver?.prototype?.observe;
    const mutationRecordPrototype = globalThis.MutationRecord?.prototype ?? {};
    const mutationRecordType = Object.getOwnPropertyDescriptor(mutationRecordPrototype, "type")?.get;
    const mutationRecordTarget = Object.getOwnPropertyDescriptor(mutationRecordPrototype, "target")?.get;
    const mutationRecordAttributeName = Object.getOwnPropertyDescriptor(mutationRecordPrototype, "attributeName")?.get;
    const mutationRecordOldValue = Object.getOwnPropertyDescriptor(mutationRecordPrototype, "oldValue")?.get;
    const mutationRecordAddedNodes = Object.getOwnPropertyDescriptor(mutationRecordPrototype, "addedNodes")?.get;
    const freeze = globalThis.Object.freeze;
    const randomToken = () => {
        if (typeof globalThis.crypto?.getRandomValues !== "function") {
            return null;
        }
        const values = new Uint32Array(4);
        globalThis.crypto.getRandomValues(values);
        return Array.from(values, (value) => value.toString(16).padStart(8, "0")).join("");
    };
    const documentID = randomToken();

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

    const parentWindow = globalThis.parent;
    const documentOrigin = globalThis.origin;
    const hasOpaqueOrigin = documentOrigin === "null";
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
    // Remember observed restrictions so a later check cannot overlook them.
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

    const sourceOrigin = (element, childOrigin) => {
        const source = apply(getAttribute, element, ["src"]);
        if (source === null || apply(getAttribute, element, ["srcdoc"]) !== null) {
            return documentOrigin;
        }
        try {
            const url = new NativeURL(source, apply(baseURI, element, []));
            return url.protocol === "http:" || url.protocol === "https:" ? url.origin : childOrigin;
        } catch (_) {
            return documentOrigin;
        }
    };

    // Evaluates the iframe allow attribute like WebKit's container policy. Without a
    // geolocation directive, the default allowlist is 'self'. A same-origin frame can
    // already reach its parent's API, so the current attribute is enough here.
    const allowAttributeAllowsGeolocation = (element, childOrigin) => {
        const directives = (apply(getAttribute, element, ["allow"]) ?? "").split(";");
        for (const directive of directives) {
            const value = directive.trim();
            const name = value.split(/[\t\n\f\r :]/, 1)[0];
            if (name !== "geolocation") {
                continue;
            }
            // WebKit also accepts the legacy colon separator after a feature name.
            const allowlist = value.slice(name.length).replace(/^:/, "").trim();
            if (!allowlist) {
                return sourceOrigin(element, childOrigin) === childOrigin;
            }
            let allowed = false;
            for (const token of allowlist.split(/[\t\n\f\r ]+/)) {
                const keyword = token.toLowerCase();
                if (token === "*") {
                    return true;
                }
                if (keyword === "'none'") {
                    return false;
                }
                if (keyword === "'self'") {
                    allowed ||= documentOrigin === childOrigin;
                } else if (keyword === "'src'") {
                    allowed ||= sourceOrigin(element, childOrigin) === childOrigin;
                } else {
                    try {
                        allowed ||= new NativeURL(token).origin === childOrigin;
                    } catch (_) {}
                }
            }
            return allowed;
        }
        return documentOrigin === childOrigin;
    };

    // A cross-origin parent hides frameElement, so its descendants fail closed, as
    // do frames whose parent lacks this script. Native code checks the top-level
    // response policy.
    const documentVerdict = () => {
        if (parentWindow === globalThis) {
            return freeze({ isSandboxed: hasOpaqueOrigin, isPolicyAllowed: true });
        }
        try {
            const element = globalThis.frameElement;
            const parentPolicy = parentWindow.__ddgSitePermissionsGeolocationPolicy;
            if (element && typeof parentPolicy?.embeddedFrameVerdict === "function") {
                const verdict = parentPolicy.embeddedFrameVerdict(element, documentOrigin);
                return freeze({
                    isSandboxed: hasOpaqueOrigin || verdict.isSandboxed !== false,
                    isPolicyAllowed: verdict.isPolicyAllowed === true
                });
            }
        } catch (_) {}
        return freeze({ isSandboxed: true, isPolicyAllowed: false });
    };

    // Called by a child frame's copy of this script, with the child's frameElement.
    const embeddedFrameVerdict = (element, childOrigin) => {
        const ownVerdict = documentVerdict();
        let isSandboxed = true;
        let isPolicyAllowed = false;
        try {
            if (apply(elementMatches, element, ["iframe,frame"])) {
                isSandboxed = !sandboxHistoryAvailable ||
                    apply(weakSetHas, sandboxedEmbeddingFrames, [element]) ||
                    apply(hasAttribute, element, ["sandbox"]);
                isPolicyAllowed = allowAttributeAllowsGeolocation(element, childOrigin);
            }
        } catch (_) {}
        return freeze({
            isSandboxed: ownVerdict.isSandboxed || isSandboxed,
            isPolicyAllowed: ownVerdict.isPolicyAllowed && isPolicyAllowed
        });
    };

    const policyAllowsGeolocation = (verdict) => {
        try {
            if (typeof nativePolicyAllowsFeature === "function") {
                return apply(nativePolicyAllowsFeature, nativePermissionsPolicy, ["geolocation"]);
            }
            return verdict.isPolicyAllowed;
        } catch (_) {
            return false;
        }
    };

    const isSecureContext = globalThis.isSecureContext === true;
    const isFramePolicyEligible = hasNetworkOrigin && isSameOriginAsTopLevel;
    const getConstraints = () => {
        const verdict = documentVerdict();
        return freeze({
            documentID,
            isSecureContext,
            isPolicyAllowed: documentID !== null && isFramePolicyEligible && policyAllowsGeolocation(verdict),
            isSandboxed: verdict.isSandboxed
        });
    };

    Object.defineProperty(globalThis, "__ddgSitePermissionsGeolocationPolicy", {
        configurable: false,
        value: freeze({ documentID, getConstraints, embeddedFrameVerdict })
    });
})();
