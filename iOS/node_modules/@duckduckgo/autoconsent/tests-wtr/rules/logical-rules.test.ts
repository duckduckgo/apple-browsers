import { expect } from '@esm-bundle/chai';
import { AutoConsentCMP } from '../../lib/cmps/base';
import AutoConsent from '../../lib/web';
import { DomActions } from '../../lib/dom-actions';
import sinon from 'sinon';

describe('AutoConsentCMP', () => {
    let autoconsentMock: AutoConsent;
    let domActionsMock: sinon.SinonStubbedInstance<DomActions>;
    let cmp: AutoConsentCMP;

    beforeEach(() => {
        domActionsMock = sinon.createStubInstance(DomActions);
        autoconsentMock = {
            config: {
                // @ts-expect-error - it's a mock!
                logs: {},
            },
            domActions: domActionsMock,
        };
        cmp = new AutoConsentCMP(
            {
                name: 'test',
                detectCmp: [],
                detectPopup: [],
                optOut: [],
                optIn: [],
                test: [],
            },
            autoconsentMock,
        );
    });

    describe('negating rules', () => {
        it('correctly handles non-negated rules', async () => {
            domActionsMock.cookieContains.returns(false);
            expect(await cmp._runRulesSequentially([{ cookieContains: 'testcookie1' }])).to.equal(false);
        });

        it('correctly negates true results', async () => {
            domActionsMock.cookieContains.returns(true);
            expect(await cmp._runRulesSequentially([{ cookieContains: 'testcookie1', negated: true }])).to.equal(false);
        });

        it('correctly negates false results', async () => {
            domActionsMock.cookieContains.returns(false);
            expect(await cmp._runRulesSequentially([{ cookieContains: 'testcookie1', negated: true }])).to.equal(true);
        });

        it('correctly negates results of "any" rules', async () => {
            domActionsMock.cookieContains.returns(false);
            expect(
                await cmp._runRulesSequentially([
                    {
                        any: [{ cookieContains: 'testcookie1' }, { cookieContains: 'testcookie2' }],
                        negated: true,
                    },
                ]),
            ).to.equal(true);
        });

        it('does not negate empty results', async () => {
            // @ts-expect-error - it's a mock!
            expect(await cmp._runRulesSequentially([{ unrecognizedRule: 'bla', negated: true }])).to.equal(false);
        });
    });

    describe('"any" rules', () => {
        it('returns true as soon as one of the steps returns true', async () => {
            domActionsMock.cookieContains.returns(false);
            expect(
                await cmp._runRulesSequentially([
                    {
                        any: [{ cookieContains: 'testcookie1', negated: true }, { cookieContains: 'testcookie2' }],
                    },
                ]),
            ).to.equal(true);
            expect(domActionsMock.cookieContains.callCount).to.equal(1);
        });

        it('does not give up until it tries all the options', async () => {
            domActionsMock.cookieContains.returns(false);
            expect(
                await cmp._runRulesSequentially([
                    {
                        any: [{ cookieContains: 'testcookie1' }, { cookieContains: 'testcookie2', negated: true }],
                    },
                ]),
            ).to.equal(true);
            expect(domActionsMock.cookieContains.callCount).to.equal(2);
        });

        it('returns false if all steps return false', async () => {
            domActionsMock.cookieContains.returns(false);
            expect(
                await cmp._runRulesSequentially([
                    {
                        any: [{ cookieContains: 'testcookie1' }, { cookieContains: 'testcookie2' }],
                    },
                ]),
            ).to.equal(false);
            expect(domActionsMock.cookieContains.callCount).to.equal(2);
        });
    });
});
