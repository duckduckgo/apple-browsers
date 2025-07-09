import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'Adroll',
    [
        'https://www.adroll.com/',
        'https://www.appliancewhse.com/',
        'https://www.michiganhumane.org/',
        'https://audioplugin.deals/',
        'https://www.mhu.edu/',
    ],
    {
        skipRegions: ['US'],
    },
);
