import generateCMPTests from '../playwright/runner';

generateCMPTests('borlabs', ['https://www.kesselheld.de/'], {
    skipRegions: ['US'],
});
