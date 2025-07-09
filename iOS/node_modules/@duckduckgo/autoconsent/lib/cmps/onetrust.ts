import { waitFor } from '../utils';
import AutoConsentCMPBase from './base';

export default class Onetrust extends AutoConsentCMPBase {
    name = 'Onetrust';
    prehideSelectors = ['#onetrust-banner-sdk,#onetrust-consent-sdk,.onetrust-pc-dark-filter,.js-consent-banner'];

    get hasSelfTest(): boolean {
        return true;
    }

    get isIntermediate(): boolean {
        return false;
    }

    get isCosmetic(): boolean {
        return false;
    }

    async detectCmp() {
        return this.elementExists('#onetrust-banner-sdk,#onetrust-pc-sdk');
    }

    async detectPopup() {
        return this.elementVisible('#onetrust-banner-sdk,#onetrust-pc-sdk', 'any');
    }

    async optOut() {
        if (this.elementVisible('#onetrust-reject-all-handler,.ot-pc-refuse-all-handler,.js-reject-cookies', 'any')) {
            // 'reject all' shortcut
            return this.click('#onetrust-reject-all-handler,.ot-pc-refuse-all-handler,.js-reject-cookies');
        }

        if (this.elementExists('#onetrust-pc-btn-handler')) {
            // "show purposes" button inside a popup
            this.click('#onetrust-pc-btn-handler');
        } else {
            // otherwise look for a generic "show settings" button
            this.click('.ot-sdk-show-settings,button.js-cookie-settings');
        }

        await this.waitForElement('#onetrust-consent-sdk', 2000);
        await this.wait(1000); // ideally we want to wait for popup visivility, but it's tricky on e.g. stackoverflow.com
        this.click('#onetrust-consent-sdk input.category-switch-handler:checked,.js-editor-toggle-state:checked', true); // optional step

        await this.wait(1000); // ideally we want to wait for popup visivility, but it's tricky on e.g. stackoverflow.com
        await this.waitForElement('.save-preference-btn-handler,.js-consent-save', 2000);
        this.click('.save-preference-btn-handler,.js-consent-save');

        // popup doesn't disappear immediately
        await this.waitForVisible('#onetrust-banner-sdk', 5000, 'none');
        return true;
    }

    async optIn() {
        return this.click('#onetrust-accept-btn-handler,#accept-recommended-btn-handler,.js-accept-cookies');
    }

    async test() {
        return await waitFor(() => this.mainWorldEval('EVAL_ONETRUST_1'), 10, 500);
    }
}
