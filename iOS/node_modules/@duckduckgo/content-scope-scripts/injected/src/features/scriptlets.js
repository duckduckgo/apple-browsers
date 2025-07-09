import ContentFeature from '../content-feature.js';
import { isBeingFramed } from '../utils.js';
import { setCookie } from './Scriptlets/src/scriptlets/set-cookie.js';
import { trustedSetCookie } from './Scriptlets/src/scriptlets/trusted-set-cookie.js';
import { setCookieReload } from './Scriptlets/src/scriptlets/set-cookie-reload.js';
import { removeCookie } from './Scriptlets/src/scriptlets/remove-cookie.js';
import { setConstant } from './Scriptlets/src/scriptlets/set-constant.js';
import { setLocalStorageItem } from './Scriptlets/src/scriptlets/set-local-storage-item.js';
import { abortCurrentInlineScript } from './Scriptlets/src/scriptlets/abort-current-inline-script.js';
import { abortOnPropertyRead } from './Scriptlets/src/scriptlets/abort-on-property-read.js';
import { abortOnPropertyWrite } from './Scriptlets/src/scriptlets/abort-on-property-write.js';
import { preventAddEventListener } from './Scriptlets/src/scriptlets/prevent-addEventListener.js';
import { preventWindowOpen } from './Scriptlets/src/scriptlets/prevent-window-open.js';
import { preventSetTimeout } from './Scriptlets/src/scriptlets/prevent-setTimeout.js';
import { removeNodeText } from './Scriptlets/src/scriptlets/remove-node-text.js';
import { preventFetch } from './Scriptlets/src/scriptlets/prevent-fetch.js';

export class Scriptlets extends ContentFeature {
    init() {
        if (isBeingFramed()) {
            return;
        }
        /* @type {import('./Scriptlets/src/scriptlets/scriptlets.ts').Source} */
        const source = {
            verbose: false,
        };

        const scriptlets = this.getFeatureSetting('scriptlets');
        for (const scriptlet of scriptlets) {
            source.name = scriptlet.name;
            source.args = Object.values(scriptlet.attrs);
            this.runScriptlet(scriptlet, source);
        }
    }

    runScriptlet(scriptlet, source) {
        const attrs = scriptlet.attrs || {};

        // add debug flag to site breakage reports
        this.addDebugFlag();

        if (scriptlet.name === 'setCookie') {
            setCookie(source, attrs.name, attrs.value, attrs.path, attrs.domain);
        }
        if (scriptlet.name === 'trustedSetCookie') {
            trustedSetCookie(source, attrs.name, attrs.value, attrs.path, attrs.domain);
        }
        if (scriptlet.name === 'setCookieReload') {
            setCookieReload(source, attrs.name, attrs.value, attrs.path, attrs.domain);
        }
        if (scriptlet.name === 'removeCookie') {
            removeCookie(source, attrs.match);
        }
        if (scriptlet.name === 'setConstant') {
            setConstant(source, attrs.property, attrs.value, attrs.stack, attrs.valueWrapper, attrs.setProxyTrap);
        }
        if (scriptlet.name === 'setLocalStorageItem') {
            setLocalStorageItem(source, attrs.key, attrs.value);
        }
        if (scriptlet.name === 'abortCurrentInlineScript') {
            abortCurrentInlineScript(source, attrs.property, attrs.search);
        }
        if (scriptlet.name === 'abortOnPropertyRead') {
            abortOnPropertyRead(source, attrs.property);
        }
        if (scriptlet.name === 'abortOnPropertyWrite') {
            abortOnPropertyWrite(source, attrs.property);
        }
        if (scriptlet.name === 'preventAddEventListener') {
            preventAddEventListener(source, attrs.typeSearch, attrs.listenerSearch, attrs.additionalArgName, attrs.additionalArgValue);
        }
        if (scriptlet.name === 'preventWindowOpen') {
            preventWindowOpen(source, attrs.match, attrs.delay, attrs.replacement);
        }
        if (scriptlet.name === 'preventSetTimeout') {
            preventSetTimeout(source, attrs.matchCallback, attrs.matchDelay);
        }
        if (scriptlet.name === 'removeNodeText') {
            removeNodeText(source, attrs.nodeName, attrs.textMatch, attrs.parentSelector);
        }
        if (scriptlet.name === 'preventFetch') {
            preventFetch(source, attrs.propsToMatch, attrs.responseBody, attrs.responseType);
        }
    }
}

export default Scriptlets;
