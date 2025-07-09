import generateCMPTests from '../playwright/runner';

generateCMPTests('linkedin.com', ['https://linkedin.com/'], {
    skipRegions: ['US'],
});
