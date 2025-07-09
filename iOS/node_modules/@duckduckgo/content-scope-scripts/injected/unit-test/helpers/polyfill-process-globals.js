/**
 * Creates a mock location object for testing purposes.
 * @returns {Location} A mock location object.
 */
export function createLocationObject(href, frameAncestorsList = []) {
    return {
        href,
        // @ts-expect-error - ancestorOrigins is not defined in the type definition
        ancestorOrigins: createDomStringList(frameAncestorsList),
    };
}

export function createDomStringList(list) {
    const domStringList = {
        length: list.length,
        item(index) {
            if (index < 0 || index >= list.length) {
                return null;
            }
            return list[index];
        },
        contains(item) {
            return list.includes(item);
        },
    };

    // Add index access support
    for (let i = 0; i < list.length; i++) {
        Object.defineProperty(domStringList, i, {
            get() {
                return list[i];
            },
            enumerable: true,
        });
    }

    return domStringList;
}

export function polyfillProcessGlobals(defaultLocation = 'http://localhost:8080', frameAncestorsList = [], topisNull = false) {
    // Store original values to restore later
    const originalDocument = globalThis.document;
    const originalLocation = globalThis.location;
    const originalTop = globalThis.top;

    // Apply the patch
    // @ts-expect-error - document is not defined in the type definition
    globalThis.document = {
        referrer: defaultLocation,
        location: createLocationObject(defaultLocation, frameAncestorsList),
    };

    globalThis.location = createLocationObject(defaultLocation, frameAncestorsList);

    globalThis.top = Object.assign({}, originalTop, {
        location: createLocationObject(defaultLocation, frameAncestorsList),
    });
    if (topisNull) {
        globalThis.top = null;
    }

    // Return a cleanup function
    return function cleanup() {
        globalThis.document = originalDocument;
        globalThis.location = originalLocation;
        globalThis.top = originalTop;
    };
}
