import generateCMPTests from '../playwright/runner';

generateCMPTests('Sirdata', ['https://www.comment-economiser.fr/'], {
    skipRegions: ['US'],
});
