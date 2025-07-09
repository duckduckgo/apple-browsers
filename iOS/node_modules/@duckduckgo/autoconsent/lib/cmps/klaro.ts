import AutoConsentCMPBase from './base';

export default class Klaro extends AutoConsentCMPBase {
    name = 'Klaro';
    prehideSelectors = ['.klaro'];
    settingsOpen = false;

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
        if (this.elementExists('.klaro > .cookie-modal')) {
            this.settingsOpen = true;
            return true;
        }
        return this.elementExists('.klaro > .cookie-notice');
    }

    async detectPopup() {
        return this.elementVisible('.klaro > .cookie-notice,.klaro > .cookie-modal', 'any');
    }

    async optOut() {
        const apiOptOutSuccess = await this.mainWorldEval('EVAL_KLARO_TRY_API_OPT_OUT');
        if (apiOptOutSuccess) {
            return true;
        }
        // if the API is broken for some reason, try clicking instead

        if (this.click('.klaro .cn-decline')) {
            return true;
        }

        // open popup via Javascript API
        await this.mainWorldEval('EVAL_KLARO_OPEN_POPUP');

        if (this.click('.klaro .cn-decline')) {
            return true;
        }

        this.click(
            '.cm-purpose:not(.cm-toggle-all) > input:not(.half-checked,.required,.only-required),.cm-purpose:not(.cm-toggle-all) > div > input:not(.half-checked,.required,.only-required)',
            true,
        );
        return this.click('.cm-btn-accept,.cm-button');
    }

    async optIn() {
        if (this.click('.klaro .cm-btn-accept-all')) {
            return true;
        }
        if (this.settingsOpen) {
            this.click('.cm-purpose:not(.cm-toggle-all) > input.half-checked', true);
            return this.click('.cm-btn-accept');
        }
        return this.click('.klaro .cookie-notice .cm-btn-success');
    }

    async test() {
        return await this.mainWorldEval('EVAL_KLARO_1');
    }
}
