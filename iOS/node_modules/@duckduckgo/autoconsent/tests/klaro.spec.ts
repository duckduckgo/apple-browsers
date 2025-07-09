import generateCMPTests from '../playwright/runner';

generateCMPTests('Klaro', [
    'https://heyklaro.com/',
    'https://www.zeitraum-moebel.de/',
    'https://repisalud.isciii.es/',
    'https://www.innogames.com/',
    'https://www.lebenslauf.de/',
    // 'https://dspace.library.stonybrook.edu', // polyfills Promise so playwright doesn't work
]);
