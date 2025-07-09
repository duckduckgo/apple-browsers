import generateCMPTests from '../playwright/runner';

generateCMPTests('Tealium', [
    // 'https://www.bahn.de/', // uses shadow DOM, see https://app.asana.com/0/1201844467387842/1202635343225979/f
    'https://www.forcepoint.com/',
    'https://www.lufthansa.com/de/en/homepage',
    'http://www.tui.com/',
    'http://www.minted.com/',
    'http://help.brother-usa.com/',
    'http://www.americangreetings.com/',
    'http://www.hagerty.com/',
]);
