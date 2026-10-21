// Delays a website's getUserMedia call so DuckDuckGo can ask for site permission first.
// WebKit can request iOS camera/microphone authorization before calling WKUIDelegate's
// media-permission method, so that delegate alone cannot provide the required prompt order.
//
// This script runs at document start in each frame's page world. It sends the requested
// types and frame eligibility to MediaCaptureUserScript, then waits for Swift's reply.
// Swift owns the saved choices, dialogs, and OS authorization. It records a short-lived
// approval before replying allow. We then call WebKit, and TabViewController consumes that
// approval in the later WKUIDelegate callback. A bypass reply restores WebKit's
// flow when the feature is off or the native handler selects the Duck.ai exception.
//
// Keep message fields in sync with MediaCaptureUserScript.swift. Verify changes with
// MediaCaptureUserScriptTests in the iOS Browser scheme, including flag transitions.
(() => {
    // Save native methods before page scripts can replace them.
    const apply = Reflect.apply;
    const getPrototypeOf = Object.getPrototypeOf;
    const getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
    const defineProperty = Object.defineProperty;
    const toBoolean = Boolean;
    const rejectPromise = Promise.reject.bind(Promise);
    const callThen = Function.prototype.call.bind(Promise.prototype.then);
    const NativeDOMException = DOMException;
    const mediaDevices = navigator.mediaDevices;
    const prototype = mediaDevices && apply(getPrototypeOf, Object, [mediaDevices]);
    const descriptor = prototype && apply(getOwnPropertyDescriptor, Object, [prototype, "getUserMedia"]);
    const nativeGetUserMedia = descriptor && descriptor.value;
    const handler = globalThis.webkit?.messageHandlers?.sitePermissionsMediaCapture;
    const postMessage = handler?.postMessage?.bind(handler);

    if (typeof nativeGetUserMedia !== "function" || typeof postMessage !== "function") {
        return;
    }

    const capability = "${CAPABILITY_TOKEN}";
    const randomToken = () => Array.from(
        crypto.getRandomValues(new Uint8Array(16)),
        byte => byte.toString(16).padStart(2, "0")
    ).join("");
    const nonce = randomToken();
    const origin = globalThis.origin;
    const locationProtocol = globalThis.location.protocol;
    const isSecureContext = globalThis.isSecureContext === true;
    const hostname = globalThis.location.hostname.toLowerCase();
    const isDuckAIHost = hostname === "duck.ai" || hostname === "duckduckgo.com" || hostname.endsWith(".duckduckgo.com");
    const hasNonOpaqueOrigin = origin !== "null" && origin.length > 0;
    const isSyntheticDocument = locationProtocol === "about:";
    const isSameOriginAsTopLevel = (() => {
        if (globalThis.top === globalThis) {
            return true;
        }
        try {
            return globalThis.top.location.origin === origin;
        } catch (_) {
            return false;
        }
    })();
    // WebKit owns each document's effective sandbox restrictions, including after navigation.
    // An allow-same-origin sandbox may request media; opaque origins are marked ineligible.
    const permissionsPolicy = document.permissionsPolicy ?? document.featurePolicy;
    const allowsFeature = permissionsPolicy?.allowsFeature;
    const hasPolicyIntrospection = typeof allowsFeature === "function";
    const inheritedPolicyProperty = "__ddgMediaCapturePolicy";
    // Some WebKit versions don't expose whether an embedded page (iframe) may use media.
    // Fall back to its HTML allow attribute and retain the parent's restrictions for nested
    // frames. This is a best-effort precheck; WebKit makes the final capture decision.
    const fallbackPolicyAllows = (feature) => {
        if (!isSameOriginAsTopLevel) {
            return false;
        }
        if (globalThis.top === globalThis) {
            return true;
        }
        try {
            const parent = globalThis.parent;
            const inheritedPolicy = parent[inheritedPolicyProperty];
            if (typeof inheritedPolicy !== "function" || !inheritedPolicy(feature)) {
                return false;
            }
            const frame = globalThis.frameElement;
            if (!frame) {
                return false;
            }
            const getAttribute = Element.prototype.getAttribute;
            const policy = apply(getAttribute, frame, ["allow"]) ?? "";
            const source = apply(getAttribute, frame, ["src"]);
            let sourceOrigin = parent.location.origin;
            if (source !== null && apply(getAttribute, frame, ["srcdoc"]) === null) {
                try {
                    const baseURIGetter = getOwnPropertyDescriptor(Node.prototype, "baseURI").get;
                    const sourceURL = new URL(source, apply(baseURIGetter, frame, []));
                    sourceOrigin = sourceURL.protocol === "http:" || sourceURL.protocol === "https:"
                        ? sourceURL.origin : origin;
                } catch (_) {}
            }
            for (const directive of policy.split(";")) {
                const value = directive.trim();
                if (!value.startsWith(feature)) {
                    continue;
                }
                // WebKit also accepts the legacy colon separator after a feature name.
                const allowlist = value.slice(feature.length).replace(/^:/, "").trim();
                if (!allowlist) {
                    return sourceOrigin === origin;
                }
                let allowed = false;
                for (const token of allowlist.split(/[\t\n\f\r ]+/)) {
                    if (token === "*") {
                        return true;
                    }
                    if (token.toLowerCase() === "'none'") {
                        return false;
                    }
                    if (token.toLowerCase() === "'self'") {
                        allowed ||= parent.location.origin === origin;
                    } else if (token.toLowerCase() === "'src'") {
                        allowed ||= sourceOrigin === origin;
                    } else {
                        try {
                            allowed ||= new URL(token).origin === origin;
                        } catch (_) {}
                    }
                }
                return allowed;
            }
            return true;
        } catch (_) {
            return false;
        }
    };
    const fallbackCameraAllowed = fallbackPolicyAllows("camera");
    const fallbackMicrophoneAllowed = fallbackPolicyAllows("microphone");
    const policyAllows = (feature) => {
        if (!hasPolicyIntrospection) {
            return feature === "camera" ? fallbackCameraAllowed : fallbackMicrophoneAllowed;
        }
        try {
            return toBoolean(apply(allowsFeature, permissionsPolicy, [feature]));
        } catch (_) {
            return false;
        }
    };
    apply(defineProperty, Object, [globalThis, inheritedPolicyProperty, { value: policyAllows }]);
    let nextRequestID = 0;

    const permissionDenied = () => new NativeDOMException("Permission denied", "NotAllowedError");
    const getUserMedia = function(constraints) {
        if (constraints === null ||
            (typeof constraints !== "object" && typeof constraints !== "function")) {
            return apply(nativeGetUserMedia, this, arguments);
        }

        let rawVideo;
        let rawAudio;
        // Read getters once so Swift approves the same media types that WebKit receives.
        try {
            rawVideo = constraints.video;
            rawAudio = constraints.audio;
        } catch (error) {
            return rejectPromise(error);
        }

        const video = toBoolean(rawVideo);
        const audio = toBoolean(rawAudio);
        const capturedConstraints = { video: rawVideo, audio: rawAudio };
        if (!video && !audio) {
            return apply(nativeGetUserMedia, this, [capturedConstraints]);
        }

        // Send ineligible requests too: Swift checks rollback before denying custom-flow requests.
        const isEligibleContext = this === mediaDevices && hasNonOpaqueOrigin && (isDuckAIHost || (isSecureContext &&
            !isSyntheticDocument &&
            (!video || policyAllows("camera")) &&
            (!audio || policyAllows("microphone"))));

        nextRequestID += 1;
        let bridgePromise;
        try {
            bridgePromise = postMessage({
                capability,
                requestID: `${nonce}:${nextRequestID}`,
                isEligible: isEligibleContext,
                video,
                audio
            });
        } catch (_) {
            return rejectPromise(permissionDenied());
        }

        return callThen(bridgePromise, reply => {
            if (reply && (reply.decision === "allow" || reply.decision === "bypass")) {
                return apply(nativeGetUserMedia, this, [capturedConstraints]);
            }
            throw permissionDenied();
        }, () => {
            throw permissionDenied();
        });
    };

    apply(defineProperty, Object, [prototype, "getUserMedia", {
        ...descriptor,
        value: getUserMedia
    }]);
})();
