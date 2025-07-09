import AutoConsentCMPBase from './base';

export default class Cookiebot extends AutoConsentCMPBase {
    name = 'Cybotcookiebot';
    prehideSelectors = [
        '#CybotCookiebotDialog,#CybotCookiebotDialogBodyUnderlay,#dtcookie-container,#cookiebanner,#cb-cookieoverlay,.modal--cookie-banner,#cookiebanner_outer,#CookieBanner',
    ];

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
        return await this.mainWorldEval('EVAL_COOKIEBOT_1');
    }

    async detectPopup() {
        return this.mainWorldEval('EVAL_COOKIEBOT_2');
    }

    async optOut() {
        await this.wait(500);
        let res = await this.mainWorldEval('EVAL_COOKIEBOT_3'); // withdraw
        await this.wait(1000); // prevent race conditions
        res = res && (await this.mainWorldEval('EVAL_COOKIEBOT_4')); // hide
        return res;
    }

    async optIn() {
        if (this.elementExists('#dtcookie-container')) {
            return this.click('.h-dtcookie-accept');
        }

        this.click('.CybotCookiebotDialogBodyLevelButton:not(:checked):enabled', true);
        this.click('#CybotCookiebotDialogBodyLevelButtonAccept');
        this.click('#CybotCookiebotDialogBodyButtonAccept');
        return true;
    }

    async test() {
        await this.wait(500);
        return await this.mainWorldEval('EVAL_COOKIEBOT_5');
    }
}
