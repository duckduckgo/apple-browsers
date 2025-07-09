import generateCMPTests from '../playwright/runner';

generateCMPTests('burpee.com', [
    'https://www.burpee.com/',
    'https://www.knfilters.com/',
    'https://www.mossberg.com/',
    'https://www.hobbies.co.uk',
]);
