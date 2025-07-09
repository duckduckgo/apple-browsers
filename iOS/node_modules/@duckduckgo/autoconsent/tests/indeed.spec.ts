import generateCMPTests from '../playwright/runner';

generateCMPTests('indeed.com', ['https://indeed.com'], {
    onlyRegions: ['US'],
});
