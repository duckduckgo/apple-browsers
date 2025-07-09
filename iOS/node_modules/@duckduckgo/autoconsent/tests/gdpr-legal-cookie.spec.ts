import generateCMPTests from '../playwright/runner';

generateCMPTests('gdpr-legal-cookie', ['https://www.lowa.co.uk/', 'https://corbo-apparel.com/', 'https://www.jhornig.com/']);
