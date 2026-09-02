(() => {
    const apply = Reflect.apply;
    const getPrototypeOf = Object.getPrototypeOf;
    const getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
    const defineProperty = Object.defineProperty;
    const toBoolean = Boolean;
    const rejectPromise = Promise.reject.bind(Promise);
    const callThen = Function.prototype.call.bind(Promise.prototype.then);
    const NativeDOMException = DOMException;
    const querySelectorAll = Document.prototype.querySelectorAll;
    const elementQuerySelectorAll = Element.prototype.querySelectorAll;
    const elementMatches = Element.prototype.matches;
    const hasAttribute = Element.prototype.hasAttribute;
    const nodeListLength = getOwnPropertyDescriptor(NodeList.prototype, "length")?.get;
    const nodeListItem = NodeList.prototype.item;
    const weakSetAdd = WeakSet.prototype.add;
    const weakSetHas = WeakSet.prototype.has;
    const NativeMutationObserver = MutationObserver;
    const observeMutations = NativeMutationObserver.prototype.observe;
    const takeMutationRecords = NativeMutationObserver.prototype.takeRecords;
    const mutationRecordType = getOwnPropertyDescriptor(MutationRecord.prototype, "type")?.get;
    const mutationRecordTarget = getOwnPropertyDescriptor(MutationRecord.prototype, "target")?.get;
    const mutationRecordAttributeName = getOwnPropertyDescriptor(MutationRecord.prototype, "attributeName")?.get;
    const mutationRecordOldValue = getOwnPropertyDescriptor(MutationRecord.prototype, "oldValue")?.get;
    const mutationRecordAddedNodes = getOwnPropertyDescriptor(MutationRecord.prototype, "addedNodes")?.get;
    const contentWindowGetters = [
        getOwnPropertyDescriptor(HTMLIFrameElement.prototype, "contentWindow")?.get,
        getOwnPropertyDescriptor(HTMLFrameElement.prototype, "contentWindow")?.get
    ].filter(Boolean);
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
    const sandboxTraversalToken = "ddg-media-sandbox-v1";
    const sandboxCheckProperty = "__ddgMediaSandboxCheck";
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
        try {
            const elements = apply(elementQuerySelectorAll, root, ["iframe[sandbox],frame[sandbox]"]);
            const count = apply(nodeListLength, elements, []);
            for (let index = 0; index < count; index++) {
                rememberSandboxedFrame(apply(nodeListItem, elements, [index]), true);
            }
        } catch (_) {}
    };
    const processSandboxMutations = (records) => {
        for (let recordIndex = 0; recordIndex < records.length; recordIndex++) {
            const record = records[recordIndex];
            const type = apply(mutationRecordType, record, []);
            if (type === "attributes" && apply(mutationRecordAttributeName, record, []) === "sandbox") {
                const target = apply(mutationRecordTarget, record, []);
                if (apply(mutationRecordOldValue, record, []) !== null || apply(hasAttribute, target, ["sandbox"])) {
                    rememberSandboxedFrame(target, true);
                }
            } else if (type === "childList") {
                const addedNodes = apply(mutationRecordAddedNodes, record, []);
                const count = apply(nodeListLength, addedNodes, []);
                for (let nodeIndex = 0; nodeIndex < count; nodeIndex++) {
                    rememberSandboxedFrames(apply(nodeListItem, addedNodes, [nodeIndex]));
                }
            }
        }
    };
    let sandboxHistoryObserver;
    let sandboxHistoryAvailable = false;
    try {
        sandboxHistoryObserver = new NativeMutationObserver(processSandboxMutations);
        apply(observeMutations, sandboxHistoryObserver, [document, {
            attributes: true,
            attributeFilter: ["sandbox"],
            attributeOldValue: true,
            childList: true,
            subtree: true
        }]);
        sandboxHistoryAvailable = true;
    } catch (_) {}
    const embeddingFrameForWindow = (childWindow) => {
        try {
            const elements = apply(querySelectorAll, document, ["iframe,frame"]);
            const count = apply(nodeListLength, elements, []);
            for (let index = 0; index < count; index++) {
                const element = apply(nodeListItem, elements, [index]);
                for (let getterIndex = 0; getterIndex < contentWindowGetters.length; getterIndex++) {
                    try {
                        if (apply(contentWindowGetters[getterIndex], element, []) === childWindow) {
                            return element;
                        }
                    } catch (_) {}
                }
            }
        } catch (_) {}
        return null;
    };
    const hasSandboxedAncestor = (() => {
        if (globalThis.parent === globalThis) {
            return false;
        }
        try {
            const parentCheck = globalThis.parent[sandboxCheckProperty];
            return typeof parentCheck !== "function" || parentCheck(globalThis, sandboxTraversalToken) !== false;
        } catch (_) {
            return true;
        }
    })();
    const checkChildSandbox = (childWindow, presentedTraversalToken) => {
        if (presentedTraversalToken !== sandboxTraversalToken || !sandboxHistoryAvailable) {
            return true;
        }
        try {
            processSandboxMutations(apply(takeMutationRecords, sandboxHistoryObserver, []));
            const embeddingFrame = embeddingFrameForWindow(childWindow);
            return !embeddingFrame ||
                hasSandboxedAncestor ||
                apply(weakSetHas, sandboxedEmbeddingFrames, [embeddingFrame]) ||
                apply(hasAttribute, embeddingFrame, ["sandbox"]);
        } catch (_) {
            return true;
        }
    };
    try {
        apply(defineProperty, Object, [globalThis, sandboxCheckProperty, {
            configurable: false,
            enumerable: false,
            writable: false,
            value: checkChildSandbox
        }]);
    } catch (_) {}
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
            hasNonOpaqueOrigin &&
            !isSyntheticDocument &&
            (!video || policyAllows("camera")) &&
            (!audio || policyAllows("microphone"));
        if (hasSandboxedAncestor || (!isDuckAIHost && !isEligibleContext)) {
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
