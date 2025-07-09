import generateCMPTests from '../playwright/runner';

generateCMPTests('nos.nl', ['https://nos.nl/'], {
    testSelfTest: false,
});
