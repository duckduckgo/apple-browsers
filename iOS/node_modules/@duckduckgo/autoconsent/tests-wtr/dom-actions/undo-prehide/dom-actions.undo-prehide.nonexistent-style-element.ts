import { expect } from '@esm-bundle/chai';
import { DomActions } from '../../../lib/dom-actions';
import { instantiateDomActions } from '../utils';

// must be run from dom-actions.prehide.empty-selector.html
describe('undoPrehide', () => {
    let domActions: DomActions;

    beforeEach(() => {
        // Given
        domActions = instantiateDomActions();
    });

    it('creates style element if it did not previously exist and immediately removes it', () => {
        // Given
        expect(document.querySelector('style#autoconsent-prehide')).to.be.null; // check that style element does not yet exist

        // When
        domActions.undoPrehide();

        // Then
        expect(document.querySelector('style#autoconsent-prehide')).to.be.null; // check that style element again does not exist (in fact, it was created for a bit and then removed immediately)
    });
});
