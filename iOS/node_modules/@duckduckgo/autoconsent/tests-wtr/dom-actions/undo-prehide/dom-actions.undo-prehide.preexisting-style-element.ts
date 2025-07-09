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

    it('removes preexisting style element', () => {
        // Given
        expect(document.querySelector('style#autoconsent-prehide')).to.not.be.null; // check that style element already exists

        // When
        domActions.undoPrehide();

        // Then
        expect(document.querySelector('style#autoconsent-prehide')).to.be.null; // check that style element was removed
    });
});
