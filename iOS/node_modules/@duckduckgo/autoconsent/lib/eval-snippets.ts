// eslint-disable-next-line @typescript-eslint/ban-ts-comment
// @ts-nocheck

export const snippets = {
    // code-based rules
    EVAL_0: () => console.log(1),
    EVAL_CONSENTMANAGER_1: () => window.__cmp && typeof __cmp('getCMPData') === 'object',
    EVAL_CONSENTMANAGER_2: () => !__cmp('consentStatus').userChoiceExists,
    EVAL_CONSENTMANAGER_3: () => __cmp('setConsent', 0),
    EVAL_CONSENTMANAGER_4: () => __cmp('setConsent', 1),
    EVAL_CONSENTMANAGER_5: () => __cmp('consentStatus').userChoiceExists,
    EVAL_COOKIEBOT_1: () => !!window.Cookiebot,
    EVAL_COOKIEBOT_2: () => !window.Cookiebot.hasResponse && window.Cookiebot.dialog?.visible === true,
    EVAL_COOKIEBOT_3: () => window.Cookiebot.withdraw() || true,
    EVAL_COOKIEBOT_4: () => window.Cookiebot.hide() || true,
    EVAL_COOKIEBOT_5: () => window.Cookiebot.declined === true,
    EVAL_KLARO_1: () => {
        const config = globalThis.klaroConfig || (globalThis.klaro?.getManager && globalThis.klaro.getManager().config);
        if (!config) {
            // with no klaro globals, we can't test on this page
            return true;
        }
        const optionalServices = (config.services || config.apps).filter((s) => !s.required).map((s) => s.name);
        if (klaro && klaro.getManager) {
            const manager = klaro.getManager();
            return optionalServices.every((name) => !manager.consents[name]);
        } else if (klaroConfig && klaroConfig.storageMethod === 'cookie') {
            const cookieName = klaroConfig.cookieName || klaroConfig.storageName;
            const consents = JSON.parse(
                decodeURIComponent(
                    document.cookie
                        .split(';')
                        .find((c) => c.trim().startsWith(cookieName))
                        .split('=')[1],
                ),
            );
            return Object.keys(consents)
                .filter((k) => optionalServices.includes(k))
                .every((k) => consents[k] === false);
        }
    },
    EVAL_KLARO_OPEN_POPUP: () => {
        klaro.show(undefined, true);
    },
    EVAL_KLARO_TRY_API_OPT_OUT: () => {
        if (window.klaro && typeof klaro.show === 'function' && typeof klaro.getManager === 'function') {
            try {
                // opt-out directly via API
                klaro.getManager().changeAll(false);
                klaro.getManager().saveAndApplyConsents();
                return true;
            } catch (e) {
                console.warn(e);
                return false;
            }
        }
        return false;
    },
    EVAL_ONETRUST_1: () => window.OnetrustActiveGroups.split(',').filter((s) => s.length > 0).length <= 1,
    EVAL_TRUSTARC_TOP: () => window && window.truste && window.truste.eu.bindMap.prefCookie === '0',
    EVAL_TRUSTARC_FRAME_TEST: () => window && window.QueryString && window.QueryString.preferences === '0',
    EVAL_TRUSTARC_FRAME_GTM: () => window && window.QueryString && window.QueryString.gtm === '1',

    // declarative rules
    EVAL_ADOPT_TEST: () => !!localStorage.getItem('adoptConsentMode'),
    EVAL_ADULTFRIENDFINDER_TEST: () => !!localStorage.getItem('cookieConsent'),
    EVAL_BAHN_TEST: () => utag.gdpr.getSelectedCategories().length === 1,
    EVAL_BIGCOMMERCE_CONSENT_MANAGER_DETECT: () => !!(window.consentManager && window.consentManager.version),
    EVAL_BORLABS_0: () =>
        !JSON.parse(
            decodeURIComponent(
                document.cookie
                    .split(';')
                    .find((c) => c.indexOf('borlabs-cookie') !== -1)
                    .split('=', 2)[1],
            ),
        ).consents.statistics,
    EVAL_CC_BANNER2_0: () => !!document.cookie.match(/sncc=[^;]+D%3Dtrue/),
    EVAL_COINBASE_0: () =>
        JSON.parse(decodeURIComponent(document.cookie.match(/cm_(eu|default)_preferences=([0-9a-zA-Z\\{\\}\\[\\]%:]*);?/)[2])).consent
            .length <= 1,
    EVAL_COOKIE_LAW_INFO_0: () => CLI.disableAllCookies() || CLI.reject_close() || true,
    EVAL_COOKIE_LAW_INFO_DETECT: () => !!window.CLI,
    EVAL_COOKIE_MANAGER_POPUP_0: () =>
        JSON.parse(
            document.cookie
                .split(';')
                .find((c) => c.trim().startsWith('CookieLevel'))
                .split('=')[1],
        ).social === false,
    EVAL_COOKIEALERT_0: () => document.querySelector('body').removeAttribute('style') || true,
    EVAL_COOKIEALERT_1: () => document.querySelector('body').removeAttribute('style') || true,
    EVAL_COOKIEALERT_2: () => window.CookieConsent.declined === true,
    EVAL_COOKIEFIRST_0: () =>
        ((o) => o.performance === false && o.functional === false && o.advertising === false)(
            JSON.parse(
                decodeURIComponent(
                    document.cookie
                        .split(';')
                        .find((c) => c.indexOf('cookiefirst') !== -1)
                        .trim(),
                ).split('=')[1],
            ),
        ),
    EVAL_COOKIEFIRST_1: () =>
        document
            .querySelectorAll('button[data-cookiefirst-accent-color=true][role=checkbox]:not([disabled])')
            .forEach((i) => i.getAttribute('aria-checked') === 'true' && i.click()) || true,
    EVAL_COOKIEINFORMATION_0: () => CookieInformation.declineAllCategories() || true,
    EVAL_COOKIEINFORMATION_1: () => CookieInformation.submitAllCategories() || true,
    EVAL_ETSY_0: () =>
        document.querySelectorAll('.gdpr-overlay-body input').forEach((toggle) => {
            toggle.checked = false;
        }) || true,
    EVAL_ETSY_1: () => document.querySelector('.gdpr-overlay-view button[data-wt-overlay-close]').click() || true,
    EVAL_EZOIC_0: () => ezCMP.handleAcceptAllClick(),
    EVAL_FIDES_DETECT_POPUP: () => window.Fides?.initialized,
    EVAL_GDPR_LEGAL_COOKIE_DETECT_CMP: () => !!window.GDPR_LC,
    EVAL_GDPR_LEGAL_COOKIE_TEST: () => !!window.GDPR_LC?.userConsentSetting,
    EVAL_IUBENDA_0: () =>
        document.querySelectorAll('.purposes-item input[type=checkbox]:not([disabled])').forEach((x) => {
            if (x.checked) x.click();
        }) || true,
    EVAL_IUBENDA_1: () => !!document.cookie.match(/_iub_cs-\d+=/),
    EVAL_MEDIAVINE_0: () =>
        document.querySelectorAll('[data-name="mediavine-gdpr-cmp"] input[type=checkbox]').forEach((x) => x.checked && x.click()) || true,
    EVAL_MICROSOFT_0: () =>
        Array.from(document.querySelectorAll('div > button'))
            .filter((el) => el.innerText.match('Reject|Ablehnen'))[0]
            .click() || true,
    EVAL_MICROSOFT_1: () =>
        Array.from(document.querySelectorAll('div > button'))
            .filter((el) => el.innerText.match('Accept|Annehmen'))[0]
            .click() || true,
    EVAL_MICROSOFT_2: () => !!document.cookie.match('MSCC|GHCC'),
    EVAL_MOOVE_0: () =>
        document.querySelectorAll('#moove_gdpr_cookie_modal input').forEach((i) => {
            if (!i.disabled) i.checked = i.name === 'moove_gdpr_strict_cookies' || i.id === 'moove_gdpr_strict_cookies';
        }) || true,
    EVAL_NHNIEUWS_TEST: () => !!localStorage.getItem('psh:cookies-seen'),
    EVAL_OSANO_DETECT: () => !!window.Osano?.cm?.dialogOpen,
    EVAL_PANDECTES_TEST: () =>
        document.cookie.includes('_pandectes_gdpr=') &&
        JSON.parse(
            atob(
                document.cookie
                    .split(';')
                    .find((s) => s.trim().startsWith('_pandectes_gdpr'))
                    .split('=')[1],
            ),
        ).status === 'deny',
    EVAL_POVR_GOBACK: () => window.history.back() || true,
    EVAL_PUBTECH_0: () =>
        document.cookie.includes('euconsent-v2') &&
        (document.cookie.match(/.YAAAAAAAAAAA/) || document.cookie.match(/.aAAAAAAAAAAA/) || document.cookie.match(/.YAAACFgAAAAA/)),
    EVAL_REMARKABLE_TEST: () => !!localStorage.getItem('rmCookieConsent'),
    EVAL_SHOPIFY_TEST: () =>
        document.cookie.includes('gdpr_cookie_consent=0') ||
        (document.cookie.includes('_tracking_consent=') &&
            JSON.parse(
                decodeURIComponent(
                    document.cookie
                        .split(';')
                        .find((s) => s.trim().startsWith('_tracking_consent'))
                        .split('=')[1],
                ),
            ).purposes.a === false),
    EVAL_SKYSCANNER_TEST: () => document.cookie.match(/gdpr=[^;]*adverts:::false/) && !document.cookie.match(/gdpr=[^;]*init:::true/),
    EVAL_SIRDATA_UNBLOCK_SCROLL: () => {
        document.documentElement.classList.forEach((cls) => {
            if (cls.startsWith('sd-cmp-')) document.documentElement.classList.remove(cls);
        });
        return true;
    },
    EVAL_STEAMPOWERED_0: () =>
        JSON.parse(
            decodeURIComponent(
                document.cookie
                    .split(';')
                    .find((s) => s.trim().startsWith('cookieSettings'))
                    .split('=')[1],
            ),
        ).preference_state === 2,
    EVAL_TAKEALOT_0: () => document.body.classList.remove('freeze') || (document.body.style = '') || true,
    EVAL_TARTEAUCITRON_0: () => tarteaucitron.userInterface.respondAll(false) || true,
    EVAL_TARTEAUCITRON_1: () => tarteaucitron.userInterface.respondAll(true) || true,
    EVAL_TARTEAUCITRON_2: () => document.cookie.match(/tarteaucitron=[^;]*/)?.[0].includes('false'),
    EVAL_TEALIUM_0: () => typeof window.utag !== 'undefined' && typeof utag.gdpr === 'object',
    EVAL_TEALIUM_1: () => utag.gdpr.setConsentValue(false) || true,
    EVAL_TEALIUM_DONOTSELL: () => utag.gdpr.dns?.setDnsState(false) || true,
    EVAL_TEALIUM_2: () => utag.gdpr.setConsentValue(true) || true,
    EVAL_TEALIUM_3: () => utag.gdpr.getConsentState() !== 1,
    EVAL_TEALIUM_DONOTSELL_CHECK: () => utag.gdpr.dns?.getDnsState() !== 1,
    EVAL_TESTCMP_STEP: () => !!document.querySelector('#reject-all'),
    EVAL_TESTCMP_0: () => window.results.results[0] === 'button_clicked',
    EVAL_TESTCMP_COSMETIC_0: () => window.results.results[0] === 'banner_hidden',
    EVAL_THEFREEDICTIONARY_0: () => cmpUi.showPurposes() || cmpUi.rejectAll() || true,
    EVAL_THEFREEDICTIONARY_1: () => cmpUi.allowAll() || true,
    EVAL_USERCENTRICS_API_0: () => typeof UC_UI === 'object',
    EVAL_USERCENTRICS_API_1: () => !!UC_UI.closeCMP(),
    EVAL_USERCENTRICS_API_2: () => !!UC_UI.denyAllConsents(),
    EVAL_USERCENTRICS_API_3: () => !!UC_UI.acceptAllConsents(),
    EVAL_USERCENTRICS_API_4: () => !!UC_UI.closeCMP(),
    EVAL_USERCENTRICS_API_5: () => UC_UI.areAllConsentsAccepted() === true,
    EVAL_USERCENTRICS_API_6: () => UC_UI.areAllConsentsAccepted() === false,
    EVAL_USERCENTRICS_BUTTON_0: () =>
        JSON.parse(localStorage.getItem('usercentrics')).consents.every((c) => c.isEssential || !c.consentStatus),
    EVAL_WAITROSE_0: () => Array.from(document.querySelectorAll('label[id$=cookies-deny-label]')).forEach((e) => e.click()) || true,
};

export function getFunctionBody(snippetFunc: () => any) {
    const snippetStr = snippetFunc.toString();
    return `(${snippetStr})()`;
}
