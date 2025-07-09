import generateCMPTests from '../playwright/runner';

generateCMPTests('kconsent', [
    'https://www.hanakat.fi/',
    'https://www.kesko.fi/',
    'https://www.k-ruoka.fi/kauppa/k-citymarket-turku-skanssi/aukioloajat',
]);
