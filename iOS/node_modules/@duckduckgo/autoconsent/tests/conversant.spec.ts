import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'Conversant',
    ['https://www.irishcentral.com/', 'https://screencrush.com/', 'https://starcrush.com/', 'https://mooseradio.com/'],
    {
        skipRegions: ['US'],
    },
);
