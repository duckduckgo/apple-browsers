import { RunContext } from '../rules';
import { waitFor } from '../utils';
import AutoConsentCMPBase from './base';

export default class TrustArcFrame extends AutoConsentCMPBase {
    name = 'TrustArc-frame';

    runContext: RunContext = {
        main: false,
        frame: true,
        urlPattern: '^https://consent-pref\\.trustarc\\.com/\\?',
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

    async detectCmp() {
        return true;
    }

    async detectPopup() {
        // we're already inside the popup
        return this.elementVisible('#defaultpreferencemanager', 'any') && this.elementVisible('.mainContent', 'any');
    }

    async navigateToSettings() {
        // wait for it to load
        await waitFor(
            async () => {
                return (
                    this.elementExists('.shp') || this.elementVisible('.advance', 'any') || this.elementExists('.switch span:first-child')
                );
            },
            10,
            500,
        );
        // splash screen -> hit more information
        if (this.elementExists('.shp')) {
            this.click('.shp');
        }

        await this.waitForElement('.prefPanel', 5000);

        // go to advanced settings if not yet shown
        if (this.elementVisible('.advance', 'any')) {
            this.click('.advance');
        }

        // takes a while to load the opt-in/opt-out buttons
        return await waitFor(() => this.elementVisible('.switch span:first-child', 'any'), 5, 1000);
    }

    async optOut() {
        // if the user has already opted out, let's not close the window
        if (await this.mainWorldEval('EVAL_TRUSTARC_FRAME_TEST')) {
            return true;
        }

        // When Tags are being controlled through a tag managment system, the window will not call the vendors' opt-out
        let timeout = 3000;
        if (await this.mainWorldEval('EVAL_TRUSTARC_FRAME_GTM')) {
            timeout = 1500;
        }

        await waitFor(() => document.readyState === 'complete', 20, 100);
        await this.waitForElement('.mainContent[aria-hidden=false]', timeout);

        if (this.click('.rejectAll')) {
            return true;
        }

        if (this.elementExists('.prefPanel')) {
            await this.waitForElement('.prefPanel[style="visibility: visible;"]', timeout);
        }

        if (this.click('#catDetails0')) {
            this.click('.submit');
            this.waitForThenClick('#gwt-debug-close_id', timeout);
            return true;
        }

        if (this.click('.required')) {
            this.waitForThenClick('#gwt-debug-close_id', timeout);
            return true;
        }

        await this.navigateToSettings();

        this.click('.switch span:nth-child(1):not(.active)', true);

        this.click('.submit');

        // at this point, iframe usually closes. Sometimes we need to close manually, but we don't wait for it to report success
        this.waitForThenClick('#gwt-debug-close_id', timeout * 10);

        return true;
    }

    async optIn() {
        if (this.click('.call')) {
            return true;
        }
        await this.navigateToSettings();
        this.click('.switch span:nth-child(2)', true);

        this.click('.submit');

        // at this point, iframe usually closes. Sometimes we need to close manually, but we don't wait for it to report success
        this.waitForElement('#gwt-debug-close_id', 300000).then(() => {
            this.click('#gwt-debug-close_id');
        });

        return true;
    }

    async test() {
        // Test JS variable to check the user's preference
        // preferences = undefined means no consent is set, preferences = '0' means consent is set to required only
        await this.wait(500);
        return await this.mainWorldEval('EVAL_TRUSTARC_FRAME_TEST');
    }
}
