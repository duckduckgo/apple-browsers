import generateCMPTests from '../playwright/runner';

generateCMPTests('com_oil', ['https://www.farbtoner.com/', 'https://www.elektro4000.de/', 'http://edelholzverkauf.de/'], {
    skipRegions: ['GB'],
    testOptIn: false,
    testSelfTest: false,
});
