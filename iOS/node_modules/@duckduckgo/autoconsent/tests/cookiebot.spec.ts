import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'Cybotcookiebot',
    [
        'https://www.wohnen.de/',
        'https://www.zwilling.com/de/',
        'https://forums.cpanel.net/',
        'https://tfl.gov.uk',
        // "https://www.ab-in-den-urlaub.de/", // often blocked by botwall
        'https://www.vatera.hu/',
    ],
    {
        skipRegions: ['US'],
    },
);

generateCMPTests(
    'Cybotcookiebot',
    [
        'https://dl.acm.org/',
        'https://www.ifm.org/',
        'https://www.thule.com/',
        'https://www.dezeen.com/',
        'https://www.l3harris.com/',
        'https://www.gog.com/',
    ],
    {},
);
