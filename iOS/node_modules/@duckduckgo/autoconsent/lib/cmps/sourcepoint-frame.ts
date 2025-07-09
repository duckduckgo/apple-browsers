import { RunContext } from '../rules';
import { waitFor } from '../utils';
import AutoConsentCMPBase from './base';

export default class SourcePoint extends AutoConsentCMPBase {
    name = 'Sourcepoint-frame';
    prehideSelectors = ["div[id^='sp_message_container_'],.message-overlay", '#sp_privacy_manager_container'];

    ccpaNotice = false;
    ccpaPopup = false;

    runContext: RunContext = {
        main: true,
        frame: true,
    };

    get hasSelfTest(): boolean {
        return false; // self-test is done by parent frame
    }

    get isIntermediate(): boolean {
        return false;
    }

    get isCosmetic(): boolean {
        return false;
    }

    async detectCmp() {
        const url = new URL(location.href);
        if (url.searchParams.has('message_id') && url.hostname === 'ccpa-notice.sp-prod.net') {
            this.ccpaNotice = true;
            return true;
        }
        if (url.hostname === 'ccpa-pm.sp-prod.net') {
            this.ccpaPopup = true;
            return true;
        }
        return (
            (url.pathname === '/index.html' ||
                url.pathname === '/privacy-manager/index.html' ||
                url.pathname === '/ccpa_pm/index.html' ||
                url.pathname === '/us_pm/index.html') &&
            (url.searchParams.has('message_id') || url.searchParams.has('requestUUID') || url.searchParams.has('consentUUID'))
        );
    }

    async detectPopup() {
        if (this.ccpaNotice) {
            return true;
        }
        if (this.ccpaPopup) {
            return await this.waitForElement('.priv-save-btn', 2000);
        }
        // check for the paywall button, and bail if it exists to prevent broken opt out
        await this.waitForElement(
            '.sp_choice_type_11,.sp_choice_type_12,.sp_choice_type_13,.sp_choice_type_ACCEPT_ALL,.sp_choice_type_SAVE_AND_EXIT',
            2000,
        );
        return !this.elementExists('.sp_choice_type_9');
    }

    async optIn() {
        await this.waitForElement('.sp_choice_type_11,.sp_choice_type_ACCEPT_ALL', 2000);
        if (this.click('.sp_choice_type_11')) {
            return true;
        }

        if (this.click('.sp_choice_type_ACCEPT_ALL')) {
            return true;
        }
        return false;
    }

    isManagerOpen() {
        return location.pathname === '/privacy-manager/index.html' || location.pathname === '/ccpa_pm/index.html';
    }

    async optOut() {
        // FIXME: ideally we want to wait until the outer frame is ready, but it's tricky in cross-origin frames
        await this.wait(500);

        const logsConfig = this.autoconsent.config.logs;
        if (this.ccpaPopup) {
            // toggles with 2 buttons
            const toggles = document.querySelectorAll(
                '.priv-purpose-container .sp-switch-arrow-block a.neutral.on .right',
            ) as NodeListOf<HTMLElement>;
            for (const t of toggles) {
                t.click();
            }
            // switch toggles
            const switches = document.querySelectorAll(
                '.priv-purpose-container .sp-switch-arrow-block a.switch-bg.on',
            ) as NodeListOf<HTMLElement>;
            for (const t of switches) {
                t.click();
            }
            return this.click('.priv-save-btn');
        }

        // sometimes there's a "Save and Exit" / "Essential cookies" button
        if (this.elementVisible('.sp_choice_type_SE', 'any')) {
            // click the "Do Not Sell" toggle if it exists
            this.click(
                [
                    "xpath///div[contains(., 'Do not share my personal information') and contains(@class, 'switch-container')]",
                    '.pm-switch[aria-checked=false] .slider',
                ],
                false,
            );
            return this.click('.sp_choice_type_SE');
        }

        if (!this.isManagerOpen()) {
            const actionable = await this.waitForVisible('.sp_choice_type_12,.sp_choice_type_13,[data-choice="1739968508799"]');
            if (!actionable) {
                return false;
            }

            if (!this.elementExists('.sp_choice_type_12,[data-choice="1739968508799"]')) {
                // do not sell button
                return this.click('.sp_choice_type_13');
            }

            this.click('.sp_choice_type_12,[data-choice="1739968508799"]');
            // the page may navigate at this point but that's okay
            await waitFor(() => this.isManagerOpen(), 200, 100);
        }

        await this.waitForElement('.type-modal', 20000);
        if (this.elementExists('[role=tablist]')) {
            await this.waitForElement('[role=tablist] [role=tab]', 10000);
        }

        // check "Do Not Sell" (CCPA) toggle if it exists
        this.waitForThenClick('.ccpa-stack .pm-switch[aria-checked=true] .slider', 500, true); // the UI is reversed: "unchecked" switch displays as an enabled toggle

        // reject all button is offered by some sites
        try {
            const rejectSelector1 = '.sp_choice_type_REJECT_ALL';
            const rejectSelector2 = '.reject-toggle';
            const path = await Promise.race([
                this.waitForElement(rejectSelector1, 2000).then((success) => (success ? 0 : -1)),
                this.waitForElement(rejectSelector2, 2000).then((success) => (success ? 1 : -1)),
                this.waitForElement('.pm-features', 2000).then((success) => (success ? 2 : -1)),
            ]);

            if (path === 0) {
                await this.waitForVisible(rejectSelector1);
                return this.click(rejectSelector1);
            } else if (path === 1) {
                this.click(rejectSelector2);
            } else if (path === 2) {
                await this.waitForElement('.pm-features', 10000);
                this.click('.checked > span', true);
                this.click('.chevron');
            }
        } catch (e) {
            logsConfig.errors && console.warn(e);
        }
        // TODO: race condition: if the reject button was clicked, the popup disappears very quickly, so the background script may not receive a success report.
        return this.click('.sp_choice_type_SAVE_AND_EXIT');
    }
}
