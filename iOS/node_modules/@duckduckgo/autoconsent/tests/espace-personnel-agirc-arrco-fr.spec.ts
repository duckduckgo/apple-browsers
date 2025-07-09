import generateCMPTests from '../playwright/runner';

generateCMPTests('espace-personnel.agirc-arrco.fr', [
    'https://espace-personnel.agirc-arrco.fr/public/signup/creation-compte/standard/1/votre-identite',
]);
