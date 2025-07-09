#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { parse } from 'csv-parse/sync';
import { getDomain } from 'tldts-experimental';
import { Readable } from 'stream';
import { finished } from 'stream/promises';

const rulesDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '../rules');
const dataDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '../data');

const easylistRevision = fs.readFileSync(path.join(rulesDir, 'filterlists', 'easylist_revision.txt'), 'utf-8');
const domainSpecificLists = [
    'easylist_cookie_specific_uBO.txt',
    'easylist_cookie_specific_hide.txt',
    'easylist_cookie_international_specific_hide.txt',
];

const MAX_DOMAIN_RANK = 100000;

/** @typedef {{ rules: Record<string, string[]>}} FilterlistJSON */

/** @type {Map<string, string>} */
let domainMap;

/**
 * Processes a list containing domain-specific cosmetic rules, filters
 * out unsupported rules and removes longtail domain rules
 * @param {String} listFileName
 */
async function processDomainSpecificFilterList(listFileName) {
    console.log(`Processing ${listFileName}`);
    const data = fs.readFileSync(path.join(rulesDir, 'filterlists', listFileName), 'utf-8');
    const lines = data.split('\n');
    /** @type {FilterlistJSON} */
    const filterlistJSON = { rules: {} };

    // Remove comments and network rules, which take a different format:
    // !  at start of line indicates comment
    // || at start of line indicates network rule
    const filteredLines = lines.filter((line) => !line.startsWith('!') && !line.startsWith('||'));
    // Dump rules into json structure for parsing
    for (const rule of filteredLines) {
        const splitRule = rule.split('##');
        const target = splitRule[0];
        const action = splitRule[1];

        if (!action) {
            continue;
        }

        if (!filterlistJSON.rules[target]) {
            filterlistJSON.rules[target] = [action];
        } else {
            filterlistJSON.rules[target].push(action);
        }
    }

    // Remove any targets that contain a +js rule. we do it this way because
    // when a target has a :js rule, we must also remove any css rules
    for (const item in filterlistJSON.rules) {
        const containsJS = filterlistJSON.rules[item].some((filter) => filter.includes('+js'));
        if (containsJS) {
            delete filterlistJSON.rules[item];
        }
    }

    for (const item in filterlistJSON.rules) {
        let domains;

        if (item.includes(',')) {
            domains = item.split(',');
        } else {
            domains = [item];
        }

        const filteredDomains = domains.filter((domain) => {
            // Don't filter global rules which don't have a domain
            if (domain === '') {
                return true;
            }

            const tlDomain = getDomain(domain);
            return domainMap.has(tlDomain);
        });

        // If no domains meet cutoff, remove rule entirely. If one or more
        // domains meet cutoff, remove those that don't
        if (filteredDomains.length === 0) {
            delete filterlistJSON.rules[item];
        } else if (filteredDomains.length !== domains.length) {
            const filteredDomainString = filteredDomains.join(',');
            filterlistJSON.rules[filteredDomainString] = filterlistJSON.rules[item];
            delete filterlistJSON.rules[item];
        }
    }

    await convertAndWriteABP(filterlistJSON, listFileName);
}

/**
 * Fetch domain popularity data from Tranco and load it into a Map for querying
 */
async function loadTrancoList() {
    const csvLocation = path.resolve(path.join(dataDir, 'top-1m.csv'));
    if (!fs.existsSync(csvLocation)) {
        console.log('Fetching latest Tranco list..');
        // Download most recent list from https://tranco-list.eu using API
        const date = new Date();
        let available;
        let download;

        do {
            const formattedDate = date.toISOString().split('T')[0].replace('/', '');
            const res = await (await fetch(`https://tranco-list.eu/api/lists/date/${formattedDate}`)).json();

            available = res.available;
            download = res.download;

            // Decrement date until a daily list is available
            date.setTime(date.getTime() - 7 * 24 * 3600000);
        } while (!available);

        const listData = await fetch(download);
        await finished(Readable.fromWeb(listData.body).pipe(fs.createWriteStream(csvLocation)));
    }

    if (typeof domainMap !== 'object') {
        const trancoCSV = fs.readFileSync(path.join(dataDir, 'top-1m.csv'), 'utf-8');
        /** @type {string[][]} */
        const records = parse(trancoCSV, {
            columns: false,
            skip_empty_lines: true,
        });

        domainMap = new Map();

        records.slice(0, MAX_DOMAIN_RANK).forEach(([key, value]) => {
            domainMap.set(value, key);
        });
    }
}

/**
 * Convert filter list to ABP format and write to disk
 * @param {FilterlistJSON} JSONList
 * @param {String} fileName
 */
function convertAndWriteABP(JSONList, fileName) {
    return new Promise((resolve, reject) => {
        const fileLocation = path.join(rulesDir, 'filterlists', fileName);
        const stream = fs.createWriteStream(fileLocation, { flags: 'w' });

        stream.once('open', () => {
            for (const item in JSONList.rules) {
                JSONList.rules[item].forEach((filter) => {
                    const abpRule = item + '##' + filter;
                    stream.write(abpRule + '\n');
                });
            }
            stream.end();
        });

        stream.on('finish', () => {
            console.log(`ABP format list written to ${fileLocation}`);
            resolve();
        });

        stream.on('error', (err) => {
            console.error(`An error occurred while writing ${fileLocation}: ${err.message}`);
        });
    });
}

/**
 * Combine all filter lists into a single filterlist.txt
 */
function combineFilterLists() {
    // TODO: consider using python-abp (flrender) to generate filterlist properly
    const filterlistContent = `[Adblock Plus 2.0]
! Title: CPM Cosmetic Filter List
! Based on EasyList ${easylistRevision}
! DO NOT EDIT MANUALLY, your changes will be lost
! Generated on ${new Date().toISOString()}
!------------------------General element hiding rules-------------------------!
${fs.readFileSync(path.join(rulesDir, 'filterlists', 'easylist_cookie_general_hide.txt'), 'utf-8')}
!------------------------Specific element hiding rules------------------------!
${fs.readFileSync(path.join(rulesDir, 'filterlists', 'easylist_cookie_specific_hide.txt'), 'utf-8')}
${fs.readFileSync(path.join(rulesDir, 'filterlists', 'easylist_cookie_specific_uBO.txt'), 'utf-8')}
!------------------------Rules for international sites------------------------!
${fs.readFileSync(path.join(rulesDir, 'filterlists', 'easylist_cookie_international_specific_hide.txt'), 'utf-8')}
!---------------------------------Allowlists----------------------------------!
${fs.readFileSync(path.join(rulesDir, 'filterlists', 'easylist_cookie_allowlist_general_hide.txt'), 'utf-8')}
!--------------------------------DDG overrides--------------------------------!
${fs.readFileSync(path.join(rulesDir, 'filterlists', 'overrides.txt'), 'utf-8')}
`;

    fs.writeFile(path.join(rulesDir, 'filterlist.txt'), filterlistContent, () => console.log('Written filterlist.txt'));
}

/**
 * Parse and refine lists using domain popularity, then combine them and write filterlist.txt
 */
async function rebuildFilterList() {
    await loadTrancoList();

    for (const list of domainSpecificLists) {
        await processDomainSpecificFilterList(list);
    }

    combineFilterLists();
}

rebuildFilterList();
