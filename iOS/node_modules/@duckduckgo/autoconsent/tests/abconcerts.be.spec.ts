import generateCMPTests from '../playwright/runner';

generateCMPTests('abconcerts.be', ['https://www.abconcerts.be/en/', 'https://www.ccdewerf.be/nl/', 'https://www.deroma.be/nl/']);
