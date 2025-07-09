/**
 * @typedef {import('../../../types/new-tab').Favorite} Favorite
 * @typedef {import('../../../types/new-tab').FavoritesData} FavoritesData
 * @typedef {import('../../../types/new-tab').FavoritesConfig} FavoritesConfig
 */

/**
 * @type {{
 *    many: {favorites: Favorite[]};
 *    single: {favorites: Favorite[]};
 *    none: {favorites: Favorite[]};
 *    "small-icon": {favorites: Favorite[]};
 *    "fallbacks": {favorites: Favorite[]};
 *    "titles": {favorites: Favorite[]};
 *    "missing": {favorites: Favorite[]};
 * }}
 */
export const favorites = {
    many: {
        // prettier-ignore
        /** @type {Favorite[]} */
        favorites: [
            { id: 'id-many-1', etldPlusOne: "example.com", url: 'https://example.com?id=id-many-1', title: 'Amazon', favicon: { src: './company-icons/amazon.svg', maxAvailableSize: 16 } },
            { id: 'id-many-2', etldPlusOne: "adform.com", url: 'https://adform.com?id=id-many-2', title: 'Adform', favicon: null },
            { id: 'id-many-3', etldPlusOne: "adobe.com", url: 'https://adobe.com?id=id-many-3', title: 'Adobe', favicon: { src: './this-does-note-exist', maxAvailableSize: 16 } },
            { id: 'id-many-4', etldPlusOne: "adobe.com", url: 'https://b.adobe.com?id=id-many-3', title: 'Adobe sub', favicon: { src: './this-does-note-exist', maxAvailableSize: 16 } },
            { id: 'id-many-31', etldPlusOne: "example.com", url: 'https://b.example.com?id=id-many-4', title: 'A Beautiful Mess', favicon: { src: './this-does-note-exist', maxAvailableSize: 16 } },
            { id: 'id-many-5', etldPlusOne: "google.com", url: 'https://mail.google.com?id=id-many-3', title: 'Gmail', favicon: null },
            { id: 'id-many-6', etldPlusOne: "example.com", url: 'https://example.com?id=id-many-5', title: 'TikTok', favicon: { src: './company-icons/bytedance.svg', maxAvailableSize: 16 } },
            { id: 'id-many-7', etldPlusOne: "doordash.com", url: 'https://doordash.com?id=id-many-6', title: 'DoorDash', favicon: null },
            { id: 'id-many-8', etldPlusOne: "example.com", url: 'https://example.com?id=id-many-7', title: 'Facebook', favicon: { src: './company-icons/facebook.svg', maxAvailableSize: 16 } },
            { id: 'id-many-9', etldPlusOne: "example.com", url: 'https://example.com?id=id-many-8', title: 'Beeswax', favicon: { src: './company-icons/beeswax.svg', maxAvailableSize: 16 } },
            { id: 'id-many-10', etldPlusOne: "example.com", url: 'https://example.com?id=id-many-9', title: 'Adobe', favicon: { src: './company-icons/adobe.svg', maxAvailableSize: 16 } },
            { id: 'id-many-11', etldPlusOne: "example.com", url: 'https://example.com?id=id-many-10', title: 'Beeswax', favicon: { src: './company-icons/beeswax.svg', maxAvailableSize: 16 } },
            { id: 'id-many-12', etldPlusOne: "example.com", url: 'https://example.com?id=id-many-11', title: 'Facebook', favicon: { src: './company-icons/facebook.svg', maxAvailableSize: 16 } },
            { id: 'id-many-13', etldPlusOne: "example.com", url: 'https://example.com?id=id-many-12', title: 'Gmail', favicon: { src: './company-icons/google.svg', maxAvailableSize: 64 } },
            { id: 'id-many-14', etldPlusOne: "example.com", url: 'https://example.com?id=id-many-13', title: 'TikTok', favicon: { src: './company-icons/bytedance.svg', maxAvailableSize: 16 } },
            { id: 'id-many-15', etldPlusOne: "example.com", url: 'https://example.com?id=id-many-14', title: 'yeti', favicon: null }
        ],
    },
    single: {
        /** @type {Favorite[]} */
        favorites: [
            {
                id: 'id-single-1',
                url: 'https://example.com?id=id-single-1',
                etldPlusOne: 'example.com',
                title: 'Amazon',
                favicon: { src: './company-icons/amazon.svg', maxAvailableSize: 32 },
            },
        ],
    },
    none: {
        /** @type {Favorite[]} */
        favorites: [],
    },
    missing: {
        /** @type {Favorite[]} */
        favorites: [
            {
                id: 'id-missing-1',
                etldPlusOne: 'adobe.com',
                url: 'https://adobe.com?id=id-many-3',
                title: 'Adobe',
                favicon: { src: './this-does-note-exist', maxAvailableSize: 16 },
            },
        ],
    },
    titles: {
        /** @type {Favorite[]} */
        favorites: [
            {
                id: 'id-titles-1',
                url: 'https://duckduckgo.com',
                etldPlusOne: 'google.com',
                title: 'accounts.google.com',
                favicon: null,
            },
        ],
    },
    'small-icon': {
        /** @type {Favorite[]} */
        favorites: [
            {
                id: 'id-small-icon-1',
                url: 'https://duckduckgo.com',
                etldPlusOne: 'duckduckgo.com',
                title: 'DuckDuckGo',
                favicon: { src: './icons/favicon@2x.png', maxAvailableSize: 16 },
            },
        ],
    },
    fallbacks: {
        /** @type {Favorite[]} */
        favorites: [
            {
                id: 'id-fallbacks-3',
                url: 'https://adobe.com?id=id-many-3',
                etldPlusOne: 'adobe.com',
                title: '404 favicon.src',
                favicon: { src: './this-does-note-exist', maxAvailableSize: 16 },
            },
            {
                id: 'id-fallbacks-4',
                url: 'https://revoked.badssl.com',
                etldPlusOne: 'badssl.com',
                title: 'missing favicon + subdomain',
                favicon: null,
            },
            {
                id: 'id-fallbacks-5',
                url: 'https://wikipedia.com',
                etldPlusOne: 'wikipedia.com',
                title: 'missing favicon',
                favicon: null,
            },
            {
                id: 'id-fallbacks-6',
                url: 'https://wikipedia.com',
                etldPlusOne: null,
                title: 'missing etld+1',
                favicon: null,
            },
        ],
    },
};

