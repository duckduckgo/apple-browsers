import generateCMPTests from '../playwright/runner';

generateCMPTests('google.com', ['https://google.com/'], {
    skipRegions: ['US'],
});
