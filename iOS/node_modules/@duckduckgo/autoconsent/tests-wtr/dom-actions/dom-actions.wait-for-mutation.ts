import { expect } from '@esm-bundle/chai';
import { instantiateDomActions } from './utils';

// must be run from dom-actions.wait-for-element.html
describe('waitForMutation', () => {
    it('should resolve if the DOM is modified', async () => {
        // Given
        const domActions = instantiateDomActions();

        // When
        const resultPromise = domActions.waitForMutation('html');
        const el = document.createElement('p');
        document.body.appendChild(el);

        // Then
        expect(await resultPromise).to.be.true;
    });

    it('should throw if the dom does not change by timeout', async () => {
        // Given
        const domActions = instantiateDomActions();

        // When
        const resultPromise = domActions.waitForMutation('html', 10);

        // Then
        try {
            await resultPromise;
            expect.fail('Expected Error');
        } catch (e) {
            expect(e).to.be.an('Error');
        }
    });

    it('should limit mutation detector to the provided selector', async () => {
        // Given
        const domActions = instantiateDomActions();

        // When
        const resultPromise = domActions.waitForMutation('#already-present', 10);
        const el = document.createElement('p');
        document.body.appendChild(el);

        // Then
        try {
            await resultPromise;
            expect.fail('Expected Error');
        } catch (e) {
            expect(e).to.be.an('Error');
        }
    });

    it('should still resolve for a mutation within the provided selector', async () => {
        // Given
        const domActions = instantiateDomActions();

        // When
        const resultPromise = domActions.waitForMutation('#already-present', 10);
        document.getElementById('already-present').innerText = 'foo';

        // Then
        expect(await resultPromise).to.be.true;
    });

    it('should throw if selector does not match anything in the page', async () => {
        const domActions = instantiateDomActions();

        try {
            await domActions.waitForMutation('#not-present', 10);
            expect.fail('Expected Error');
        } catch (e) {
            expect(e).to.be.an('Error');
        }
    });
});
