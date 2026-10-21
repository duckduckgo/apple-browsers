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
    const elementMatches = globalThis.Element?.prototype?.matches;
    const getAttribute = globalThis.Element?.prototype?.getAttribute;
    const baseURI = Object.getOwnPropertyDescriptor(globalThis.Node?.prototype ?? {}, "baseURI")?.get;
    const NativeURL = globalThis.URL;
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
    // Like WebKit, only a sandbox that makes the origin opaque blocks geolocation.
    // hasNetworkOrigin already rejects an opaque origin, so this flag never changes
    // the verdict by itself. It reports the same fact to native code, which needs it.
    const isSandboxed = documentOrigin === "null";

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
            // Like WebKit, the feature name is a case-sensitive prefix and the first
            // directive for it wins.
            const value = directive.trim();
            if (!value.startsWith("geolocation")) {
                continue;
            }
            const allowlist = value.slice("geolocation".length).trim();
            if (!allowlist) {
                return sourceOrigin(element, childOrigin) === childOrigin;
            }
            // Like WebKit, the first * or 'none' decides.
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
    const documentPolicyAllowed = () => {
        if (parentWindow === globalThis) {
            return true;
        }
        try {
            const element = globalThis.frameElement;
            const parentPolicy = parentWindow.__ddgSitePermissionsGeolocationPolicy;
            if (element && typeof parentPolicy?.embeddedFrameAllowed === "function") {
                return parentPolicy.embeddedFrameAllowed(element, documentOrigin) === true;
            }
        } catch (_) {}
        return false;
    };

    // Called by a child frame's copy of this script, with the child's frameElement.
    const embeddedFrameAllowed = (element, childOrigin) => {
        try {
            return documentPolicyAllowed() &&
                apply(elementMatches, element, ["iframe,frame"]) &&
                allowAttributeAllowsGeolocation(element, childOrigin);
        } catch (_) {
            return false;
        }
    };

    const policyAllowsGeolocation = () => {
        try {
            if (typeof nativePolicyAllowsFeature === "function") {
                return apply(nativePolicyAllowsFeature, nativePermissionsPolicy, ["geolocation"]);
            }
            return documentPolicyAllowed();
        } catch (_) {
            return false;
        }
    };

    const isSecureContext = globalThis.isSecureContext === true;
    const isFramePolicyEligible = hasNetworkOrigin && isSameOriginAsTopLevel;
    const getConstraints = () => freeze({
        documentID,
        isSecureContext,
        isPolicyAllowed: documentID !== null && isFramePolicyEligible && policyAllowsGeolocation(),
        isSandboxed
    });

    Object.defineProperty(globalThis, "__ddgSitePermissionsGeolocationPolicy", {
        configurable: false,
        value: freeze({ documentID, getConstraints, embeddedFrameAllowed })
    });
})();
