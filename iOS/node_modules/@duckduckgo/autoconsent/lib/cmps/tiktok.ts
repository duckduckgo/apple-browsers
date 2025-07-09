import { RunContext } from '../rules';
import { isElementVisible } from '../utils';
import AutoConsentCMPBase from './base';

export default class Tiktok extends AutoConsentCMPBase {
    name = 'tiktok.com';

    runContext: RunContext = {
        urlPattern: 'tiktok',
    };

    get hasSelfTest(): boolean {
        return true;
    }

    get isIntermediate(): boolean {
        return false;
    }

    get isCosmetic(): boolean {
        return false;
    }

    getShadowRoot() {
        const container = document.querySelector('tiktok-cookie-banner');
        if (!container) {
            return null;
        }
        return container.shadowRoot;
    }

    async detectCmp() {
        return this.elementExists('tiktok-cookie-banner');
    }

    async detectPopup() {
        const banner = this.getShadowRoot().querySelector('.tiktok-cookie-banner') as HTMLElement;
        return isElementVisible(banner);
    }

    async optOut() {
        const logsConfig = this.autoconsent.config.logs;
        const declineButton = this.getShadowRoot().querySelector('.button-wrapper button:first-child') as HTMLElement;
        if (declineButton) {
            logsConfig.rulesteps && console.log('[clicking]', declineButton);
            declineButton.click();
            return true;
        } else {
            logsConfig.errors && console.log('no decline button found');
            return false;
        }
    }

    async optIn() {
        const logsConfig = this.autoconsent.config.logs;
        const acceptButton = this.getShadowRoot().querySelector('.button-wrapper button:last-child') as HTMLElement;
        if (acceptButton) {
            logsConfig.rulesteps && console.log('[clicking]', acceptButton);
            acceptButton.click();
            return true;
        } else {
            logsConfig.errors && console.log('no accept button found');
            return false;
        }
    }

    async test() {
        const match = document.cookie.match(/cookie-consent=([^;]+)/);
        if (!match) {
            return false;
        }
        const value = JSON.parse(decodeURIComponent(match[1]));
        return Object.values(value).every((x) => typeof x !== 'boolean' || x === false);
    }
}
