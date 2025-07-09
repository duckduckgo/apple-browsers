import { getGlobal } from './utils.js';

/**
 * Check if the current document origin is on the tracker list, using the provided lookup trie.
 * @param {object} trackerLookup Trie lookup of tracker domains
 * @returns {boolean} True iff the origin is a tracker.
 *
 * Note: getGlobal() is used in testing to get the global object,
 * it's a work around for ESM modules are essentially singletons preventing overriding of global variables.
 */
export function isTrackerOrigin(trackerLookup, originHostname = getGlobal().document.location.hostname) {
    const parts = originHostname.split('.').reverse();
    let node = trackerLookup;
    for (const sub of parts) {
        if (node[sub] === 1) {
            return true;
        } else if (node[sub]) {
            node = node[sub];
        } else {
            return false;
        }
    }
    return false;
}
