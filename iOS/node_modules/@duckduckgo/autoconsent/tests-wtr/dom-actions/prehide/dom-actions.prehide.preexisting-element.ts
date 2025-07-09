import { expect } from '@esm-bundle/chai';
import { instantiateDomActions } from '../utils';
import { DomActions } from '../../../lib/dom-actions';

// must be run from dom-actions.prehide.preexisting-element.html
describe('prehide', () => {
    let domActions: DomActions;

    beforeEach(() => {
        // Given
        domActions = instantiateDomActions();
    });

    it('prehides preexisting element by selector', async () => {
        // Given
        expect(document.getElementById('visible').checkVisibility({ checkOpacity: true })).to.be.true; // establish baseline to prevent false positive
        expect(document.querySelector('style#autoconsent-prehide')).to.be.null; // check that style element does not yet exist

        // When
        const result = domActions.prehide('#visible');

        // Then
        expect(result).to.be.true;

        expect(document.getElementById('visible').checkVisibility({ checkOpacity: true })).to.be.false;
        expect(document.querySelector('style#autoconsent-prehide')).not.to.be.null; // check that style element was created
    });
});
