import { waitFor } from '../utils';
import AutoConsentCMPBase from './base';

export default class Conversant extends AutoConsentCMPBase {
    prehideSelectors = ['.cmp-root'];
    name = 'Conversant';

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
        return this.elementExists('.cmp-root .cmp-receptacle');
    }

    async detectPopup() {
        return this.elementVisible('.cmp-root .cmp-receptacle', 'any');
    }

    async optOut() {
        if (!(await this.waitForThenClick('.cmp-main-button:not(.cmp-main-button--primary)'))) {
            return false;
        }

        if (!(await this.waitForElement('.cmp-view-tab-tabs'))) {
            return false;
        }

        await this.waitForThenClick('.cmp-view-tab-tabs > :first-child');
        await this.waitForThenClick('.cmp-view-tab-tabs > .cmp-view-tab--active:first-child');

        for (const item of Array.from(document.querySelectorAll('.cmp-accordion-item'))) {
            (<HTMLElement>item.querySelector('.cmp-accordion-item-title')).click();
            await waitFor(() => !!item.querySelector('.cmp-accordion-item-content.cmp-active'), 10, 50);
            const content = item.querySelector('.cmp-accordion-item-content.cmp-active');
            content
                .querySelectorAll('.cmp-toggle-actions .cmp-toggle-deny:not(.cmp-toggle-deny--active)')
                .forEach((e: HTMLElement) => e.click());
            content
                .querySelectorAll('.cmp-toggle-actions .cmp-toggle-checkbox:not(.cmp-toggle-checkbox--active)')
                .forEach((e: HTMLElement) => e.click());
            // await waitFor(() => !item.querySelector('.cmp-toggle-deny--active,.cmp-toggle-checkbox--active'), 5, 50); // this may take a long time
        }
        await this.click('.cmp-main-button:not(.cmp-main-button--primary)');
        return true;
    }

    async optIn() {
        return this.waitForThenClick('.cmp-main-button.cmp-main-button--primary');
    }

    async test() {
        return document.cookie.includes('cmp-data=0');
    }
}
