import generateCMPTests from '../playwright/runner';

generateCMPTests('xnxx-com', ['https://xnxx.com/', 'https://xvideos.com/'], {
    onlyRegions: ['US'],
});
