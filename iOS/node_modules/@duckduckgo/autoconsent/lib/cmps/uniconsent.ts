import AutoConsentCMPBase from './base';

export default class Uniconsent extends AutoConsentCMPBase {
    name = 'Uniconsent';

    get prehideSelectors(): string[] {
        return ['.unic', '.modal:has(.unic)'];
    }

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
        return this.elementExists('.unic .unic-box,.unic .unic-bar,.unic .unic-modal');
    }

    async detectPopup() {
        return this.elementVisible('.unic .unic-box,.unic .unic-bar,.unic .unic-modal', 'any');
    }

    async optOut() {
        await this.waitForElement('.unic button', 1000);
        document.querySelectorAll('.unic button').forEach((button: HTMLButtonElement) => {
            const text = button.textContent;
            if (text.includes('Manage Options') || text.includes('Optionen verwalten')) {
                button.click();
            }
        });

        if (await this.waitForElement('.unic input[type=checkbox]', 1000)) {
            await this.waitForElement('.unic button', 1000);

            document.querySelectorAll('.unic input[type=checkbox]').forEach((c: HTMLInputElement) => {
                if (c.checked) {
                    c.click();
                }
            });

            for (const b of <NodeListOf<HTMLButtonElement>>document.querySelectorAll('.unic button')) {
                const text = b.textContent;
                for (const pattern of ['Confirm Choices', 'Save Choices', 'Auswahl speichern']) {
                    if (text.includes(pattern)) {
                        b.click();
                        await this.wait(500); // give it some time to close the popup
                        return true;
                    }
                }
            }
        }

        return false;
    }

    async optIn() {
        return this.waitForThenClick('.unic #unic-agree');
    }

    async test() {
        await this.wait(1000);
        const res = this.elementExists('.unic .unic-box,.unic .unic-bar');
        return !res;
    }
}
