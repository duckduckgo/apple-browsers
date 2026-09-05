(() => {
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
    // An allow-same-origin sandbox may request media; opaque origins must never reach the bridge.
    const permissionsPolicy = document.permissionsPolicy ?? document.featurePolicy;
    const allowsFeature = permissionsPolicy?.allowsFeature;
    const hasPolicyIntrospection = typeof allowsFeature === "function";
    const policyAllows = (feature) => {
        if (!hasPolicyIntrospection) {
            return isSameOriginAsTopLevel;
        }
        try {
            return toBoolean(apply(allowsFeature, permissionsPolicy, [feature]));
        } catch (_) {
            return false;
        }
    };
    let nextRequestID = 0;

    const permissionDenied = () => new NativeDOMException("Permission denied", "NotAllowedError");
    const getUserMedia = function(constraints) {
        if (this !== mediaDevices) {
            return rejectPromise(permissionDenied());
        }
        if (constraints === null ||
            (typeof constraints !== "object" && typeof constraints !== "function")) {
            return apply(nativeGetUserMedia, this, arguments);
        }

        let rawVideo;
        let rawAudio;
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

        const isEligibleContext = isSecureContext &&
            !isSyntheticDocument &&
            (!video || policyAllows("camera")) &&
            (!audio || policyAllows("microphone"));
        if (!hasNonOpaqueOrigin || (!isDuckAIHost && !isEligibleContext)) {
            return rejectPromise(permissionDenied());
        }

        nextRequestID += 1;
        let bridgePromise;
        try {
            bridgePromise = postMessage({
                capability,
                requestID: `${nonce}:${nextRequestID}`,
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
