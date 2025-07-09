import { expect } from '@esm-bundle/chai';
import Autoconsent from '../../lib/web';

describe('Autoconsent.findCmp', () => {
    let autoconsent: Autoconsent;

    beforeEach(() => {
        // Given
        autoconsent = new Autoconsent((msg) => Promise.resolve(), {
            enabled: false, // bypass initialization
            autoAction: null,
        });
    });

    it('should detect a CMP in a page', async () => {
        autoconsent.addDeclarativeCMP({
            name: 'test',
            detectCmp: [{ exists: '#privacy-test-page-cmp-test' }],
            detectPopup: [],
            optIn: [],
            optOut: [],
        });
        const found = await autoconsent.findCmp(0);
        expect(found).to.have.length(1);
        expect(found[0].name).to.equal('test');
    });

    it('can return more than 1 match', async () => {
        autoconsent.addDeclarativeCMP({
            name: 'test',
            detectCmp: [{ exists: '#privacy-test-page-cmp-test' }],
            detectPopup: [],
            optIn: [],
            optOut: [],
        });
        autoconsent.addDeclarativeCMP({
            name: 'test2',
            detectCmp: [{ exists: '#reject-all' }],
            detectPopup: [],
            optIn: [],
            optOut: [],
        });
        const found = await autoconsent.findCmp(0);
        expect(found).to.have.length(2);
    });

    it('returns empty if no rules match', async () => {
        autoconsent.addDeclarativeCMP({
            name: 'test',
            detectCmp: [{ exists: '#privacy-test-page-cmp-test2' }],
            detectPopup: [],
            optIn: [],
            optOut: [],
        });
        autoconsent.addDeclarativeCMP({
            name: 'test2',
            detectCmp: [{ exists: '#reject-all2' }],
            detectPopup: [],
            optIn: [],
            optOut: [],
        });
        const found = await autoconsent.findCmp(0);
        expect(found).to.have.length(0);
    });

    it('does not return a rule if the runContext does not match: frame-only rule', async () => {
        autoconsent.addDeclarativeCMP({
            name: 'runContextRule',
            runContext: { main: false, frame: true },
            detectCmp: [{ exists: '#privacy-test-page-cmp-test' }],
            detectPopup: [],
            optIn: [],
            optOut: [],
        });
        autoconsent.addDeclarativeCMP({
            name: 'test',
            detectCmp: [{ exists: '#reject-all' }],
            detectPopup: [],
            optIn: [],
            optOut: [],
        });
        const found = await autoconsent.findCmp(0);
        expect(found).to.have.length(1);
        expect(found[0].name).to.equal('test');
    });

    it('does not return a rule if the runContext does not match: urlPattern', async () => {
        autoconsent.addDeclarativeCMP({
            name: 'runContextRule',
            runContext: { urlPattern: '^https://(www\\.)?example\\.com/' },
            detectCmp: [{ exists: '#privacy-test-page-cmp-test' }],
            detectPopup: [],
            optIn: [],
            optOut: [],
        });
        autoconsent.addDeclarativeCMP({
            name: 'test',
            detectCmp: [{ exists: '#reject-all' }],
            detectPopup: [],
            optIn: [],
            optOut: [],
        });
        const found = await autoconsent.findCmp(0);
        expect(found).to.have.length(1);
        expect(found[0].name).to.equal('test');
    });

    it('only matches the site-specific rule if urlPattern matches', async () => {
        autoconsent.addDeclarativeCMP({
            name: 'runContextRule',
            runContext: { urlPattern: '^http://localhost' },
            detectCmp: [{ exists: '#privacy-test-page-cmp-test' }],
            detectPopup: [],
            optIn: [],
            optOut: [],
        });
        autoconsent.addDeclarativeCMP({
            name: 'test',
            detectCmp: [{ exists: '#reject-all' }],
            detectPopup: [],
            optIn: [],
            optOut: [],
        });
        const found = await autoconsent.findCmp(0);
        expect(found).to.have.length(1);
        expect(found[0].name).to.equal('runContextRule');
    });
});
