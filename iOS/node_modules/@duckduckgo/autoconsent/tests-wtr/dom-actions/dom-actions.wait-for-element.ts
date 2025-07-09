import { expect } from '@esm-bundle/chai';
import { instantiateDomActions } from './utils';
import sinon from 'sinon/pkg/sinon-esm.js';

// must be run from dom-actions.wait-for-element.html
describe('waitForElement', () => {
    let clock;

    beforeEach(() => {
        clock = sinon.useFakeTimers();
    });

    afterEach(() => {
        clock.restore();
    });

    it('should resolve to true immediately if element already present', async () => {
        // Given
        const domActions = instantiateDomActions();

        // When
        const result = await domActions.waitForElement('#already-present');

        // Then
        expect(result).to.be.true;
    });
    it('should resolve to true once element appears', async () => {
        // Given
        const domActions = instantiateDomActions();

        // When
        const resultPromise = domActions.waitForElement('#deferred', 1000);

        clock.tickAsync(800); // intentionally not awaiting

        setTimeout(() => {
            const deferredElement = document.createElement('p');
            deferredElement.id = 'deferred';
            deferredElement.innerText = 'Deferred element appeared';

            document.getElementById('target-for-delayed-element').appendChild(deferredElement);
        }, 800);

        const result = await resultPromise;

        // Then
        expect(result).to.be.true;
    });
    it('should resolve to false if element does not appear until timeout', async () => {
        // Given
        const domActions = instantiateDomActions();

        // When
        const resultPromise = domActions.waitForElement('#not-present', 1000);

        clock.tickAsync(1000); // intentionally not awaiting

        const result = await resultPromise;

        // Then
        expect(result).to.be.false;
    });
});
