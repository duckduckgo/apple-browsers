import { expect } from '@esm-bundle/chai';
import { DomActions } from '../../../lib/dom-actions';
import { instantiateDomActions } from '../utils';

// must be run from dom-actions.prehide.empty-selector.html
describe('prehide', () => {
    let domActions: DomActions;

    beforeEach(() => {
        // Given
        domActions = instantiateDomActions();
    });

    it('returns false when selector is empty string', () => {
        // Given
        expect(document.getElementById('visible').checkVisibility({ checkOpacity: true })).to.be.true; // establish baseline to prevent false positive
        expect(document.querySelector('style#autoconsent-prehide')).to.be.null; // check that style element does not yet exist

        // When
        const result = domActions.prehide('');

        // Then
        expect(result).to.be.false;
        expect(document.getElementById('visible').checkVisibility({ checkOpacity: true })).to.be.true;
        expect(document.querySelector('style#autoconsent-prehide')).not.to.be.null; // check that style element was created
    });
});
