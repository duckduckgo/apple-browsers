import generateCMPTests from '../playwright/runner';

generateCMPTests('Complianz notice', ['https://yrc.com/', 'https://www.worldometers.info/'], {
    skipRegions: ['GB'],
});
