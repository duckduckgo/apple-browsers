import AutoConsentCMPBase from './base';

// Note: JS API is also available:
// https://help.consentmanager.net/books/cmp/page/javascript-api
export default class ConsentManager extends AutoConsentCMPBase {
    name = 'consentmanager.net';

    prehideSelectors = ['#cmpbox,#cmpbox2'];
    apiAvailable = false;

    get hasSelfTest(): boolean {
        return this.apiAvailable;
    }

    get isIntermediate(): boolean {
        return false;
    }

    get isCosmetic(): boolean {
        return false;
    }

    async detectCmp() {
        this.apiAvailable = await this.mainWorldEval('EVAL_CONSENTMANAGER_1');
        if (!this.apiAvailable) {
            return this.elementExists('#cmpbox');
        } else {
            return true;
        }
    }

    async detectPopup() {
        if (this.apiAvailable) {
            // wait before making this check because early in the page lifecycle this may incorrectly return
            // true, causing an opt-out when it is not needed.
            await this.wait(500);
            return await this.mainWorldEval('EVAL_CONSENTMANAGER_2');
        }
        return this.elementVisible('#cmpbox .cmpmore', 'any');
    }

    async optOut() {
        await this.wait(500);
        if (this.apiAvailable) {
            return await this.mainWorldEval('EVAL_CONSENTMANAGER_3');
        }

        if (this.click('.cmpboxbtnno')) {
            return true;
        }

        if (this.elementExists('.cmpwelcomeprpsbtn')) {
            this.click('.cmpwelcomeprpsbtn > a[aria-checked=true]', true);
            this.click('.cmpboxbtnsave');
            return true;
        }

        this.click('.cmpboxbtncustom');
        await this.waitForElement('.cmptblbox', 2000);
        this.click('.cmptdchoice > a[aria-checked=true]', true);
        this.click('.cmpboxbtnyescustomchoices');

        this.hide('#cmpwrapper,#cmpbox', 'display');
        return true;
    }

    async optIn() {
        if (this.apiAvailable) {
            return await this.mainWorldEval('EVAL_CONSENTMANAGER_4');
        }
        return this.click('.cmpboxbtnyes');
    }

    async test() {
        if (this.apiAvailable) {
            return await this.mainWorldEval('EVAL_CONSENTMANAGER_5');
        }
    }
}
