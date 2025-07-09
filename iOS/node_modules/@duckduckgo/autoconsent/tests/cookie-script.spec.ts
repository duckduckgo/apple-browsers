import generateCMPTests from '../playwright/runner';

generateCMPTests('cookie-script', ['https://arzt-auskunft.de'], {
    skipRegions: ['US', 'FR', 'GB'],
});
