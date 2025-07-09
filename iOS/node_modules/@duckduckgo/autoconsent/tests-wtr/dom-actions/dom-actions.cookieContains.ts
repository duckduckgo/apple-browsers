import { expect } from '@esm-bundle/chai';
import { instantiateDomActions } from './utils';
import { DomActions } from '../../lib/dom-actions';

// must be run from dom-actions.cookieContains.html
describe('cookieContains', () => {
    let domActions: DomActions;

    before(() => {
        domActions = instantiateDomActions();
        document.cookie = 'testcookie1=testcookievalue1';
    });

    it('existing cookie matches by value', () => {
        const cookieContains = domActions.cookieContains('testcookie1');
        expect(cookieContains).true;
    });

    it('non-existent cookie does not match', () => {
        const cookieContains = domActions.cookieContains('nonexistentcookie');
        expect(cookieContains).false;
    });

    it('matches partial cookie value', () => {
        const cookieContains = domActions.cookieContains('cookie1');
        expect(cookieContains).true;
    });

    it('matches partial substring', () => {
        const cookieContains = domActions.cookieContains('cookie1=test');
        expect(cookieContains).true;
    });

    it('matches full cookie name=value', () => {
        const cookieContains = domActions.cookieContains('testcookie1=testcookievalue1');
        expect(cookieContains).true;
    });
});
