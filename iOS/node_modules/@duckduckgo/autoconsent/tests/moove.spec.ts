import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'Moove',
    ['https://impact.parkinson.org/', 'https://wamu.org/', 'https://www.phorest.com/', 'https://theposterclub.com/'],
    {},
);
