import { expect } from '@esm-bundle/chai';
import { DomActions } from '../../../lib/dom-actions';
import { instantiateDomActions } from '../utils';

// must be run from dom-actions.prehide.delayed-element.html
describe('prehide', () => {
    let domActions: DomActions;

    beforeEach(() => {
        // Given
        domActions = instantiateDomActions();
    });

    it('returns true even when element is only created after the call, and is immediately hidden', () => {
        // Given
        expect(document.querySelector('style#autoconsent-prehide')).to.be.null; // check that style element does not yet exist

        // When
        const result = domActions.prehide('#nonexistent');

        // Then
        expect(result).to.be.true;
        expect(document.querySelector('style#autoconsent-prehide')).not.to.be.null; // check that style element was created

        // we create element ex post and it will be hidden immediately
        const createdDiv = document.createElement('div');
        createdDiv.innerText = 'Here is some content';
        createdDiv.id = 'nonexistent';

        document.getElementsByTagName('body')[0].appendChild(createdDiv);

        expect(createdDiv.checkVisibility({ checkOpacity: true })).to.be.false;
    });
});
