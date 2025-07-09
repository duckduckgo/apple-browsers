import { getStyleElement, hideElements } from '../utils';
import AutoConsentCMPBase from './base';

export default class Evidon extends AutoConsentCMPBase {
    name = 'Evidon';

    get hasSelfTest(): boolean {
        return false;
    }

    get isIntermediate(): boolean {
        return false;
    }

    get isCosmetic(): boolean {
        return false;
    }

    async detectCmp() {
        return this.elementExists('#_evidon_banner');
    }

    async detectPopup() {
        return this.elementVisible('#_evidon_banner', 'any');
    }

    async optOut() {
        if (this.click('#_evidon-decline-button')) {
            return true;
        }

        hideElements(getStyleElement(), '#evidon-prefdiag-overlay,#evidon-prefdiag-background,#_evidon-background');
        await this.waitForThenClick('#_evidon-option-button');

        await this.waitForElement('#evidon-prefdiag-overlay', 5000);

        await this.wait(500);
        await this.waitForThenClick('#evidon-prefdiag-decline');
        return true;
    }

    async optIn() {
        return this.click('#_evidon-accept-button');
    }
}
