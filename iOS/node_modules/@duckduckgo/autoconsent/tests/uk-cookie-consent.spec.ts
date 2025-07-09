import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'UK Cookie Consent',
    ['https://ondinebio.mystagingwebsite.com/', 'https://www.equinoxpub.com/home/', 'https://london.msg.com/'],
    {},
);
