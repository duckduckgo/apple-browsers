import generateCMPTests from '../playwright/runner';

generateCMPTests('cookieyes', [
    'https://www.cookieyes.com/',
    'https://www.primefaces.org/',
    'https://www.undip.ac.id/',
    'https://ttinteractive.com/',
    'https://www.chronofhorse.com/',
    'https://nl.flaminfitness.com/products/30l-tactical-backpack',
]);
