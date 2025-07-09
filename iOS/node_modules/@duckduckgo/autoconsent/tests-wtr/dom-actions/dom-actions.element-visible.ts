import { expect } from '@esm-bundle/chai';
import { instantiateDomActions } from './utils';
import { DomActions } from '../../lib/dom-actions';

// must be run from dom-actions.element-visible.html
describe('elementVisible', () => {
    let domActions: DomActions;

    beforeEach(() => {
        // Given
        domActions = instantiateDomActions();
    });

    describe('mode: "none"', () => {
        it('should return true if no elements found by selector', () => {
            // When + Then
            expect(domActions.elementVisible('#not-found', 'none')).to.be.true;
        });
        it('should return false if all elements are visible', () => {
            // When + Then
            expect(domActions.elementVisible(['#all-visible', 'button'], 'none')).to.be.false;
        });
        it('should return false if some elements are visible', () => {
            // When + Then
            expect(domActions.elementVisible(['#some-visible', 'button'], 'none')).to.be.false;
        });
        it('should return true if no elements are visible', () => {
            // When + Then
            expect(domActions.elementVisible(['#none-visible', 'button'], 'none')).to.be.true;
        });
    });
    describe('mode: "any"', () => {
        it('should return false if no elements found by selector', () => {
            // When + Then
            expect(domActions.elementVisible('#not-found', 'any')).to.be.false;
        });
        it('should return false if no elements are visible', () => {
            // When + Then
            expect(domActions.elementVisible(['#none-visible', 'button'], 'any')).to.be.false;
        });
        it('should return true if some elements are visible', () => {
            // When + Then
            expect(domActions.elementVisible(['#some-visible', 'button'], 'any')).to.be.true;
        });
        it('should return true if all elements are visible', () => {
            // When + Then
            expect(domActions.elementVisible(['#all-visible', 'button'], 'any')).to.be.true;
        });
    });
    describe('mode: "all"', () => {
        it('should return false if no elements found by selector', () => {
            // When + Then
            expect(domActions.elementVisible('#not-found', 'all')).to.be.false;
        });
        it('should return false if no elements are visible', () => {
            // When + Then
            expect(domActions.elementVisible(['#none-visible', 'button'], 'all')).to.be.false;
        });
        it('should return false if some elements are visible', () => {
            // When + Then
            expect(domActions.elementVisible(['#some-visible', 'button'], 'all')).to.be.false;
        });
        it('should return true if all elements are visible', () => {
            // When + Then
            expect(domActions.elementVisible(['#all-visible', 'button'], 'all')).to.be.true;
        });
    });
});
