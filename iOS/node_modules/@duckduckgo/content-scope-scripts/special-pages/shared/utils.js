// All locales supported by c-s-s translations as of 2025-06
// Using regional variants in case we want to extend support for currency in the future
export const translationsLocales = {
    en: 'en-US',
    nl: 'nl-NL',
    fr: 'fr-FR',
    de: 'de-DE',
    it: 'it-IT',
    pl: 'pl-PL',
    pt: 'pt-PT',
    ru: 'ru-RU',
    es: 'es-ES',
};

/**
 * @param {keyof typeof translationsLocales} locale
 * @returns {Intl.NumberFormat}
 */
export const getLocalizedNumberFormatter = (locale) => {
    const localeToUse = translationsLocales[locale] || 'en-US'; // Fallback to English if locale is not supported

    return new Intl.NumberFormat(localeToUse);
};
