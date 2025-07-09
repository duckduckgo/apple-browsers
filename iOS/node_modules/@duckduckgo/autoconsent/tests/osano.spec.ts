import generateCMPTests from '../playwright/runner';

generateCMPTests('osano', ['https://www.weathertech.com/', 'https://ping.com/en-us/', 'https://www.flowrestling.org/']);
