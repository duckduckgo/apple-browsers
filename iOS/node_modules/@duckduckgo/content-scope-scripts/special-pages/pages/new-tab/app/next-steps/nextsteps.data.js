/**
 * @import enStrings from "./strings.json"
 * @import ntpStrings from "../strings.json"
 */
export const variants = {
    /** @param {(translationId: keyof enStrings) => string} t */
    bringStuff: (t) => ({
        id: 'bringStuff',
        icon: 'Bring-Stuff',
        title: t('nextSteps_bringStuff_title'),
        summary: t('nextSteps_bringStuff_summary'),
        actionText: t('nextSteps_bringStuff_actionText'),
    }),
    /** @param {(translationId: keyof enStrings) => string} t */
    defaultApp: (t) => ({
        id: 'defaultApp',
        icon: 'Default-App',
        title: t('nextSteps_defaultApp_title'),
        summary: t('nextSteps_defaultApp_summary'),
        actionText: t('nextSteps_defaultApp_actionText'),
    }),
    /** @param {(translationId: keyof enStrings) => string} t */
    blockCookies: (t) => ({
        id: 'blockCookies',
        icon: 'Cookie-Pops',
        title: t('nextSteps_blockCookies_title'),
        summary: t('nextSteps_blockCookies_summary'),
        actionText: t('nextSteps_blockCookies_actionText'),
    }),
    /** @param {(translationId: keyof enStrings) => string} t */
    emailProtection: (t) => ({
        id: 'emailProtection',
        icon: 'Email-Protection',
        title: t('nextSteps_emailProtection_title'),
        summary: t('nextSteps_emailProtection_summary'),
        actionText: t('nextSteps_emailProtection_actionText'),
    }),
    /** @param {(translationId: keyof enStrings) => string} t */
    duckplayer: (t) => ({
        id: 'duckplayer',
        icon: 'Tube-Clean',
        title: t('nextSteps_duckPlayer_title'),
        summary: t('nextSteps_duckPlayer_summary'),
        actionText: t('nextSteps_duckPlayer_actionText'),
    }),
    /** @param {(translationId: keyof enStrings) => string} t */
    addAppToDockMac: (t) => ({
        id: 'addAppToDockMac',
        icon: 'Dock-Add-Mac',
        title: t('nextSteps_addAppDockMac_title'),
        summary: t('nextSteps_addAppDockMac_summary'),
        actionText: t('nextSteps_addAppDockMac_actionText'),
        confirmationText: t('nextSteps_addAppDockMac_confirmationText'),
    }),
    /** @param {(translationId: keyof enStrings) => string} t */
    pinAppToTaskbarWindows: (t) => ({
        id: 'pinAppToTaskbarWindows',
        icon: 'Dock-Add-Windows',
        title: t('nextSteps_pinAppToTaskbarWindows_title'),
        summary: t('nextSteps_pinAppToTaskbarWindows_summary'),
        actionText: t('nextSteps_pinAppToTaskbarWindows_actionText'),
    }),
};

export const otherText = {
    /** @param {(translationId: keyof ntpStrings) => string} t */
    showMore: (t) => t('ntp_show_more'),
    /** @param {(translationId: keyof ntpStrings) => string} t */
    showLess: (t) => t('ntp_show_less'),
    /** @param {(translationId: keyof enStrings) => string} t */
    nextSteps_sectionTitle: (t) => t('nextSteps_sectionTitle'),
};

/**
 * @typedef {import('../../types/new-tab').NextStepsCardTypes} NextStepsCardTypes
 * @type {NextStepsCardTypes[]} cardsWithConfirmationText
 */
const cardsWithConfirmationText = ['addAppToDockMac'];

export const additionalCardStates = {
    hasConfirmationText: (/** @type {keyof variants} */ variantId) => cardsWithConfirmationText.includes(variantId),
};