export function gen(count = 1000) {
    const max = Math.min(count, 1000);
    const icons = [
        '33across.svg',
        'a.svg',
        'acuityads.svg',
        'adform.svg',
        'adjust.svg',
        'adobe.svg',
        'akamai.svg',
        'amazon.svg',
        'amplitude.svg',
        'appsflyer.svg',
        'automattic.svg',
        'b.svg',
        'beeswax.svg',
        'bidtellect.svg',
        'branch-metrics.svg',
        'braze.svg',
        'bugsnag.svg',
        'bytedance.svg',
        'c.svg',
        'chartbeat.svg',
        'cloudflare.svg',
        'cognitiv.svg',
        'comscore.svg',
        'crimtan-holdings.svg',
        'criteo.svg',
        'd.svg',
        'deepintent.svg',
        'e.svg',
        'exoclick.svg',
        'eyeota.svg',
        'f.svg',
        'facebook.svg',
        'g.svg',
        'google.svg',
        'google-ads.svg',
        'google-analytics.svg',
        'gumgum.svg',
        'h.svg',
        'hotjar.svg',
        'i.svg',
        'id5.svg',
        'improve-digital.svg',
        'index-exchange.svg',
        'inmar.svg',
        'instagram.svg',
        'intent-iq.svg',
        'iponweb.svg',
        'j.svg',
        'k.svg',
        'kargo.svg',
        'kochava.svg',
        'l.svg',
        'line.svg',
        'linkedin.svg',
        'liveintent.svg',
        'liveramp.svg',
        'loopme-ltd.svg',
        'lotame-solutions.svg',
        'm.svg',
        'magnite.svg',
        'mediamath.svg',
        'medianet-advertising.svg',
        'mediavine.svg',
        'merkle.svg',
        'microsoft.svg',
        'mixpanel.svg',
        'n.svg',
        'narrative.svg',
        'nativo.svg',
        'neustar.svg',
        'new-relic.svg',
        'o.svg',
        'onetrust.svg',
        'openjs-foundation.svg',
        'openx.svg',
        'opera-software.svg',
        'oracle.svg',
        'other.svg',
        'outbrain.svg',
        'p.svg',
        'pinterest.svg',
        'prospect-one.svg',
        'pubmatic.svg',
        'pulsepoint.svg',
        'q.svg',
        'quantcast.svg',
        'r.svg',
        'rhythmone.svg',
        'roku.svg',
        'rtb-house.svg',
        'rubicon.svg',
        's.svg',
        'salesforce.svg',
        'semasio.svg',
        'sharethrough.svg',
        'simplifi-holdings.svg',
        'smaato.svg',
        'snap.svg',
        'sonobi.svg',
        'sovrn-holdings.svg',
        'spotx.svg',
        'supership.svg',
        'synacor.svg',
        't.svg',
        'taboola.svg',
        'tapad.svg',
        'teads.svg',
        'the-nielsen-company.svg',
        'the-trade-desk.svg',
        'triplelift.svg',
        'twitter.svg',
        'u.svg',
        'unruly-group.svg',
        'urban-airship.svg',
        'v.svg',
        'verizon-media.svg',
        'w.svg',
        'warnermedia.svg',
        'wpp.svg',
        'x.svg',
        'xaxis.svg',
        'y.svg',
        'yahoo-japan.svg',
        'yandex.svg',
        'yieldmo.svg',
        'youtube.svg',
        'z.svg',
        'zeotap.svg',
        'zeta-global.svg',
    ];
    return {
        favorites: Array.from({ length: max }).map((_, index) => {
            const randomFavicon = icons[index];
            const joined = `./company-icons/${randomFavicon}`;
            const alpha = 'abcdefghijklmnopqrstuvwxyz';

            /** @type {Favorite} */
            const out = {
                id: `id-many-${index}`,
                url: `https://${alpha[index % 7]}.example.com?id=${index}`,
                etldPlusOne: `example.com`,
                title: `Example ${index + 1}`,
                favicon: { src: joined, maxAvailableSize: 64 },
            };

            return out;
        }),
    };
}
