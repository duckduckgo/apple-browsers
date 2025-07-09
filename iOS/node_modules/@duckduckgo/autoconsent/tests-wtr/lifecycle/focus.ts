import { expect } from '@esm-bundle/chai';
import Autoconsent from '../../lib/web';

describe('Autoconsent', () => {
    let autoconsent: Autoconsent;

    beforeEach(() => {
        // Given
        autoconsent = new Autoconsent(() => Promise.resolve(), {
            enabled: false, // bypass initialization
            autoAction: null,
        });
    });

    it('should restore focus after the opt-out', async () => {
        const focusedElement = document.querySelector('#pre-focused-input') as HTMLInputElement;
        focusedElement.focus();
        expect(document.activeElement).to.equal(focusedElement);
        // @ts-expect-error this is a mock
        autoconsent.foundCmp = {
            name: 'Test page CMP',
            optOut: async () => {
                // @ts-expect-error we know it'll work
                document.querySelector('#popup-input').focus();
                // @ts-expect-error we know it'll work
                document.querySelector('#reject-all').click();
                return true;
            },
        };
        await autoconsent.doOptOut();
        expect(document.activeElement).to.equal(focusedElement);
    });

    it('should restore focus after the opt-in', async () => {
        const focusedElement = document.querySelector('#pre-focused-input') as HTMLInputElement;
        focusedElement.focus();
        expect(document.activeElement).to.equal(focusedElement);
        // @ts-expect-error this is a mock
        autoconsent.foundCmp = {
            name: 'Test page CMP',
            optIn: async () => {
                // @ts-expect-error we know it'll work
                document.querySelector('#popup-input').focus();
                // @ts-expect-error we know it'll work
                document.querySelector('#accept-all').click();
                return true;
            },
        };
        await autoconsent.doOptIn();
        expect(document.activeElement).to.equal(focusedElement);
    });
});
