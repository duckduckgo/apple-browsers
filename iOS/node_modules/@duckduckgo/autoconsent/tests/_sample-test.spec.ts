import coverageData from '../data/coverage.json';
import generateCMPTests from '../playwright/runner';

const region = (process.env.REGION || 'US').trim();
const nSites = parseInt(process.env.NSITES || '1');

Object.keys(coverageData).forEach((name) => {
    if (!coverageData[name][region]) {
        // no coverage in this region
        return;
    }
    const siteList = coverageData[name][region].exampleSites.slice(0, nSites);
    generateCMPTests(name, siteList, {
        testOptIn: false,
    });
});
