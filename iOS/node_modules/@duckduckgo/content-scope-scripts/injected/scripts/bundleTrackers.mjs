// eslint-disable-next-line no-redeclare
import fetch from 'node-fetch';
import { parseArgs, write } from '../../scripts/script-utils.js';

const tdsUrl = 'https://staticcdn.duckduckgo.com/trackerblocking/v4/tds.json';
const resp = await fetch(tdsUrl);
/**
 * Ignore 'unknown' type for now.
 * @type any
 */
const tds = await resp.json();

// Build a trie of tracker domains, starting with the broadest subdomain. Leaves are set to 1 to indicate success
// i.e. lookup['com']['example'] === 1 if example.com is a tracker domain
const trackerLookupTrie = {};
function insert(domainParts, node) {
    if (domainParts.length === 1) {
        node[domainParts[0]] = 1;
    } else if (node[domainParts[0]]) {
        insert(domainParts.slice(1), node[domainParts[0]]);
    } else {
        node[domainParts[0]] = {};
        insert(domainParts.slice(1), node[domainParts[0]]);
    }
}
Object.keys(tds.trackers).forEach((tracker) => {
    insert(tracker.split('.').reverse(), trackerLookupTrie);
});

const outputString = JSON.stringify(trackerLookupTrie);
const args = parseArgs(process.argv.slice(2), []);
if (args.output) {
    write([args.output], outputString);
} else {
    // Used by the extension code
    console.log(outputString);
}
