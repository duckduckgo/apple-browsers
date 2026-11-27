// Delays a website's getUserMedia call so DuckDuckGo can ask for site permission first.
// WebKit can request iOS camera/microphone authorization before calling WKUIDelegate's
// media-permission method, so that delegate alone cannot provide the required prompt order.
//
// This script runs at document start in each frame's page world. It sends the requested
// types and frame eligibility to MediaCaptureUserScript, then waits for Swift's reply.
// Swift owns the saved choices, dialogs, and OS authorization. It records a short-lived
// approval before replying allow. We then call WebKit, and TabViewController consumes that
// approval in the later WKUIDelegate callback. A bypass reply restores WebKit's
// flow on iOS 15 or the native handler selects the Duck.ai exception.
//
// Keep message fields in sync with MediaCaptureUserScript.swift. Verify changes with
// MediaCaptureUserScriptTests in the iOS Browser scheme.
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
    const NativePromise = Promise;
    const permissions = navigator.permissions;
    const queryPermission = permissions?.query?.bind(permissions);
    const permissionState = globalThis.PermissionStatus &&
        apply(getOwnPropertyDescriptor, Object, [PermissionStatus.prototype, "state"])?.get;
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
    const isTopLevel = globalThis.top === globalThis;
    // Swift checks that the request still belongs to the committed top-level page.
    const ancestorOrigins = globalThis.location.ancestorOrigins;
    const topOrigin = isTopLevel ? origin : ancestorOrigins?.[ancestorOrigins.length - 1] ?? "null";
    // Compare with every ancestor, not only the top-level page: a frame can share the top-level
    // origin and still sit inside a cross-origin frame (a.example → b.example → a.example).
    // Whenever any ancestor is cross-origin, rely on WebKit's Permissions API for the whole
    // chain's delegation. Top-level pages have no ancestors.
    const hasCrossOriginAncestor = (() => {
        for (let index = 0; index < (ancestorOrigins?.length ?? 0); index += 1) {
            if (ancestorOrigins[index] !== origin) {
                return true;
            }
        }
        return false;
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
    // Like WebKit, use the embedding attributes from when this document loaded; a later change
    // applies on the next navigation. Parse the local rules before page scripts can replace
    // the methods they use; only the inherited policy check waits for the first request.
    const embeddingFrame = (() => {
        if (hasPolicyIntrospection || hasCrossOriginAncestor || isTopLevel) {
            return null;
        }
        try {
            const frame = globalThis.frameElement;
            if (!frame) {
                return null;
            }
            const parent = globalThis.parent;
            const getAttribute = Element.prototype.getAttribute;
            const source = apply(getAttribute, frame, ["srcdoc"]) === null ? apply(getAttribute, frame, ["src"]) : null;
            return {
                policy: apply(getAttribute, frame, ["allow"]) ?? "",
                source,
                baseURI: source === null ? null : apply(getOwnPropertyDescriptor(Node.prototype, "baseURI").get, frame, []),
                parentOrigin: parent.location.origin,
                inheritedPolicy: parent[inheritedPolicyProperty]
            };
        } catch (_) {
            return null;
        }
    })();
    const localPolicyAllows = (feature) => {
        if (hasCrossOriginAncestor) {
            return false;
        }
        if (isTopLevel) {
            return true;
        }
        try {
            if (!embeddingFrame) {
                return false;
            }
            const { policy, source, baseURI, parentOrigin } = embeddingFrame;
            let sourceOrigin = parentOrigin;
            if (source !== null) {
                try {
                    const sourceURL = new URL(source, baseURI);
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
                        allowed ||= parentOrigin === origin;
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
    const localCameraAllowed = !hasPolicyIntrospection && localPolicyAllows("camera");
    const localMicrophoneAllowed = !hasPolicyIntrospection && localPolicyAllows("microphone");
    const fallbackPolicyAllows = (feature) => {
        if (!(feature === "camera" ? localCameraAllowed : localMicrophoneAllowed)) {
            return false;
        }
        if (isTopLevel) {
            return true;
        }
        try {
            const inheritedPolicy = embeddingFrame.inheritedPolicy;
            return typeof inheritedPolicy === "function" && inheritedPolicy(feature);
        } catch (_) {
            return false;
        }
    };
    let fallbackCameraAllowed;
    let fallbackMicrophoneAllowed;
    const policyAllows = (feature) => {
        if (!hasPolicyIntrospection) {
            if (feature === "camera") {
                fallbackCameraAllowed ??= fallbackPolicyAllows("camera");
                return fallbackCameraAllowed;
            }
            fallbackMicrophoneAllowed ??= fallbackPolicyAllows("microphone");
            return fallbackMicrophoneAllowed;
        }
        try {
            return toBoolean(apply(allowsFeature, permissionsPolicy, [feature]));
        } catch (_) {
            return false;
        }
    };
    apply(defineProperty, Object, [globalThis, inheritedPolicyProperty, { value: policyAllows }]);
    // A cross-origin frame can't read its iframe's allow attribute, but WebKit's Permissions API
    // reports "denied" for a feature the embedding pages didn't delegate to it. Resolve only a
    // promise made with the saved constructor: the page can change how derived promises are built.
    const delegationAllows = (features) => new NativePromise(resolve => {
        const check = (index) => {
            if (index === features.length) {
                resolve(true);
                return;
            }
            try {
                callThen(queryPermission({ name: features[index] }),
                    status => apply(permissionState, status, []) === "denied" ? resolve(false) : check(index + 1),
                    () => resolve(false));
            } catch (_) {
                resolve(false);
            }
        };
        check(0);
    });
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

        // Send ineligible requests too: Swift returns them to WebKit when site permissions is off.
        const isEligibleContext = this === mediaDevices && hasNonOpaqueOrigin && (isDuckAIHost || (isSecureContext &&
            !isSyntheticDocument &&
            (hasCrossOriginAncestor || ((!video || policyAllows("camera")) &&
                (!audio || policyAllows("microphone"))))));

        nextRequestID += 1;
        const requestID = `${nonce}:${nextRequestID}`;
        const post = isEligible => postMessage({ capability, requestID, isEligible, topOrigin, video, audio });
        let bridgePromise;
        try {
            bridgePromise = !isEligibleContext || !hasCrossOriginAncestor || isDuckAIHost
                ? post(isEligibleContext)
                : callThen(delegationAllows(video && audio ? ["camera", "microphone"] : [video ? "camera" : "microphone"]),
                    post);
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
