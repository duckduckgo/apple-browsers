import generateCMPTests from '../playwright/runner';

generateCMPTests('Yahoo', ['https://www.yahoo.com/'], {
    skipRegions: ['US'],
});
