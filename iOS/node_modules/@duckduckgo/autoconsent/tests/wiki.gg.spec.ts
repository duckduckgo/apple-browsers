import generateCMPTests from '../playwright/runner';

generateCMPTests('wiki.gg', [
    'https://pve.proxmox.com/wiki/Main_Page',
    'https://helldivers.wiki.gg/wiki/Helldivers_Wiki',
    'https://enshrouded.wiki.gg/wiki/Main_Page',
    'https://calamitymod.wiki.gg/wiki/Calamity_Mod_Wiki',
    'https://abioticfactor.wiki.gg/wiki/Abiotic_Factor_Wiki',
]);
