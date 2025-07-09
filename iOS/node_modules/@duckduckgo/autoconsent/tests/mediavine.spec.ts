import generateCMPTests from '../playwright/runner';

generateCMPTests('Mediavine', ['https://www.passionforsavings.com/', 'https://europeupclose.com/'], {
    skipRegions: ['US'],
});
