import generateCMPTests from '../playwright/runner';

generateCMPTests('macaron', [
    'https://www.hotelamourparis.fr/',
    'https://www.sofitel-washington-dc.com/',
    'https://www.fairmont-montecarlo.com/en/',
]);
