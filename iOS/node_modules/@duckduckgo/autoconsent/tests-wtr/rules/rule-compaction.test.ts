import { expect } from '@esm-bundle/chai';
import { encodeRules, decodeRules } from '../../lib/encoding';
import { AutoConsentCMPRule } from '../../lib/rules';
import { autoconsent } from '../../rules/rules.json';
import AutoConsent from '../../lib/web';

describe('RuleCompaction', () => {
    it('decodeRules(encodeRules(rules)) preserves required attributes', () => {
        const rules: AutoConsentCMPRule[] = JSON.parse(JSON.stringify(autoconsent));

        const encoded = encodeRules(rules);
        const decoded = decodeRules(encoded);
        expect(rules.length).to.equal(decoded.length);
        const ignoredKeys = ['comment', 'optIn', 'vendorUrl'];
        for (let i = 0; i < rules.length; i++) {
            const originalRule = rules[i];
            // ensure that runContext exists
            if (!originalRule.runContext) {
                originalRule.runContext = {};
            }
            // Default value for test and prehideSelectors is empty array
            originalRule.test = originalRule.test || [];
            originalRule.prehideSelectors = originalRule.prehideSelectors || [];

            const finalRule = decoded[i];
            for (const key of Object.keys(originalRule).filter((k) => !ignoredKeys.includes(k))) {
                // @ts-expect-error Type checker doesn't like us using dynamic attributes here
                expect(finalRule[key]).to.deep.equal(originalRule[key], `${key} is correctly preserved`);
            }
        }
        const originalLength = JSON.stringify(rules).length;
        const encodedLength = JSON.stringify(encoded).length;
        // > 50% size reduction
        // Tuple encoding: 45%
        // Exists lookup:  53%
        // Visible lookup: 70%
        // waitForThenClick: 73%
        console.log('Original Size:', originalLength, 'Encoded Size:', encodedLength);
        expect((originalLength - encodedLength) / encodedLength).to.be.greaterThan(0.75);
    });

    it('decodeRules: refuses to decode future formats', () => {
        expect(() => decodeRules({ v: 2, s: [], r: [] })).to.throw('Unsupported rule format.');
    });

    it('decodeRules: runContext flags are extendable', () => {
        // We can add new flags on the left-hand side of the runContext field and old clients
        // will still be able to parse the lower two.
        const decoded = decodeRules({
            v: 1,
            s: [],
            r: [
                [1, 'test_extra_flag', 0, '', 112, [], [], [], [], [], {}],
                [1, 'test', 0, '', 10, [], [], [], [], [], {}],
            ],
        });
        expect(decoded[0].runContext).to.eql({ main: true });
        expect(decoded[1].runContext).to.eql({ main: true, frame: false });
    });

    it('decodeRules: filters out rules that use newer step/eval rules', () => {
        const decoded = decodeRules({
            v: 1,
            s: [],
            r: [
                // @ts-expect-error Test rule has different shape on purpose
                [10, 'test_future', 0, '', 112, [], [], [], [], [], [], {}],
                [1, 'test', 0, '', 10, [], [], [], [], [], {}],
            ],
        });
        expect(decoded).to.have.length(1);
        expect(decoded[0].name).to.equal('test');
    });
});

describe('AutoConsent', () => {
    it('parseDeclarativeRules: filters out rules that use newer step/eval rules', () => {
        const autoconsent = new AutoConsent(() => Promise.resolve());
        const dynamicRuleCount = autoconsent.rules.length;
        autoconsent.parseDeclarativeRules({
            autoconsent: [],
            compact: encodeRules([
                {
                    name: 'test',
                    detectCmp: [{ exists: '#cmp' }],
                    detectPopup: [{ visible: '#cmp' }],
                    optOut: [{ click: '#opt-out' }],
                    optIn: [],
                    minimumRuleStepVersion: 1,
                },
                {
                    name: 'future_rule',
                    detectCmp: [{ exists: '#cmp' }],
                    detectPopup: [{ visible: '#cmp' }],
                    optOut: [{ click: '#opt-out' }],
                    optIn: [],
                    minimumRuleStepVersion: 6,
                },
            ]),
        });
        expect(autoconsent.rules).to.have.length(dynamicRuleCount + 1);
    });
});
