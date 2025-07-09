import { DDGProxy, DDGReflect, isBeingFramed } from './utils.js';
import ContentFeature from './content-feature.js';

const urlChangeListeners = new Set();
/**
 * Register a listener to be called when the URL changes.
 * @param {function} listener
 */
export function registerForURLChanges(listener) {
    if (urlChangeListeners.size === 0) {
        listenForURLChanges();
    }
    urlChangeListeners.add(listener);
}

function handleURLChange() {
    for (const listener of urlChangeListeners) {
        listener();
    }
}

function listenForURLChanges() {
    const urlChangedInstance = new ContentFeature('urlChanged', {}, {});
    if ('navigation' in globalThis && 'addEventListener' in globalThis.navigation) {
        // if the browser supports the navigation API, we can use that to listen for URL changes
        // Listening to navigatesuccess instead of navigate to ensure the navigation is committed.
        globalThis.navigation.addEventListener('navigatesuccess', () => {
            handleURLChange();
        });
        // Exit early if the navigation API is supported
        return;
    }
    if (isBeingFramed()) {
        // don't run if we're in an iframe
        return;
    }
    // single page applications don't have a DOMContentLoaded event on navigations, so
    // we use proxy/reflect on history.pushState to call applyRules on page navigations
    const historyMethodProxy = new DDGProxy(urlChangedInstance, History.prototype, 'pushState', {
        apply(target, thisArg, args) {
            const changeResult = DDGReflect.apply(target, thisArg, args);
            handleURLChange();
            return changeResult;
        },
    });
    historyMethodProxy.overload();
    // listen for popstate events in order to run on back/forward navigations
    window.addEventListener('popstate', () => {
        handleURLChange();
    });
}
