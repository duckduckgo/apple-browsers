import { waitFor } from '../utils';
import AutoConsentCMPBase from './base';

export default class Tumblr extends AutoConsentCMPBase {
    name = 'tumblr-com';
    runContext = {
        urlPattern: '^https://(www\\.)?tumblr\\.com/',
    };

    get hasSelfTest(): boolean {
        return false;
    }

    get isIntermediate(): boolean {
        return false;
    }

    get isCosmetic(): boolean {
        return false;
    }

    get prehideSelectors(): string[] {
        return ['#cmp-app-container'];
    }

    async detectCmp() {
        return this.elementExists('#cmp-app-container');
    }

    async detectPopup() {
        return this.elementVisible('#cmp-app-container', 'any');
    }

    async optOut() {
        let iframe: HTMLIFrameElement = document.querySelector('#cmp-app-container iframe');
        let settingsButton: HTMLButtonElement = iframe.contentDocument?.querySelector('.cmp-components-button.is-secondary');
        if (!settingsButton) {
            return false;
        }
        settingsButton.click();
        await waitFor(
            () => {
                const iframe: HTMLIFrameElement = document.querySelector('#cmp-app-container iframe');
                return !!iframe.contentDocument?.querySelector('.cmp__dialog input');
            },
            5,
            500,
        );

        // it's a different button now
        iframe = document.querySelector('#cmp-app-container iframe');
        settingsButton = iframe.contentDocument?.querySelector('.cmp-components-button.is-secondary');
        if (!settingsButton) {
            return false;
        }
        settingsButton.click();
        return true;
    }

    async optIn() {
        const iframe: HTMLIFrameElement = document.querySelector('#cmp-app-container iframe');
        const acceptButton: HTMLButtonElement = iframe.contentDocument.querySelector('.cmp-components-button.is-primary');
        if (acceptButton) {
            acceptButton.click();
            return true;
        }
        return false;
    }
}
