import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'cookie-manager-popup',
    ['https://www.focus-bikes.com/de_de/', 'https://www.gazelle.de/', 'https://www.kalkhoff-bikes.com/de_de/'],
    {},
);
