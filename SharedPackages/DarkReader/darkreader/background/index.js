(function () {
    'use strict';

    const isNavigatorDefined = typeof navigator !== 'undefined';
    const userAgent = isNavigatorDefined ? (navigator.userAgentData && Array.isArray(navigator.userAgentData.brands)) ?
        navigator.userAgentData.brands.map((brand) => `${brand.brand.toLowerCase()} ${brand.version}`).join(' ') : navigator.userAgent.toLowerCase()
        : 'some useragent';
    const platform = isNavigatorDefined ? (navigator.userAgentData && typeof navigator.userAgentData.platform === 'string') ?
        navigator.userAgentData.platform.toLowerCase() : navigator.platform.toLowerCase()
        : 'some platform';
    const isFirefox = (((false)));
    (userAgent.includes('vivaldi'));
    (userAgent.includes('yabrowser'));
    const isOpera = ((userAgent.includes('opr') || userAgent.includes('opera')));
    const isEdge = (userAgent.includes('edg'));
    const isWindows = platform.startsWith('win');
    const isMacOS = platform.startsWith('mac');
    const isMobile = (isNavigatorDefined && navigator.userAgentData) ? navigator.userAgentData.mobile : (userAgent.includes('mobile') || (false));
    // Return true if browser is known to have a bug with Media Queries, specifically Chromium on Linux and Kiwi on Android
    // We assume that if we are on Android, then we are running in Kiwi since it is the only mobile browser we can install Dark Reader in
    (((isNavigatorDefined && navigator.userAgentData) && ['Linux', 'Android'].includes(navigator.userAgentData.platform))
        || platform.startsWith('linux'));
    (() => {
        const m = userAgent.match(/chrom(?:e|ium)(?:\/| )([^ ]+)/);
        if (m && m[1]) {
            return m[1];
        }
        return '';
    })();
    (() => {
        const m = userAgent.match(/(?:firefox|librewolf)(?:\/| )([^ ]+)/);
        if (m && m[1]) {
            return m[1];
        }
        return '';
    })();
    (() => {
        try {
            document.querySelector(':defined');
            return true;
        }
        catch (err) {
            return false;
        }
    })();
    const isXMLHttpRequestSupported = typeof XMLHttpRequest === 'function';
    const isFetchSupported = typeof fetch === 'function';

    function parse24HTime(time) {
        return time.split(':').map((x) => parseInt(x));
    }
    function compareTime(time1, time2) {
        if (time1[0] === time2[0] && time1[1] === time2[1]) {
            return 0;
        }
        if (time1[0] < time2[0] || (time1[0] === time2[0] && time1[1] < time2[1])) {
            return -1;
        }
        return 1;
    }
    function nextTimeInterval(time0, time1, date = new Date()) {
        const a = parse24HTime(time0);
        const b = parse24HTime(time1);
        const t = [date.getHours(), date.getMinutes()];
        // Ensure a <= b
        if (compareTime(a, b) > 0) {
            return nextTimeInterval(time1, time0, date);
        }
        if (compareTime(a, b) === 0) {
            return null;
        }
        if (compareTime(t, a) < 0) {
            // t < a <= b
            // Schedule for todate at time a
            date.setHours(a[0]);
            date.setMinutes(a[1]);
            date.setSeconds(0);
            date.setMilliseconds(0);
            return date.getTime();
        }
        if (compareTime(t, b) < 0) {
            // a <= t < b
            // Schedule for today at time b
            date.setHours(b[0]);
            date.setMinutes(b[1]);
            date.setSeconds(0);
            date.setMilliseconds(0);
            return date.getTime();
        }
        // a <= b <= t
        // Schedule for tomorrow at time a
        return (new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1, a[0], a[1])).getTime();
    }
    function isInTimeIntervalLocal(time0, time1, date = new Date()) {
        const a = parse24HTime(time0);
        const b = parse24HTime(time1);
        const t = [date.getHours(), date.getMinutes()];
        if (compareTime(a, b) > 0) {
            return compareTime(a, t) <= 0 || compareTime(t, b) < 0;
        }
        return compareTime(a, t) <= 0 && compareTime(t, b) < 0;
    }
    function isInTimeIntervalUTC(time0, time1, timestamp) {
        if (time1 < time0) {
            return timestamp <= time1 || time0 <= timestamp;
        }
        return time0 < timestamp && timestamp < time1;
    }
    function getDuration(time) {
        let duration = 0;
        if (time.seconds) {
            duration += time.seconds * 1000;
        }
        if (time.minutes) {
            duration += time.minutes * 60 * 1000;
        }
        if (time.hours) {
            duration += time.hours * 60 * 60 * 1000;
        }
        if (time.days) {
            duration += time.days * 24 * 60 * 60 * 1000;
        }
        return duration;
    }
    function getDurationInMinutes(time) {
        return getDuration(time) / 1000 / 60;
    }
    function getSunsetSunriseUTCTime(latitude, longitude, date) {
        const dec31 = Date.UTC(date.getUTCFullYear(), 0, 0, 0, 0, 0, 0);
        const oneDay = getDuration({ days: 1 });
        const dayOfYear = Math.floor((date.getTime() - dec31) / oneDay);
        const zenith = 90.83333333333333;
        const D2R = Math.PI / 180;
        const R2D = 180 / Math.PI;
        // convert the longitude to hour value and calculate an approximate time
        const lnHour = longitude / 15;
        function getTime(isSunrise) {
            const t = dayOfYear + (((isSunrise ? 6 : 18) - lnHour) / 24);
            // calculate the Sun's mean anomaly
            const M = (0.9856 * t) - 3.289;
            // calculate the Sun's true longitude
            let L = M + (1.916 * Math.sin(M * D2R)) + (0.020 * Math.sin(2 * M * D2R)) + 282.634;
            if (L > 360) {
                L -= 360;
            }
            else if (L < 0) {
                L += 360;
            }
            // calculate the Sun's right ascension
            let RA = R2D * Math.atan(0.91764 * Math.tan(L * D2R));
            if (RA > 360) {
                RA -= 360;
            }
            else if (RA < 0) {
                RA += 360;
            }
            // right ascension value needs to be in the same qua
            const Lquadrant = (Math.floor(L / (90))) * 90;
            const RAquadrant = (Math.floor(RA / 90)) * 90;
            RA += (Lquadrant - RAquadrant);
            // right ascension value needs to be converted into hours
            RA /= 15;
            // calculate the Sun's declination
            const sinDec = 0.39782 * Math.sin(L * D2R);
            const cosDec = Math.cos(Math.asin(sinDec));
            // calculate the Sun's local hour angle
            const cosH = (Math.cos(zenith * D2R) - (sinDec * Math.sin(latitude * D2R))) / (cosDec * Math.cos(latitude * D2R));
            if (cosH > 1) {
                // always night
                return {
                    alwaysDay: false,
                    alwaysNight: true,
                    time: 0,
                };
            }
            else if (cosH < -1) {
                // always day
                return {
                    alwaysDay: true,
                    alwaysNight: false,
                    time: 0,
                };
            }
            const H = (isSunrise ? (360 - R2D * Math.acos(cosH)) : (R2D * Math.acos(cosH))) / 15;
            // calculate local mean time of rising/setting
            const T = H + RA - (0.06571 * t) - 6.622;
            // adjust back to UTC
            let UT = T - lnHour;
            if (UT > 24) {
                UT -= 24;
            }
            else if (UT < 0) {
                UT += 24;
            }
            // convert to milliseconds
            return {
                alwaysDay: false,
                alwaysNight: false,
                time: Math.round(UT * getDuration({ hours: 1 })),
            };
        }
        const sunriseTime = getTime(true);
        const sunsetTime = getTime(false);
        if (sunriseTime.alwaysDay || sunsetTime.alwaysDay) {
            return {
                alwaysDay: true,
                alwaysNight: false,
                sunriseTime: 0,
                sunsetTime: 0,
            };
        }
        else if (sunriseTime.alwaysNight || sunsetTime.alwaysNight) {
            return {
                alwaysDay: false,
                alwaysNight: true,
                sunriseTime: 0,
                sunsetTime: 0,
            };
        }
        return {
            alwaysDay: false,
            alwaysNight: false,
            sunriseTime: sunriseTime.time,
            sunsetTime: sunsetTime.time,
        };
    }
    function isNightAtLocation(latitude, longitude, date = new Date()) {
        const time = getSunsetSunriseUTCTime(latitude, longitude, date);
        if (time.alwaysDay) {
            return false;
        }
        else if (time.alwaysNight) {
            return true;
        }
        const sunriseTime = time.sunriseTime;
        const sunsetTime = time.sunsetTime;
        const currentTime = (date.getUTCHours() * getDuration({ hours: 1 }) +
            date.getUTCMinutes() * getDuration({ minutes: 1 }) +
            date.getUTCSeconds() * getDuration({ seconds: 1 }) +
            date.getUTCMilliseconds());
        return isInTimeIntervalUTC(sunsetTime, sunriseTime, currentTime);
    }
    function nextTimeChangeAtLocation(latitude, longitude, date = new Date()) {
        const time = getSunsetSunriseUTCTime(latitude, longitude, date);
        if (time.alwaysDay) {
            return date.getTime() + getDuration({ days: 1 });
        }
        else if (time.alwaysNight) {
            return date.getTime() + getDuration({ days: 1 });
        }
        const [firstTimeOnDay, lastTimeOnDay] = time.sunriseTime < time.sunsetTime ? [time.sunriseTime, time.sunsetTime] : [time.sunsetTime, time.sunriseTime];
        const currentTime = (date.getUTCHours() * getDuration({ hours: 1 }) +
            date.getUTCMinutes() * getDuration({ minutes: 1 }) +
            date.getUTCSeconds() * getDuration({ seconds: 1 }) +
            date.getUTCMilliseconds());
        if (currentTime <= firstTimeOnDay) {
            // Timeline:
            // --- firstTimeOnDay <---> lastTimeOnDay ---
            //  ^
            // Current time
            return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(), 0, 0, 0, firstTimeOnDay);
        }
        if (currentTime <= lastTimeOnDay) {
            // Timeline:
            // --- firstTimeOnDay <---> lastTimeOnDay ---
            //                      ^
            //                 Current time
            return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(), 0, 0, 0, lastTimeOnDay);
        }
        // Timeline:
        // --- firstTimeOnDay <---> lastTimeOnDay ---
        //                                         ^
        //                                    Current time
        return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + 1, 0, 0, 0, firstTimeOnDay);
    }

    function cachedFactory(factory, size) {
        const cache = new Map();
        return (key) => {
            if (cache.has(key)) {
                return cache.get(key);
            }
            const value = factory(key);
            cache.set(key, value);
            if (cache.size > size) {
                const first = cache.keys().next().value;
                cache.delete(first);
            }
            return value;
        };
    }

    function getURLHostOrProtocol($url) {
        const url = new URL($url);
        if (url.host) {
            return url.host;
        }
        else if (url.protocol === 'file:') {
            return url.pathname;
        }
        return url.protocol;
    }
    function compareURLPatterns(a, b) {
        return a.localeCompare(b);
    }
    /**
     * Determines whether URL has a match in URL template list.
     * @param url Site URL.
     * @paramlist List to search into.
     */
    function isURLInList(url, list) {
        for (let i = 0; i < list.length; i++) {
            if (isURLMatched(url, list[i])) {
                return true;
            }
        }
        return false;
    }
    /**
     * Determines whether URL matches the template.
     * @param url URL.
     * @param urlTemplate URL template ("google.*", "youtube.com" etc).
     */
    function isURLMatched(url, urlTemplate) {
        if (isRegExp(urlTemplate)) {
            const regexp = createRegExp(urlTemplate);
            return regexp ? regexp.test(url) : false;
        }
        return matchURLPattern(url, urlTemplate);
    }
    const URL_CACHE_SIZE = 32;
    const prepareURL = cachedFactory((url) => {
        let parsed;
        try {
            parsed = new URL(url);
        }
        catch (err) {
            return null;
        }
        const { hostname, pathname, protocol, port } = parsed;
        const hostParts = hostname.split('.').reverse();
        const pathParts = pathname.split('/').slice(1);
        if (!pathParts[pathParts.length - 1]) {
            pathParts.splice(pathParts.length - 1, 1);
        }
        return {
            hostParts,
            pathParts,
            port,
            protocol,
        };
    }, URL_CACHE_SIZE);
    const URL_MATCH_CACHE_SIZE = 32 * 1024;
    const preparePattern = cachedFactory((pattern) => {
        if (!pattern) {
            return null;
        }
        const exactStart = pattern.startsWith('^');
        const exactEnd = pattern.endsWith('$');
        if (exactStart) {
            pattern = pattern.substring(1);
        }
        if (exactEnd) {
            pattern = pattern.substring(0, pattern.length - 1);
        }
        let protocol = '';
        const protocolIndex = pattern.indexOf('://');
        if (protocolIndex > 0) {
            protocol = pattern.substring(0, protocolIndex + 1);
            pattern = pattern.substring(protocolIndex + 3);
        }
        const slashIndex = pattern.indexOf('/');
        const host = slashIndex < 0 ? pattern : pattern.substring(0, slashIndex);
        let hostName = host;
        let isIPv6 = false;
        let ipV6End = -1;
        if (host.startsWith('[')) {
            ipV6End = host.indexOf(']');
            if (ipV6End > 0) {
                isIPv6 = true;
            }
        }
        let port = '*';
        const portIndex = host.lastIndexOf(':');
        if (portIndex >= 0 && (!isIPv6 || ipV6End < portIndex)) {
            hostName = host.substring(0, portIndex);
            port = host.substring(portIndex + 1);
        }
        if (isIPv6) {
            try {
                const ipV6URL = new URL(`http://${hostName}`);
                hostName = ipV6URL.hostname;
            }
            catch (err) {
            }
        }
        const hostParts = hostName.split('.').reverse();
        const path = slashIndex < 0 ? '' : pattern.substring(slashIndex + 1);
        const pathParts = path.split('/');
        if (!pathParts[pathParts.length - 1]) {
            pathParts.splice(pathParts.length - 1, 1);
        }
        return {
            hostParts,
            pathParts,
            port,
            exactStart,
            exactEnd,
            protocol,
        };
    }, URL_MATCH_CACHE_SIZE);
    function matchURLPattern(url, pattern) {
        const u = prepareURL(url);
        const p = preparePattern(pattern);
        return matchPreparedURLPattern(u, p);
    }
    function matchPreparedURLPattern(u, p) {
        if (!(u && p)
            || (p.hostParts.length > u.hostParts.length)
            || (p.exactStart && p.hostParts.length !== u.hostParts.length)
            || (p.exactEnd && p.pathParts.length !== u.pathParts.length)
            || (p.port !== '*' && p.port !== u.port)
            || (p.protocol && p.protocol !== u.protocol)) {
            return false;
        }
        for (let i = 0; i < p.hostParts.length; i++) {
            const pHostPart = p.hostParts[i];
            const uHostPart = u.hostParts[i];
            if (pHostPart !== '*' && pHostPart !== uHostPart) {
                return false;
            }
        }
        if (p.hostParts.length >= 2
            && p.hostParts.at(-1) !== '*'
            && (p.hostParts.length < u.hostParts.length - 1
                || (p.hostParts.length === u.hostParts.length - 1
                    && u.hostParts.at(-1) !== 'www'))) {
            return false;
        }
        if (p.pathParts.length === 0) {
            return true;
        }
        if (p.pathParts.length > u.pathParts.length) {
            return false;
        }
        for (let i = 0; i < p.pathParts.length; i++) {
            const pPathPart = p.pathParts[i];
            const uPathPart = u.pathParts[i];
            if (pPathPart !== '*' && pPathPart !== uPathPart) {
                return false;
            }
        }
        return true;
    }
    function isRegExp(pattern) {
        return pattern.startsWith('/') && pattern.endsWith('/') && pattern.length > 2;
    }
    const REGEXP_CACHE_SIZE = 1024;
    const createRegExp = cachedFactory((pattern) => {
        if (pattern.startsWith('/')) {
            pattern = pattern.substring(1);
        }
        if (pattern.endsWith('/')) {
            pattern = pattern.substring(0, pattern.length - 1);
        }
        try {
            return new RegExp(pattern);
        }
        catch (err) {
            return null;
        }
    }, REGEXP_CACHE_SIZE);
    const wikiPDFPathRegexp = /^\/.*\/[a-z]+\:[^\:\/]+\.pdf/i;
    function isPDF(url) {
        try {
            const { hostname, pathname } = new URL(url);
            if (pathname.includes('.pdf')) {
                if (((hostname.endsWith('.wikimedia.org') || hostname.endsWith('.wikipedia.org')) && pathname.match(wikiPDFPathRegexp)) ||
                    (hostname.endsWith('.dropbox.com') && pathname.startsWith('/s/') && (pathname.endsWith('.pdf') || pathname.endsWith('.PDF')))) {
                    return false;
                }
                if (pathname.endsWith('.pdf')) {
                    for (let i = pathname.length; i >= 0; i--) {
                        if (pathname[i] === '=') {
                            return false;
                        }
                        else if (pathname[i] === '/') {
                            return true;
                        }
                    }
                }
                else {
                    return false;
                }
            }
        }
        catch (e) {
            // Do nothing
        }
        return false;
    }
    const indexedSiteLists = new WeakMap();
    function isInListOptimized(url, list) {
        if (!url || list.length === 0) {
            return false;
        }
        let index = indexedSiteLists.get(list);
        if (!index) {
            index = indexURLTemplateList(list);
            indexedSiteLists.set(list, index);
        }
        return isURLInIndexedList(url, index);
    }
    function isURLEnabled(url, userSettings, { isProtected, isInDarkList, isDarkThemeDetected }, isAllowedFileSchemeAccess = true) {
        if (isLocalFile(url) && !isAllowedFileSchemeAccess) {
            return false;
        }
        if (isProtected && !userSettings.enableForProtectedPages) {
            return false;
        }
        if (isPDF(url)) {
            return userSettings.enableForPDF;
        }
        const isURLInDisabledList = isInListOptimized(url, userSettings.disabledFor);
        const isURLInEnabledList = isInListOptimized(url, userSettings.enabledFor);
        if (!userSettings.enabledByDefault) {
            return isURLInEnabledList;
        }
        if (isURLInEnabledList) {
            return true;
        }
        if (isInDarkList || (userSettings.detectDarkTheme && isDarkThemeDetected)) {
            return false;
        }
        return !isURLInDisabledList;
    }
    function isLocalFile(url) {
        return Boolean(url) && url.startsWith('file:///');
    }
    function indexURLTemplateList(list, assign = () => true) {
        const trie = {
            key: '',
            hostNodes: new Map(),
            pathNodes: new Map(),
            hardPatterns: [],
            regexps: [],
            data: null,
        };
        const templateIndices = new Map();
        const patterns = [];
        list.forEach((u, i) => {
            if (isRegExp(u)) {
                const r = createRegExp(u);
                if (r) {
                    trie.regexps.push({ regexp: r, data: assign(list[i], i) });
                }
            }
            else {
                const p = preparePattern(u);
                if (p) {
                    if (p.exactStart || p.exactEnd || (p.port && p.port !== '*') || p.protocol) {
                        trie.hardPatterns.push({ pattern: p, data: assign(list[i], i) });
                        return;
                    }
                    patterns.push(p);
                    templateIndices.set(p, i);
                }
            }
        });
        patterns.forEach((pattern) => {
            const listIndex = templateIndices.get(pattern);
            const data = assign(list[listIndex], listIndex);
            let node = trie;
            pattern.hostParts.forEach((p) => {
                const nodes = node.hostNodes;
                if (nodes.has(p)) {
                    node = nodes.get(p);
                }
                else {
                    node = {
                        key: p,
                        hostNodes: new Map(),
                        pathNodes: new Map(),
                        data: null,
                    };
                    nodes.set(p, node);
                }
            });
            const lastHostNode = {
                key: '',
                hostNodes: new Map(),
                pathNodes: new Map(),
                data: null,
            };
            node.hostNodes.set('', lastHostNode);
            node = lastHostNode;
            if (pattern.pathParts.length === 0) {
                node.data = data;
                return;
            }
            pattern.pathParts.forEach((p) => {
                const nodes = node.pathNodes;
                if (nodes.has(p)) {
                    node = nodes.get(p);
                }
                else {
                    node = {
                        key: p,
                        hostNodes: new Map(),
                        pathNodes: new Map(),
                        data: null,
                    };
                    nodes.set(p, node);
                }
            });
            const lastPathNode = {
                key: '',
                hostNodes: new Map(),
                pathNodes: new Map(),
                data: null,
            };
            node.pathNodes.set('', lastPathNode);
            lastPathNode.data = data;
        });
        return trie;
    }
    function isURLInIndexedList(url, trie) {
        const matches = getURLMatchesFromIndexedList(url, trie, true);
        return matches.length > 0;
    }
    function getURLMatchesFromIndexedList(url, trie, breakOnFirstMatch = false) {
        const found = new Set();
        const matches = [];
        const push = (data) => {
            if (!found.has(data)) {
                found.add(data);
                matches.push(data);
            }
        };
        for (const r of trie.regexps) {
            if (r.regexp.test(url)) {
                push(r.data);
                if (breakOnFirstMatch) {
                    return matches;
                }
            }
        }
        const u = prepareURL(url);
        if (!u) {
            return matches;
        }
        for (const p of trie.hardPatterns) {
            if (matchPreparedURLPattern(u, p.pattern)) {
                push(p.data);
                if (breakOnFirstMatch) {
                    return matches;
                }
            }
        }
        const matchHost = (node, index) => {
            const finalHostNode = node.hostNodes.get('');
            const noMoreHostParts = index === u.hostParts.length;
            const value = noMoreHostParts ? '' : u.hostParts[index];
            if (finalHostNode && (noMoreHostParts ||
                node.key === '*' ||
                (index === u.hostParts.length - 1 && value === 'www'))) {
                if (finalHostNode.data) {
                    push(finalHostNode.data);
                    if (breakOnFirstMatch) {
                        return;
                    }
                }
                matchPath(finalHostNode, 0);
            }
            if (noMoreHostParts) {
                return;
            }
            const nodes = node.hostNodes;
            const wildcardNode = nodes.get('*');
            if (wildcardNode) {
                matchHost(wildcardNode, index + 1);
            }
            if (breakOnFirstMatch && matches.length > 0) {
                return;
            }
            const keyNode = nodes.get(value);
            if (keyNode) {
                matchHost(keyNode, index + 1);
            }
        };
        const matchPath = (node, index) => {
            const finalPathNode = node.pathNodes.get('');
            const noMorePathParts = index === u.pathParts.length;
            const value = noMorePathParts ? '' : u.pathParts[index];
            if (finalPathNode && finalPathNode.data) {
                push(finalPathNode.data);
            }
            if (noMorePathParts) {
                return;
            }
            const nodes = node.pathNodes;
            const wildcardNode = nodes.get('*');
            if (wildcardNode) {
                matchPath(wildcardNode, index + 1);
            }
            if (breakOnFirstMatch && matches.length > 0) {
                return;
            }
            const keyNode = nodes.get(value);
            if (keyNode) {
                matchPath(keyNode, index + 1);
            }
        };
        matchHost(trie, 0);
        return matches;
    }

    function canInjectScript(url) {
        if (url === 'about:blank') {
            return false;
        }
        if (isEdge) {
            return Boolean(url
                && !url.startsWith('chrome')
                && !url.startsWith('data')
                && !url.startsWith('devtools')
                && !url.startsWith('edge')
                && !url.startsWith('https://chrome.google.com/webstore')
                && !url.startsWith('https://chromewebstore.google.com/')
                && !url.startsWith('https://microsoftedge.microsoft.com/addons')
                && !url.startsWith('view-source'));
        }
        return Boolean(url
            && !url.startsWith('chrome')
            && !url.startsWith('https://chrome.google.com/webstore')
            && !url.startsWith('https://chromewebstore.google.com/')
            && !url.startsWith('data')
            && !url.startsWith('devtools')
            && !url.startsWith('view-source'));
    }
    async function readSyncStorage(defaults) {
        return new Promise((resolve) => {
            chrome.storage.sync.get(null, (sync) => {
                if (chrome.runtime.lastError) {
                    console.error(chrome.runtime.lastError.message);
                    resolve(null);
                    return;
                }
                for (const key in sync) {
                    // Just to be sure: https://github.com/darkreader/darkreader/issues/7270
                    // The value of sync[key] shouldn't be null.
                    if (!sync[key]) {
                        continue;
                    }
                    const metaKeysCount = sync[key].__meta_split_count;
                    if (!metaKeysCount) {
                        continue;
                    }
                    let string = '';
                    for (let i = 0; i < metaKeysCount; i++) {
                        string += sync[`${key}_${i.toString(36)}`];
                        delete sync[`${key}_${i.toString(36)}`];
                    }
                    try {
                        sync[key] = JSON.parse(string);
                    }
                    catch (error) {
                        console.error(`sync[${key}]: Could not parse record from sync storage: ${string}`);
                        resolve(null);
                        return;
                    }
                }
                sync = {
                    ...defaults,
                    ...sync,
                };
                resolve(sync);
            });
        });
    }
    async function readLocalStorage(defaults) {
        return new Promise((resolve) => {
            chrome.storage.local.get(defaults, (local) => {
                if (chrome.runtime.lastError) {
                    console.error(chrome.runtime.lastError.message);
                    resolve(defaults);
                    return;
                }
                resolve(local);
            });
        });
    }
    function prepareSyncStorage(values) {
        for (const key in values) {
            const value = values[key];
            const string = JSON.stringify(value);
            // The maximum size of any one item that each extension is allowed to store in the sync storage area,
            // as measured by the JSON stringification of the item's value plus the length of its key.
            // Source: https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/storage/sync
            const totalLength = string.length + key.length;
            if (totalLength > chrome.storage.sync.QUOTA_BYTES_PER_ITEM) {
                // This length limit permits us to store up to 1000 = (parseInt('rr', 36) + 1) records.
                const maxLength = chrome.storage.sync.QUOTA_BYTES_PER_ITEM - key.length - 1 - 2;
                const minimalKeysNeeded = Math.ceil(string.length / maxLength);
                for (let i = 0; i < minimalKeysNeeded; i++) {
                    values[`${key}_${i.toString(36)}`] = string.substring(i * maxLength, (i + 1) * maxLength);
                }
                values[key] = {
                    __meta_split_count: minimalKeysNeeded,
                };
            }
        }
        return values;
    }
    async function writeSyncStorage(values) {
        return new Promise((resolve, reject) => {
            const packaged = prepareSyncStorage(values);
            chrome.storage.sync.set(packaged, () => {
                if (chrome.runtime.lastError) {
                    reject(chrome.runtime.lastError);
                    return;
                }
                resolve();
            });
        });
    }
    async function writeLocalStorage(values) {
        return new Promise((resolve) => {
            chrome.storage.local.set(values, () => {
                resolve();
            });
        });
    }
    async function removeSyncStorage(keys) {
        return new Promise((resolve) => {
            chrome.storage.sync.remove(keys, () => {
                resolve();
            });
        });
    }
    async function removeLocalStorage(keys) {
        return new Promise((resolve) => {
            chrome.storage.local.remove(keys, () => {
                resolve();
            });
        });
    }
    async function getCommands() {
        return new Promise((resolve) => {
            if (!chrome.commands) {
                resolve([]);
                return;
            }
            chrome.commands.getAll((commands) => {
                if (commands) {
                    resolve(commands);
                }
                else {
                    resolve([]);
                }
            });
        });
    }
    function keepListeningToEvents() {
        let intervalId = 0;
        const keepHopeAlive = () => {
            intervalId = setInterval(chrome.runtime.getPlatformInfo, getDuration({ seconds: 10 }));
        };
        chrome.runtime.onStartup.addListener(keepHopeAlive);
        keepHopeAlive();
        const stopListening = () => {
            clearInterval(intervalId);
            chrome.runtime.onStartup.removeListener(keepHopeAlive);
        };
        return stopListening;
    }

    const BLOG_URL = 'https://darkreader.org/blog/';
    const NEWS_URL = 'https://darkreader.org/blog/posts.json';
    const CONFIG_URL_BASE = 'https://raw.githubusercontent.com/darkreader/darkreader/main/src/config';
    function getBlogPostURL(postId) {
        return `${BLOG_URL}${postId}/`;
    }

    const isSystemDarkModeEnabled = () => (matchMedia('(prefers-color-scheme: dark)')).matches;

    var MessageTypeUItoBG;
    (function (MessageTypeUItoBG) {
        MessageTypeUItoBG["GET_DATA"] = "ui-bg-get-data";
        MessageTypeUItoBG["GET_DEVTOOLS_DATA"] = "ui-bg-get-devtools-data";
        MessageTypeUItoBG["SUBSCRIBE_TO_CHANGES"] = "ui-bg-subscribe-to-changes";
        MessageTypeUItoBG["UNSUBSCRIBE_FROM_CHANGES"] = "ui-bg-unsubscribe-from-changes";
        MessageTypeUItoBG["CHANGE_SETTINGS"] = "ui-bg-change-settings";
        MessageTypeUItoBG["SET_THEME"] = "ui-bg-set-theme";
        MessageTypeUItoBG["TOGGLE_ACTIVE_TAB"] = "ui-bg-toggle-active-tab";
        MessageTypeUItoBG["MARK_NEWS_AS_READ"] = "ui-bg-mark-news-as-read";
        MessageTypeUItoBG["MARK_NEWS_AS_DISPLAYED"] = "ui-bg-mark-news-as-displayed";
        MessageTypeUItoBG["LOAD_CONFIG"] = "ui-bg-load-config";
        MessageTypeUItoBG["APPLY_DEV_DYNAMIC_THEME_FIXES"] = "ui-bg-apply-dev-dynamic-theme-fixes";
        MessageTypeUItoBG["RESET_DEV_DYNAMIC_THEME_FIXES"] = "ui-bg-reset-dev-dynamic-theme-fixes";
        MessageTypeUItoBG["APPLY_DEV_INVERSION_FIXES"] = "ui-bg-apply-dev-inversion-fixes";
        MessageTypeUItoBG["RESET_DEV_INVERSION_FIXES"] = "ui-bg-reset-dev-inversion-fixes";
        MessageTypeUItoBG["APPLY_DEV_STATIC_THEMES"] = "ui-bg-apply-dev-static-themes";
        MessageTypeUItoBG["RESET_DEV_STATIC_THEMES"] = "ui-bg-reset-dev-static-themes";
        MessageTypeUItoBG["START_ACTIVATION"] = "ui-bg-start-activation";
        MessageTypeUItoBG["RESET_ACTIVATION"] = "ui-bg-reset-activation";
        MessageTypeUItoBG["COLOR_SCHEME_CHANGE"] = "ui-bg-color-scheme-change";
        MessageTypeUItoBG["HIDE_HIGHLIGHTS"] = "ui-bg-hide-highlights";
    })(MessageTypeUItoBG || (MessageTypeUItoBG = {}));
    var MessageTypeBGtoUI;
    (function (MessageTypeBGtoUI) {
        MessageTypeBGtoUI["CHANGES"] = "bg-ui-changes";
    })(MessageTypeBGtoUI || (MessageTypeBGtoUI = {}));
    var DebugMessageTypeBGtoUI;
    (function (DebugMessageTypeBGtoUI) {
        DebugMessageTypeBGtoUI["CSS_UPDATE"] = "debug-bg-ui-css-update";
        DebugMessageTypeBGtoUI["UPDATE"] = "debug-bg-ui-update";
    })(DebugMessageTypeBGtoUI || (DebugMessageTypeBGtoUI = {}));
    var MessageTypeBGtoCS;
    (function (MessageTypeBGtoCS) {
        MessageTypeBGtoCS["ADD_CSS_FILTER"] = "bg-cs-add-css-filter";
        MessageTypeBGtoCS["ADD_DYNAMIC_THEME"] = "bg-cs-add-dynamic-theme";
        MessageTypeBGtoCS["ADD_STATIC_THEME"] = "bg-cs-add-static-theme";
        MessageTypeBGtoCS["ADD_SVG_FILTER"] = "bg-cs-add-svg-filter";
        MessageTypeBGtoCS["CLEAN_UP"] = "bg-cs-clean-up";
        MessageTypeBGtoCS["FETCH_RESPONSE"] = "bg-cs-fetch-response";
        MessageTypeBGtoCS["UNSUPPORTED_SENDER"] = "bg-cs-unsupported-sender";
    })(MessageTypeBGtoCS || (MessageTypeBGtoCS = {}));
    var DebugMessageTypeBGtoCS;
    (function (DebugMessageTypeBGtoCS) {
        DebugMessageTypeBGtoCS["RELOAD"] = "debug-bg-cs-reload";
    })(DebugMessageTypeBGtoCS || (DebugMessageTypeBGtoCS = {}));
    var MessageTypeCStoBG;
    (function (MessageTypeCStoBG) {
        MessageTypeCStoBG["COLOR_SCHEME_CHANGE"] = "cs-bg-color-scheme-change";
        MessageTypeCStoBG["DARK_THEME_DETECTED"] = "cs-bg-dark-theme-detected";
        MessageTypeCStoBG["DARK_THEME_NOT_DETECTED"] = "cs-bg-dark-theme-not-detected";
        MessageTypeCStoBG["FETCH"] = "cs-bg-fetch";
        MessageTypeCStoBG["DOCUMENT_CONNECT"] = "cs-bg-document-connect";
        MessageTypeCStoBG["DOCUMENT_FORGET"] = "cs-bg-document-forget";
        MessageTypeCStoBG["DOCUMENT_FREEZE"] = "cs-bg-document-freeze";
        MessageTypeCStoBG["DOCUMENT_RESUME"] = "cs-bg-document-resume";
    })(MessageTypeCStoBG || (MessageTypeCStoBG = {}));
    var DebugMessageTypeCStoBG;
    (function (DebugMessageTypeCStoBG) {
        DebugMessageTypeCStoBG["LOG"] = "debug-cs-bg-log";
    })(DebugMessageTypeCStoBG || (DebugMessageTypeCStoBG = {}));
    var MessageTypeCStoUI;
    (function (MessageTypeCStoUI) {
        MessageTypeCStoUI["EXPORT_CSS_RESPONSE"] = "cs-ui-export-css-response";
    })(MessageTypeCStoUI || (MessageTypeCStoUI = {}));
    var MessageTypeUItoCS;
    (function (MessageTypeUItoCS) {
        MessageTypeUItoCS["EXPORT_CSS"] = "ui-cs-export-css";
    })(MessageTypeUItoCS || (MessageTypeUItoCS = {}));

    function parseArray(text) {
        return text.replace(/\r/g, '')
            .split('\n')
            .map((s) => s.trim())
            .filter((s) => s);
    }
    function formatArray(arr) {
        return arr.concat('').join('\n');
    }
    function getStringSize(value) {
        return value.length * 2;
    }
    function getParenthesesRange(input, searchStartIndex = 0) {
        return getOpenCloseRange(input, searchStartIndex, '(', ')', []);
    }
    function getOpenCloseRange(input, searchStartIndex, openToken, closeToken, excludeRanges) {
        let indexOf;
        if (excludeRanges.length === 0) {
            indexOf = (token, pos) => input.indexOf(token, pos);
        }
        else {
            indexOf = (token, pos) => indexOfExcluding(input, token, pos, excludeRanges);
        }
        const { length } = input;
        let depth = 0;
        let firstOpenIndex = -1;
        for (let i = searchStartIndex; i < length; i++) {
            if (depth === 0) {
                const openIndex = indexOf(openToken, i);
                if (openIndex < 0) {
                    break;
                }
                firstOpenIndex = openIndex;
                depth++;
                i = openIndex;
            }
            else {
                const closeIndex = indexOf(closeToken, i);
                if (closeIndex < 0) {
                    break;
                }
                const openIndex = indexOf(openToken, i);
                if (openIndex < 0 || closeIndex <= openIndex) {
                    depth--;
                    if (depth === 0) {
                        return { start: firstOpenIndex, end: closeIndex + 1 };
                    }
                    i = closeIndex;
                }
                else {
                    depth++;
                    i = openIndex;
                }
            }
        }
        return null;
    }
    function indexOfExcluding(input, search, position, excludeRanges) {
        const i = input.indexOf(search, position);
        const exclusion = excludeRanges.find((r) => i >= r.start && i < r.end);
        if (exclusion) {
            return indexOfExcluding(input, search, exclusion.end, excludeRanges);
        }
        return i;
    }
    function splitExcluding(input, separator, excludeRanges) {
        const parts = [];
        let commaIndex = -1;
        let currIndex = 0;
        while ((commaIndex = indexOfExcluding(input, separator, currIndex, excludeRanges)) >= 0) {
            parts.push(input.substring(currIndex, commaIndex).trim());
            currIndex = commaIndex + 1;
        }
        parts.push(input.substring(currIndex).trim());
        return parts;
    }

    // Exclude font libraries to preserve icons
    const excludedSelectors = [
        'pre', 'pre *', 'code',
        '[aria-hidden="true"]',
        // Font Awesome
        '[class*="fa-"]',
        '.fa', '.fab', '.fad', '.fal', '.far', '.fas', '.fass', '.fasr', '.fat',
        // Generic matches for icon/symbol fonts
        '.icofont', '[style*="font-"]',
        '[class*="icon"]', '[class*="Icon"]',
        '[class*="symbol"]', '[class*="Symbol"]',
        // Glyph Icons
        '.glyphicon',
        // Material Design
        '[class*="material-symbol"]', '[class*="material-icon"]',
        // MUI
        'mu', '[class*="mu-"]',
        // Typicons
        '.typcn',
        // Videojs font
        '[class*="vjs-"]',
    ];
    function createTextStyle(config) {
        const lines = [];
        lines.push(`*:not(${excludedSelectors.join(', ')}) {`);
        if (config.useFont && config.fontFamily) {
            lines.push(`  font-family: ${config.fontFamily} !important;`);
        }
        if (config.textStroke > 0) {
            lines.push(`  -webkit-text-stroke: ${config.textStroke}px !important;`);
            lines.push(`  text-stroke: ${config.textStroke}px !important;`);
        }
        lines.push('}');
        return lines.join('\n');
    }

    function isArrayLike(items) {
        return items.length != null;
    }
    // NOTE: Iterating Array-like items using `for .. of` is 3x slower in Firefox
    // https://jsben.ch/kidOp
    function forEach(items, iterator) {
        if (isArrayLike(items)) {
            for (let i = 0, len = items.length; i < len; i++) {
                iterator(items[i]);
            }
        }
        else {
            for (const item of items) {
                iterator(item);
            }
        }
    }
    // NOTE: Pushing items like `arr.push(...items)` is 3x slower in Firefox
    // https://jsben.ch/nr9OF
    function push(array, addition) {
        forEach(addition, (a) => array.push(a));
    }

    function formatSitesFixesConfig(fixes, options) {
        const lines = [];
        fixes.forEach((fix, i) => {
            push(lines, fix.url);
            options.props.forEach((prop) => {
                const command = options.getPropCommandName(prop);
                const value = fix[prop];
                if (options.shouldIgnoreProp(prop, value)) {
                    return;
                }
                lines.push('');
                lines.push(command);
                const formattedValue = options.formatPropValue(prop, value);
                if (formattedValue) {
                    lines.push(formattedValue);
                }
            });
            if (i < fixes.length - 1) {
                lines.push('');
                lines.push('='.repeat(32));
                lines.push('');
            }
        });
        lines.push('');
        return lines.join('\n');
    }

    function scale(x, inLow, inHigh, outLow, outHigh) {
        return (x - inLow) * (outHigh - outLow) / (inHigh - inLow) + outLow;
    }
    function clamp(x, min, max) {
        return Math.min(max, Math.max(min, x));
    }
    // Note: the caller is responsible for ensuring that matrix dimensions make sense
    function multiplyMatrices(m1, m2) {
        const result = [];
        for (let i = 0, len = m1.length; i < len; i++) {
            result[i] = [];
            for (let j = 0, len2 = m2[0].length; j < len2; j++) {
                let sum = 0;
                for (let k = 0, len3 = m1[0].length; k < len3; k++) {
                    sum += m1[i][k] * m2[k][j];
                }
                result[i][j] = sum;
            }
        }
        return result;
    }

    function createFilterMatrix(config) {
        let m = Matrix.identity();
        if (config.sepia !== 0) {
            m = multiplyMatrices(m, Matrix.sepia(config.sepia / 100));
        }
        if (config.grayscale !== 0) {
            m = multiplyMatrices(m, Matrix.grayscale(config.grayscale / 100));
        }
        if (config.contrast !== 100) {
            m = multiplyMatrices(m, Matrix.contrast(config.contrast / 100));
        }
        if (config.brightness !== 100) {
            m = multiplyMatrices(m, Matrix.brightness(config.brightness / 100));
        }
        if (config.mode === 1) {
            m = multiplyMatrices(m, Matrix.invertNHue());
        }
        return m;
    }
    function applyColorMatrix([r, g, b], matrix) {
        const rgb = [[r / 255], [g / 255], [b / 255], [1], [1]];
        const result = multiplyMatrices(matrix, rgb);
        return [0, 1, 2].map((i) => clamp(Math.round(result[i][0] * 255), 0, 255));
    }
    const Matrix = {
        identity() {
            return [
                [1, 0, 0, 0, 0],
                [0, 1, 0, 0, 0],
                [0, 0, 1, 0, 0],
                [0, 0, 0, 1, 0],
                [0, 0, 0, 0, 1],
            ];
        },
        invertNHue() {
            return [
                [0.333, -0.667, -0.667, 0, 1],
                [-0.667, 0.333, -0.667, 0, 1],
                [-0.667, -0.667, 0.333, 0, 1],
                [0, 0, 0, 1, 0],
                [0, 0, 0, 0, 1],
            ];
        },
        brightness(v) {
            return [
                [v, 0, 0, 0, 0],
                [0, v, 0, 0, 0],
                [0, 0, v, 0, 0],
                [0, 0, 0, 1, 0],
                [0, 0, 0, 0, 1],
            ];
        },
        contrast(v) {
            const t = (1 - v) / 2;
            return [
                [v, 0, 0, 0, t],
                [0, v, 0, 0, t],
                [0, 0, v, 0, t],
                [0, 0, 0, 1, 0],
                [0, 0, 0, 0, 1],
            ];
        },
        sepia(v) {
            return [
                [(0.393 + 0.607 * (1 - v)), (0.769 - 0.769 * (1 - v)), (0.189 - 0.189 * (1 - v)), 0, 0],
                [(0.349 - 0.349 * (1 - v)), (0.686 + 0.314 * (1 - v)), (0.168 - 0.168 * (1 - v)), 0, 0],
                [(0.272 - 0.272 * (1 - v)), (0.534 - 0.534 * (1 - v)), (0.131 + 0.869 * (1 - v)), 0, 0],
                [0, 0, 0, 1, 0],
                [0, 0, 0, 0, 1],
            ];
        },
        grayscale(v) {
            return [
                [(0.2126 + 0.7874 * (1 - v)), (0.7152 - 0.7152 * (1 - v)), (0.0722 - 0.0722 * (1 - v)), 0, 0],
                [(0.2126 - 0.2126 * (1 - v)), (0.7152 + 0.2848 * (1 - v)), (0.0722 - 0.0722 * (1 - v)), 0, 0],
                [(0.2126 - 0.2126 * (1 - v)), (0.7152 - 0.7152 * (1 - v)), (0.0722 + 0.9278 * (1 - v)), 0, 0],
                [0, 0, 0, 1, 0],
                [0, 0, 0, 0, 1],
            ];
        },
    };

    function parseSitesFixesConfig(text, options) {
        const sites = [];
        const blocks = text.replace(/\r/g, '').split(/^\s*={2,}\s*$/gm);
        blocks.forEach((block) => {
            const lines = block.split('\n');
            const commandIndices = [];
            lines.forEach((ln, i) => {
                if (ln.match(/^[A-Z]+(\s[A-Z]+){0,2}$/)) {
                    commandIndices.push(i);
                }
            });
            if (commandIndices.length === 0) {
                return;
            }
            const siteFix = {
                url: parseArray(lines.slice(0, commandIndices[0]).join('\n')),
            };
            commandIndices.forEach((commandIndex, i) => {
                const command = lines[commandIndex].trim();
                const valueText = lines.slice(commandIndex + 1, i === commandIndices.length - 1 ? lines.length : commandIndices[i + 1]).join('\n');
                const prop = options.getCommandPropName(command);
                if (!prop) {
                    return;
                }
                const value = options.parseCommandValue(command, valueText);
                siteFix[prop] = value;
            });
            sites.push(siteFix);
        });
        return sites;
    }
    // URL patterns are guaranteed to not have protocol and leading '/'
    function getDomain(url) {
        try {
            return (new URL(url)).hostname.toLowerCase();
        }
        catch (error) {
            return url.split('/')[0].toLowerCase();
        }
    }
    function processSiteFixesConfigBlock(text, offsets, recordStart, recordEnd, urls) {
        // TODO: more formal definition of URLs and delimiters
        const block = text.substring(recordStart, recordEnd);
        const lines = block.split('\n');
        const commandIndices = [];
        lines.forEach((ln, i) => {
            if (ln.match(/^[A-Z]+(\s[A-Z]+){0,2}$/)) {
                commandIndices.push(i);
            }
        });
        if (commandIndices.length === 0) {
            return;
        }
        offsets.push([recordStart, recordEnd - recordStart]);
        const urls_ = parseArray(lines.slice(0, commandIndices[0]).join('\n'));
        urls.push(urls_);
    }
    function extractURLsFromSiteFixesConfig(text) {
        const urls = [];
        // Array of tuples, where first number is an offset of record start and second number is record length.
        const offsets = [];
        let recordStart = 0;
        // Delimiter between two blocks
        const delimiterRegex = /^\s*={2,}\s*$/gm;
        let delimiter;
        while ((delimiter = delimiterRegex.exec(text))) {
            const nextDelimiterStart = delimiter.index;
            const nextDelimiterEnd = delimiter.index + delimiter[0].length;
            processSiteFixesConfigBlock(text, offsets, recordStart, nextDelimiterStart, urls);
            recordStart = nextDelimiterEnd;
        }
        processSiteFixesConfigBlock(text, offsets, recordStart, text.length, urls);
        return { urls, offsets };
    }
    function indexSitesFixesConfig(text) {
        const { urls, offsets: offsetsGrouped } = extractURLsFromSiteFixesConfig(text);
        const offsetMap = new Map();
        const templates = [];
        const offsets = [];
        urls.forEach((block, i) => {
            block.forEach((u) => {
                templates.push(u);
                offsets.push(offsetsGrouped[i]);
                offsetMap.set(u, offsetsGrouped[i]);
            });
        });
        const indexedList = indexURLTemplateList(templates, (_, i) => {
            return offsets[i];
        });
        return indexedList;
    }
    const siteFixesCache = new WeakMap();
    function getSitesFixesFor(url, text, index, parse) {
        const matches = getURLMatchesFromIndexedList(url, index);
        const fixes = matches.map((offset) => {
            const cache = siteFixesCache.get(offset);
            if (cache) {
                return cache;
            }
            const [start, length] = offset;
            const block = text.slice(start, start + length);
            const fix = parse(block)[0];
            siteFixesCache.set(offset, cache);
            return fix;
        });
        return fixes;
    }

    var FilterMode;
    (function (FilterMode) {
        FilterMode[FilterMode["light"] = 0] = "light";
        FilterMode[FilterMode["dark"] = 1] = "dark";
    })(FilterMode || (FilterMode = {}));
    function createCSSFilterStyleSheet(config, url, isTopFrame, fixes, index) {
        const filterValue = getCSSFilterValue(config);
        const reverseFilterValue = 'invert(100%) hue-rotate(180deg)';
        return cssFilterStyleSheetTemplate('html', filterValue, reverseFilterValue, config, url, isTopFrame, fixes, index);
    }
    function cssFilterStyleSheetTemplate(filterRoot, filterValue, reverseFilterValue, config, url, isTopFrame, fixes, index) {
        const fix = getInversionFixesFor(url, fixes, index);
        const lines = [];
        lines.push('@media screen {');
        // Add leading rule
        if (filterValue && isTopFrame) {
            lines.push('');
            lines.push('/* Leading rule */');
            lines.push(createLeadingRule(filterRoot, filterValue));
        }
        if (config.mode === FilterMode.dark) {
            // Add reverse rule
            lines.push('');
            lines.push('/* Reverse rule */');
            lines.push(createReverseRule(reverseFilterValue, fix));
        }
        if (config.useFont || config.textStroke > 0) {
            // Add text rule
            lines.push('');
            lines.push('/* Font */');
            lines.push(createTextStyle(config));
        }
        // Fix bad font hinting after inversion
        lines.push('');
        lines.push('/* Text contrast */');
        lines.push('html {');
        lines.push('  text-shadow: 0 0 0 !important;');
        lines.push('}');
        // Full screen fix
        lines.push('');
        lines.push('/* Full screen */');
        [':-webkit-full-screen', ':-moz-full-screen', ':fullscreen'].forEach((fullScreen) => {
            lines.push(`${fullScreen}, ${fullScreen} * {`);
            lines.push('  -webkit-filter: none !important;');
            lines.push('  filter: none !important;');
            lines.push('}');
        });
        if (isTopFrame) {
            const light = [255, 255, 255];
            // If browser affected by Chromium Issue 501582, set dark background on html
            // Or if browser is Firefox v102+
            const bgColor = light;
            lines.push('');
            lines.push('/* Page background */');
            lines.push('html {');
            lines.push(`  background: rgb(${bgColor.join(',')}) !important;`);
            lines.push('}');
        }
        if (fix.css && fix.css.length > 0 && config.mode === FilterMode.dark) {
            lines.push('');
            lines.push('/* Custom rules */');
            lines.push(fix.css);
        }
        lines.push('');
        lines.push('}');
        return lines.join('\n');
    }
    function getCSSFilterValue(config) {
        const filters = [];
        if (config.mode === FilterMode.dark) {
            filters.push('invert(100%) hue-rotate(180deg)');
        }
        if (config.brightness !== 100) {
            filters.push(`brightness(${config.brightness}%)`);
        }
        if (config.contrast !== 100) {
            filters.push(`contrast(${config.contrast}%)`);
        }
        if (config.grayscale !== 0) {
            filters.push(`grayscale(${config.grayscale}%)`);
        }
        if (config.sepia !== 0) {
            filters.push(`sepia(${config.sepia}%)`);
        }
        if (filters.length === 0) {
            return null;
        }
        return filters.join(' ');
    }
    function createLeadingRule(filterRoot, filterValue) {
        return [
            `${filterRoot} {`,
            `  -webkit-filter: ${filterValue} !important;`,
            `  filter: ${filterValue} !important;`,
            '}',
        ].join('\n');
    }
    function joinSelectors(selectors) {
        return selectors.map((s) => s.replace(/\,$/, '')).join(',\n');
    }
    function createReverseRule(reverseFilterValue, fix) {
        const lines = [];
        if (fix.invert.length > 0) {
            lines.push(`${joinSelectors(fix.invert)} {`);
            lines.push(`  -webkit-filter: ${reverseFilterValue} !important;`);
            lines.push(`  filter: ${reverseFilterValue} !important;`);
            lines.push('}');
        }
        if (fix.noinvert.length > 0) {
            lines.push(`${joinSelectors(fix.noinvert)} {`);
            lines.push('  -webkit-filter: none !important;');
            lines.push('  filter: none !important;');
            lines.push('}');
        }
        if (fix.removebg.length > 0) {
            lines.push(`${joinSelectors(fix.removebg)} {`);
            lines.push('  background: white !important;');
            lines.push('}');
        }
        return lines.join('\n');
    }
    /**
    * Returns fixes for a given URL.
    * If no matches found, common fixes will be returned.
    * @param url Site URL.
    * @param inversionFixes List of inversion fixes.
    */
    function getInversionFixesFor(url, fixes, index) {
        const inversionFixes = getSitesFixesFor(url, fixes, index, parseInversionFixes);
        const common = {
            url: inversionFixes[0].url,
            invert: inversionFixes[0].invert || [],
            noinvert: inversionFixes[0].noinvert || [],
            removebg: inversionFixes[0].removebg || [],
            css: inversionFixes[0].css || '',
        };
        if (url) {
            // Search for match with given URL
            const matches = inversionFixes
                .slice(1)
                .filter((s) => isURLInList(url, s.url))
                .sort((a, b) => b.url[0].length - a.url[0].length);
            if (matches.length > 0) {
                const found = matches[0];
                return {
                    url: found.url,
                    invert: common.invert.concat(found.invert || []),
                    noinvert: common.noinvert.concat(found.noinvert || []),
                    removebg: common.removebg.concat(found.removebg || []),
                    css: [common.css, found.css].filter((s) => s).join('\n'),
                };
            }
        }
        return common;
    }
    const inversionFixesCommands = {
        'INVERT': 'invert',
        'NO INVERT': 'noinvert',
        'REMOVE BG': 'removebg',
        'CSS': 'css',
    };
    function parseInversionFixes(text) {
        return parseSitesFixesConfig(text, {
            commands: Object.keys(inversionFixesCommands),
            getCommandPropName: (command) => inversionFixesCommands[command],
            parseCommandValue: (command, value) => {
                if (command === 'CSS') {
                    return value.trim();
                }
                return parseArray(value);
            },
        });
    }
    function formatInversionFixes(inversionFixes) {
        const fixes = inversionFixes.slice().sort((a, b) => compareURLPatterns(a.url[0], b.url[0]));
        return formatSitesFixesConfig(fixes, {
            props: Object.values(inversionFixesCommands),
            getPropCommandName: (prop) => Object.entries(inversionFixesCommands).find(([, p]) => p === prop)[0],
            formatPropValue: (prop, value) => {
                if (prop === 'css') {
                    return value.trim().replace(/\n+/g, '\n');
                }
                return formatArray(value).trim();
            },
            shouldIgnoreProp: (prop, value) => {
                if (prop === 'css') {
                    return !value;
                }
                return !(Array.isArray(value) && value.length > 0);
            },
        });
    }

    const detectorHintsCommands = {
        'TARGET': 'target',
        'MATCH': 'match',
        'NO DARK THEME': 'noDarkTheme',
        'SYSTEM THEME': 'systemTheme',
        'IFRAME': 'iframe',
    };
    const detectorParserOptions = {
        commands: Object.keys(detectorHintsCommands),
        getCommandPropName: (command) => detectorHintsCommands[command],
        parseCommandValue: (command, value) => {
            if (command === 'TARGET') {
                return value.trim();
            }
            if (command === 'NO DARK THEME' || command === 'SYSTEM THEME') {
                return true;
            }
            return parseArray(value);
        },
    };
    function parseDetectorHints(text) {
        return parseSitesFixesConfig(text, detectorParserOptions);
    }
    function getDetectorHintsFor(url, text, index) {
        const fixes = getSitesFixesFor(url, text, index, parseDetectorHints);
        if (fixes.length === 0) {
            return null;
        }
        return fixes;
    }

    const cssCommentsRegex = /\/\*[\s\S]*?\*\//g;
    function removeCSSComments(cssText) {
        return cssText.replace(cssCommentsRegex, '');
    }

    function parseCSS(cssText) {
        cssText = removeCSSComments(cssText);
        cssText = cssText.trim();
        if (!cssText) {
            return [];
        }
        const rules = [];
        // Find {...} ranges excluding inside of "...", [...] etc.
        const excludeRanges = getTokenExclusionRanges(cssText);
        const bracketRanges = getAllOpenCloseRanges(cssText, '{', '}', excludeRanges);
        let ruleStart = 0;
        bracketRanges.forEach((brackets) => {
            const key = cssText.substring(ruleStart, brackets.start).trim();
            const content = cssText.substring(brackets.start + 1, brackets.end - 1);
            if (key.startsWith('@')) {
                const typeEndIndex = key.search(/[\s\(]/);
                const rule = {
                    type: typeEndIndex < 0 ? key : key.substring(0, typeEndIndex),
                    query: typeEndIndex < 0 ? '' : key.substring(typeEndIndex).trim(),
                    rules: parseCSS(content),
                };
                rules.push(rule);
            }
            else {
                const rule = {
                    selectors: parseSelectors(key),
                    declarations: parseDeclarations(content),
                };
                rules.push(rule);
            }
            ruleStart = brackets.end;
        });
        return rules;
    }
    function getAllOpenCloseRanges(input, openToken, closeToken, excludeRanges = []) {
        const ranges = [];
        let i = 0;
        let range;
        while ((range = getOpenCloseRange(input, i, openToken, closeToken, excludeRanges))) {
            ranges.push(range);
            i = range.end;
        }
        return ranges;
    }
    function getTokenExclusionRanges(cssText) {
        const singleQuoteGoesFirst = cssText.indexOf("'") < cssText.indexOf('"');
        const firstQuote = singleQuoteGoesFirst ? "'" : '"';
        const secondQuote = singleQuoteGoesFirst ? '"' : "'";
        const excludeRanges = getAllOpenCloseRanges(cssText, firstQuote, firstQuote);
        excludeRanges.push(...getAllOpenCloseRanges(cssText, secondQuote, secondQuote, excludeRanges));
        excludeRanges.push(...getAllOpenCloseRanges(cssText, '[', ']', excludeRanges));
        excludeRanges.push(...getAllOpenCloseRanges(cssText, '(', ')', excludeRanges));
        return excludeRanges;
    }
    function parseSelectors(selectorText) {
        const excludeRanges = getTokenExclusionRanges(selectorText);
        return splitExcluding(selectorText, ',', excludeRanges);
    }
    function parseDeclarations(cssDeclarationsText) {
        const declarations = [];
        const excludeRanges = getTokenExclusionRanges(cssDeclarationsText);
        splitExcluding(cssDeclarationsText, ';', excludeRanges).forEach((part) => {
            const colonIndex = part.indexOf(':');
            if (colonIndex > 0) {
                const importantIndex = part.indexOf('!important');
                declarations.push({
                    property: part.substring(0, colonIndex).trim(),
                    value: part.substring(colonIndex + 1, importantIndex > 0 ? importantIndex : part.length).trim(),
                    important: importantIndex > 0,
                });
            }
        });
        return declarations;
    }
    function isParsedStyleRule(rule) {
        return 'selectors' in rule;
    }

    function formatCSS(cssText) {
        const parsed = parseCSS(cssText);
        return formatParsedCSS(parsed);
    }
    function formatParsedCSS(parsed) {
        const lines = [];
        const tab = '    ';
        function formatRule(rule, indent) {
            if (isParsedStyleRule(rule)) {
                formatStyleRule(rule, indent);
            }
            else {
                formatAtRule(rule, indent);
            }
        }
        function formatAtRule({ type, query, rules }, indent) {
            lines.push(`${indent}${type} ${query} {`);
            rules.forEach((child) => formatRule(child, `${indent}${tab}`));
            lines.push(`${indent}}`);
        }
        function formatStyleRule({ selectors, declarations }, indent) {
            const lastSelectorIndex = selectors.length - 1;
            selectors.forEach((selector, i) => {
                lines.push(`${indent}${selector}${i < lastSelectorIndex ? ',' : ' {'}`);
            });
            const sorted = sortDeclarations(declarations);
            sorted.forEach(({ property, value, important }) => {
                lines.push(`${indent}${tab}${property}: ${value}${important ? ' !important' : ''};`);
            });
            lines.push(`${indent}}`);
        }
        clearEmptyRules(parsed);
        parsed.forEach((rule) => formatRule(rule, ''));
        return lines.join('\n');
    }
    function sortDeclarations(declarations) {
        const prefixRegex = /^-[a-z]-/;
        return [...declarations].sort((a, b) => {
            const aProp = a.property;
            const bProp = b.property;
            const aPrefix = aProp.match(prefixRegex)?.[0] ?? '';
            const bPrefix = bProp.match(prefixRegex)?.[0] ?? '';
            const aNorm = aPrefix ? aProp.replace(prefixRegex, '') : aProp;
            const bNorm = bPrefix ? bProp.replace(prefixRegex, '') : bProp;
            if (aNorm === bNorm) {
                return aPrefix.localeCompare(bPrefix);
            }
            return aNorm.localeCompare(bNorm);
        });
    }
    function clearEmptyRules(rules) {
        for (let i = rules.length - 1; i >= 0; i--) {
            const rule = rules[i];
            if (isParsedStyleRule(rule)) {
                if (rule.declarations.length === 0) {
                    rules.splice(i, 1);
                }
            }
            else {
                clearEmptyRules(rule.rules);
                if (rule.rules.length === 0) {
                    rules.splice(i, 1);
                }
            }
        }
    }

    const dynamicThemeFixesCommands = {
        'INVERT': 'invert',
        'CSS': 'css',
        'IGNORE INLINE STYLE': 'ignoreInlineStyle',
        'IGNORE IMAGE ANALYSIS': 'ignoreImageAnalysis',
        'IGNORE CSS URL': 'ignoreCSSUrl',
    };
    function parseDynamicThemeFixes(text) {
        return parseSitesFixesConfig(text, {
            commands: Object.keys(dynamicThemeFixesCommands),
            getCommandPropName: (command) => dynamicThemeFixesCommands[command],
            parseCommandValue: (command, value) => {
                if (command === 'CSS') {
                    return value.trim();
                }
                return parseArray(value);
            },
        });
    }
    function formatDynamicThemeFixes(dynamicThemeFixes) {
        const fixes = dynamicThemeFixes.slice().sort((a, b) => compareURLPatterns(a.url[0], b.url[0]));
        return formatSitesFixesConfig(fixes, {
            props: Object.values(dynamicThemeFixesCommands),
            getPropCommandName: (prop) => Object.entries(dynamicThemeFixesCommands).find(([, p]) => p === prop)[0],
            formatPropValue: (prop, value) => {
                if (prop === 'css') {
                    return formatCSS(value);
                }
                return formatArray(value).trim();
            },
            shouldIgnoreProp: (prop, value) => {
                if (prop === 'css') {
                    return !value;
                }
                return !(Array.isArray(value) && value.length > 0);
            },
        });
    }
    function getDynamicThemeFixesFor(url, isTopFrame, text, index, enabledForPDF) {
        const fixes = getSitesFixesFor(url, text, index, parseDynamicThemeFixes);
        if (fixes.length === 0 || fixes[0].url[0] !== '*') {
            return null;
        }
        if (enabledForPDF) {
            // Copy part of fixes which will be mutated
            const commonFix = { ...fixes[0] };
            const pdfFixes = [
                commonFix,
                ...fixes.slice(1),
            ];
            const inversionFix = '\nembed[type="application/pdf"][src="about:blank"] { filter: invert(100%) contrast(90%); }' ;
            if (!commonFix.css.endsWith(inversionFix)) {
                commonFix.css += inversionFix;
            }
            if (['drive.google.com', 'mail.google.com'].includes(getDomain(url))) {
                const nestedInversionFix = 'div[role="dialog"] div[role="document"]';
                if (commonFix.invert.at(-1) !== nestedInversionFix) {
                    commonFix.invert.push(nestedInversionFix);
                }
            }
            return pdfFixes;
        }
        return fixes;
    }

    const darkTheme = {
        neutralBg: [16, 20, 23],
        neutralText: [167, 158, 139],
        redBg: [64, 12, 32],
        redText: [247, 142, 102],
        greenBg: [32, 64, 48],
        greenText: [128, 204, 148],
        blueBg: [32, 48, 64],
        blueText: [128, 182, 204],
        fadeBg: [16, 20, 23, 0.5],
        fadeText: [167, 158, 139, 0.5],
    };
    const lightTheme = {
        neutralBg: [255, 242, 228],
        neutralText: [0, 0, 0],
        redBg: [255, 85, 170],
        redText: [140, 14, 48],
        greenBg: [192, 255, 170],
        greenText: [0, 128, 0],
        blueBg: [173, 215, 229],
        blueText: [28, 16, 171],
        fadeBg: [0, 0, 0, 0.5],
        fadeText: [0, 0, 0, 0.5],
    };
    function rgb([r, g, b, a]) {
        if (typeof a === 'number') {
            return `rgba(${r}, ${g}, ${b}, ${a})`;
        }
        return `rgb(${r}, ${g}, ${b})`;
    }
    function mix(color1, color2, t) {
        return color1.map((c, i) => Math.round(c * (1 - t) + color2[i] * t));
    }
    function createStaticStylesheet(config, url, isTopFrame, staticThemes, staticThemesIndex) {
        const srcTheme = config.mode === 1 ? darkTheme : lightTheme;
        const theme = Object.entries(srcTheme).reduce((t, [prop, color]) => {
            const [r, g, b, a] = color;
            t[prop] = applyColorMatrix([r, g, b], createFilterMatrix({ ...config, mode: 0 }));
            if (a !== undefined) {
                t[prop].push(a);
            }
            return t;
        }, {});
        const themes = getSitesFixesFor(url, staticThemes, staticThemesIndex, parseStaticThemes);
        const commonTheme = themes.find((t) => t.url[0] === '*');
        const siteTheme = themes.find((t) => t.url[0] !== '*');
        if (!commonTheme) {
            return '';
        }
        const lines = [];
        if (!siteTheme || !siteTheme.noCommon) {
            lines.push('/* Common theme */');
            lines.push(...ruleGenerators.map((gen) => gen(commonTheme, theme)));
        }
        if (siteTheme) {
            lines.push(`/* Theme for ${siteTheme.url.join(' ')} */`);
            lines.push(...ruleGenerators.map((gen) => gen(siteTheme, theme)));
        }
        if (config.useFont || config.textStroke > 0) {
            lines.push('/* Font */');
            lines.push(createTextStyle(config));
        }
        return lines
            .filter((ln) => ln)
            .join('\n');
    }
    function createRuleGen(getSelectors, generateDeclarations, modifySelector = (s) => s) {
        return (siteTheme, themeColors) => {
            const selectors = getSelectors(siteTheme);
            if (selectors == null || selectors.length === 0) {
                return null;
            }
            const lines = [];
            selectors.forEach((s, i) => {
                let ln = modifySelector(s);
                if (i < selectors.length - 1) {
                    ln += ',';
                }
                else {
                    ln += ' {';
                }
                lines.push(ln);
            });
            const declarations = generateDeclarations(themeColors);
            declarations.forEach((d) => lines.push(`    ${d} !important;`));
            lines.push('}');
            return lines.join('\n');
        };
    }
    const mx = {
        bg: {
            hover: 0.075,
            active: 0.1,
        },
        fg: {
            hover: 0.25,
            active: 0.5,
        },
        border: 0.5,
    };
    const ruleGenerators = [
        createRuleGen((t) => t.neutralBg, (t) => [`background-color: ${rgb(t.neutralBg)}`]),
        createRuleGen((t) => t.neutralBgActive, (t) => [`background-color: ${rgb(t.neutralBg)}`]),
        createRuleGen((t) => t.neutralBgActive, (t) => [`background-color: ${rgb(mix(t.neutralBg, [255, 255, 255], mx.bg.hover))}`], (s) => `${s}:hover`),
        createRuleGen((t) => t.neutralBgActive, (t) => [`background-color: ${rgb(mix(t.neutralBg, [255, 255, 255], mx.bg.active))}`], (s) => `${s}:active, ${s}:focus`),
        createRuleGen((t) => t.neutralText, (t) => [`color: ${rgb(t.neutralText)}`]),
        createRuleGen((t) => t.neutralTextActive, (t) => [`color: ${rgb(t.neutralText)}`]),
        createRuleGen((t) => t.neutralTextActive, (t) => [`color: ${rgb(mix(t.neutralText, [255, 255, 255], mx.fg.hover))}`], (s) => `${s}:hover`),
        createRuleGen((t) => t.neutralTextActive, (t) => [`color: ${rgb(mix(t.neutralText, [255, 255, 255], mx.fg.active))}`], (s) => `${s}:active, ${s}:focus`),
        createRuleGen((t) => t.neutralBorder, (t) => [`border-color: ${rgb(mix(t.neutralBg, t.neutralText, mx.border))}`]),
        createRuleGen((t) => t.redBg, (t) => [`background-color: ${rgb(t.redBg)}`]),
        createRuleGen((t) => t.redBgActive, (t) => [`background-color: ${rgb(t.redBg)}`]),
        createRuleGen((t) => t.redBgActive, (t) => [`background-color: ${rgb(mix(t.redBg, [255, 0, 64], mx.bg.hover))}`], (s) => `${s}:hover`),
        createRuleGen((t) => t.redBgActive, (t) => [`background-color: ${rgb(mix(t.redBg, [255, 0, 64], mx.bg.active))}`], (s) => `${s}:active, ${s}:focus`),
        createRuleGen((t) => t.redText, (t) => [`color: ${rgb(t.redText)}`]),
        createRuleGen((t) => t.redTextActive, (t) => [`color: ${rgb(t.redText)}`]),
        createRuleGen((t) => t.redTextActive, (t) => [`color: ${rgb(mix(t.redText, [255, 255, 0], mx.fg.hover))}`], (s) => `${s}:hover`),
        createRuleGen((t) => t.redTextActive, (t) => [`color: ${rgb(mix(t.redText, [255, 255, 0], mx.fg.active))}`], (s) => `${s}:active, ${s}:focus`),
        createRuleGen((t) => t.redBorder, (t) => [`border-color: ${rgb(mix(t.redBg, t.redText, mx.border))}`]),
        createRuleGen((t) => t.greenBg, (t) => [`background-color: ${rgb(t.greenBg)}`]),
        createRuleGen((t) => t.greenBgActive, (t) => [`background-color: ${rgb(t.greenBg)}`]),
        createRuleGen((t) => t.greenBgActive, (t) => [`background-color: ${rgb(mix(t.greenBg, [128, 255, 182], mx.bg.hover))}`], (s) => `${s}:hover`),
        createRuleGen((t) => t.greenBgActive, (t) => [`background-color: ${rgb(mix(t.greenBg, [128, 255, 182], mx.bg.active))}`], (s) => `${s}:active, ${s}:focus`),
        createRuleGen((t) => t.greenText, (t) => [`color: ${rgb(t.greenText)}`]),
        createRuleGen((t) => t.greenTextActive, (t) => [`color: ${rgb(t.greenText)}`]),
        createRuleGen((t) => t.greenTextActive, (t) => [`color: ${rgb(mix(t.greenText, [182, 255, 224], mx.fg.hover))}`], (s) => `${s}:hover`),
        createRuleGen((t) => t.greenTextActive, (t) => [`color: ${rgb(mix(t.greenText, [182, 255, 224], mx.fg.active))}`], (s) => `${s}:active, ${s}:focus`),
        createRuleGen((t) => t.greenBorder, (t) => [`border-color: ${rgb(mix(t.greenBg, t.greenText, mx.border))}`]),
        createRuleGen((t) => t.blueBg, (t) => [`background-color: ${rgb(t.blueBg)}`]),
        createRuleGen((t) => t.blueBgActive, (t) => [`background-color: ${rgb(t.blueBg)}`]),
        createRuleGen((t) => t.blueBgActive, (t) => [`background-color: ${rgb(mix(t.blueBg, [0, 128, 255], mx.bg.hover))}`], (s) => `${s}:hover`),
        createRuleGen((t) => t.blueBgActive, (t) => [`background-color: ${rgb(mix(t.blueBg, [0, 128, 255], mx.bg.active))}`], (s) => `${s}:active, ${s}:focus`),
        createRuleGen((t) => t.blueText, (t) => [`color: ${rgb(t.blueText)}`]),
        createRuleGen((t) => t.blueTextActive, (t) => [`color: ${rgb(t.blueText)}`]),
        createRuleGen((t) => t.blueTextActive, (t) => [`color: ${rgb(mix(t.blueText, [182, 224, 255], mx.fg.hover))}`], (s) => `${s}:hover`),
        createRuleGen((t) => t.blueTextActive, (t) => [`color: ${rgb(mix(t.blueText, [182, 224, 255], mx.fg.active))}`], (s) => `${s}:active, ${s}:focus`),
        createRuleGen((t) => t.blueBorder, (t) => [`border-color: ${rgb(mix(t.blueBg, t.blueText, mx.border))}`]),
        createRuleGen((t) => t.fadeBg, (t) => [`background-color: ${rgb(t.fadeBg)}`]),
        createRuleGen((t) => t.fadeText, (t) => [`color: ${rgb(t.fadeText)}`]),
        createRuleGen((t) => t.transparentBg, () => ['background-color: transparent']),
        createRuleGen((t) => t.noImage, () => ['background-image: none']),
        createRuleGen((t) => t.invert, () => ['filter: invert(100%) hue-rotate(180deg)']),
    ];
    const staticThemeCommands = {
        'NO COMMON': 'noCommon',
        'NEUTRAL BG': 'neutralBg',
        'NEUTRAL BG ACTIVE': 'neutralBgActive',
        'NEUTRAL TEXT': 'neutralText',
        'NEUTRAL TEXT ACTIVE': 'neutralTextActive',
        'NEUTRAL BORDER': 'neutralBorder',
        'RED BG': 'redBg',
        'RED BG ACTIVE': 'redBgActive',
        'RED TEXT': 'redText',
        'RED TEXT ACTIVE': 'redTextActive',
        'RED BORDER': 'redBorder',
        'GREEN BG': 'greenBg',
        'GREEN BG ACTIVE': 'greenBgActive',
        'GREEN TEXT': 'greenText',
        'GREEN TEXT ACTIVE': 'greenTextActive',
        'GREEN BORDER': 'greenBorder',
        'BLUE BG': 'blueBg',
        'BLUE BG ACTIVE': 'blueBgActive',
        'BLUE TEXT': 'blueText',
        'BLUE TEXT ACTIVE': 'blueTextActive',
        'BLUE BORDER': 'blueBorder',
        'FADE BG': 'fadeBg',
        'FADE TEXT': 'fadeText',
        'TRANSPARENT BG': 'transparentBg',
        'NO IMAGE': 'noImage',
        'INVERT': 'invert',
    };
    function parseStaticThemes($themes) {
        return parseSitesFixesConfig($themes, {
            commands: Object.keys(staticThemeCommands),
            getCommandPropName: (command) => staticThemeCommands[command],
            parseCommandValue: (command, value) => {
                if (command === 'NO COMMON') {
                    return true;
                }
                return parseArray(value);
            },
        });
    }
    function camelCaseToUpperCase(text) {
        return text.replace(/([a-z])([A-Z])/g, '$1 $2').toUpperCase();
    }
    function formatStaticThemes(staticThemes) {
        const themes = staticThemes.slice().sort((a, b) => compareURLPatterns(a.url[0], b.url[0]));
        return formatSitesFixesConfig(themes, {
            props: Object.values(staticThemeCommands),
            getPropCommandName: camelCaseToUpperCase,
            formatPropValue: (prop, value) => {
                if (prop === 'noCommon') {
                    return '';
                }
                return formatArray(value).trim();
            },
            shouldIgnoreProp: (prop, value) => {
                if (prop === 'noCommon') {
                    return !value;
                }
                return !(Array.isArray(value) && value.length > 0);
            },
        });
    }

    function createSVGFilterStylesheet(config, url, isTopFrame, fixes, index) {
        let filterValue;
        let reverseFilterValue;
        {
            // Chrome fails with "Unsafe attempt to load URL ... Domains, protocols and ports must match.
            filterValue = 'url(#dark-reader-filter)';
            reverseFilterValue = 'url(#dark-reader-reverse-filter)';
        }
        const filterRoot = 'html';
        return cssFilterStyleSheetTemplate(filterRoot, filterValue, reverseFilterValue, config, url, isTopFrame, fixes, index);
    }
    function toSVGMatrix(matrix) {
        return matrix.slice(0, 4).map((m) => m.map((m) => m.toFixed(3)).join(' ')).join(' ');
    }
    function getSVGFilterMatrixValue(config) {
        return toSVGMatrix(createFilterMatrix(config));
    }
    function getSVGReverseFilterMatrixValue() {
        return toSVGMatrix(Matrix.invertNHue());
    }

    var ThemeEngine;
    (function (ThemeEngine) {
        ThemeEngine["cssFilter"] = "cssFilter";
        ThemeEngine["svgFilter"] = "svgFilter";
        ThemeEngine["staticTheme"] = "staticTheme";
        ThemeEngine["dynamicTheme"] = "dynamicTheme";
    })(ThemeEngine || (ThemeEngine = {}));

    var AutomationMode;
    (function (AutomationMode) {
        AutomationMode["NONE"] = "";
        AutomationMode["TIME"] = "time";
        AutomationMode["SYSTEM"] = "system";
        AutomationMode["LOCATION"] = "location";
    })(AutomationMode || (AutomationMode = {}));

    function debounce(delay, fn) {
        let timeoutId = null;
        return ((...args) => {
            if (timeoutId) {
                clearTimeout(timeoutId);
            }
            timeoutId = setTimeout(() => {
                timeoutId = null;
                fn(...args);
            }, delay);
        });
    }

    class PromiseBarrier {
        resolves = [];
        rejects = [];
        wasResolved = false;
        wasRejected = false;
        resolution;
        reason;
        async entry() {
            if (this.wasResolved) {
                return Promise.resolve(this.resolution);
            }
            if (this.wasRejected) {
                return Promise.reject(this.reason);
            }
            return new Promise((resolve, reject) => {
                this.resolves.push(resolve);
                this.rejects.push(reject);
            });
        }
        async resolve(value) {
            if (this.wasRejected || this.wasResolved) {
                return;
            }
            this.wasResolved = true;
            this.resolution = value;
            this.resolves.forEach((resolve) => resolve(value));
            this.resolves = [];
            this.rejects = [];
            return new Promise((resolve) => setTimeout(() => resolve()));
        }
        async reject(reason) {
            if (this.wasRejected || this.wasResolved) {
                return;
            }
            this.wasRejected = true;
            this.reason = reason;
            this.rejects.forEach((reject) => reject(reason));
            this.resolves = [];
            this.rejects = [];
            return new Promise((resolve) => setTimeout(() => resolve()));
        }
        isPending() {
            return !this.wasResolved && !this.wasRejected;
        }
        isFulfilled() {
            return this.wasResolved;
        }
        isRejected() {
            return this.wasRejected;
        }
    }

    var StateManagerImplState;
    (function (StateManagerImplState) {
        StateManagerImplState[StateManagerImplState["INITIAL"] = 0] = "INITIAL";
        StateManagerImplState[StateManagerImplState["LOADING"] = 1] = "LOADING";
        StateManagerImplState[StateManagerImplState["READY"] = 2] = "READY";
        StateManagerImplState[StateManagerImplState["SAVING"] = 3] = "SAVING";
        StateManagerImplState[StateManagerImplState["SAVING_OVERRIDE"] = 4] = "SAVING_OVERRIDE";
        StateManagerImplState[StateManagerImplState["ONCHANGE_RACE"] = 5] = "ONCHANGE_RACE";
        StateManagerImplState[StateManagerImplState["RECOVERY"] = 6] = "RECOVERY";
    })(StateManagerImplState || (StateManagerImplState = {}));
    class StateManagerImpl {
        localStorageKey;
        parent;
        defaults;
        logWarn;
        meta;
        barrier = null;
        storage;
        listeners;
        constructor(localStorageKey, parent, defaults, storage, addListener, logWarn) {
            this.localStorageKey = localStorageKey;
            this.parent = parent;
            this.defaults = defaults;
            this.storage = storage;
            addListener((change) => this.onChange(change));
            this.logWarn = logWarn;
            this.meta = StateManagerImplState.INITIAL;
            this.barrier = new PromiseBarrier();
            this.listeners = new Set();
            // TODO(Anton): consider calling this.loadState() to preload data,
            // and remove StateManagerImplState.INITIAL.
        }
        collectState() {
            const state = {};
            for (const key of Object.keys(this.defaults)) {
                state[key] = this.parent[key] || this.defaults[key];
            }
            return state;
        }
        applyState(storage) {
            Object.assign(this.parent, this.defaults, storage);
        }
        releaseBarrier() {
            const barrier = this.barrier;
            this.barrier = new PromiseBarrier();
            barrier.resolve();
        }
        notifyListeners() {
            this.listeners.forEach((listener) => listener());
        }
        onChange(state) {
            switch (this.meta) {
                case StateManagerImplState.INITIAL:
                    this.meta = StateManagerImplState.READY;
                // fallthrough
                case StateManagerImplState.READY:
                    this.applyState(state);
                    this.notifyListeners();
                    return;
                case StateManagerImplState.LOADING:
                    this.meta = StateManagerImplState.ONCHANGE_RACE;
                    return;
                case StateManagerImplState.SAVING:
                    this.meta = StateManagerImplState.ONCHANGE_RACE;
                    return;
                case StateManagerImplState.SAVING_OVERRIDE:
                    this.meta = StateManagerImplState.ONCHANGE_RACE;
                    break;
                case StateManagerImplState.ONCHANGE_RACE:
                    // We are already waiting for an active read/write operation to end
                    break;
                case StateManagerImplState.RECOVERY:
                    this.meta = StateManagerImplState.ONCHANGE_RACE;
                    break;
            }
        }
        saveStateInternal() {
            this.storage.set({ [this.localStorageKey]: this.collectState() }, () => {
                switch (this.meta) {
                    case StateManagerImplState.INITIAL:
                    // fallthrough
                    case StateManagerImplState.LOADING:
                    // fallthrough
                    case StateManagerImplState.READY:
                    // fallthrough
                    case StateManagerImplState.RECOVERY:
                        this.logWarn('Unexpected state. Possible data race!');
                        this.meta = StateManagerImplState.ONCHANGE_RACE;
                        this.loadStateInternal();
                        return;
                    case StateManagerImplState.SAVING:
                        this.meta = StateManagerImplState.READY;
                        this.releaseBarrier();
                        return;
                    case StateManagerImplState.SAVING_OVERRIDE:
                        this.meta = StateManagerImplState.SAVING;
                        this.saveStateInternal();
                        return;
                    case StateManagerImplState.ONCHANGE_RACE:
                        this.meta = StateManagerImplState.RECOVERY;
                        this.loadStateInternal();
                }
            });
        }
        // This function is not guaranteed to save state before returning
        async saveState() {
            switch (this.meta) {
                case StateManagerImplState.INITIAL:
                    // Make sure not to overwrite data before it is loaded
                    this.logWarn('StateManager.saveState was called before StateManager.loadState(). Possible data race! Loading data instead.');
                    return this.loadState();
                case StateManagerImplState.LOADING:
                    // Need to wait for active read operation to end
                    this.logWarn('StateManager.saveState was called before StateManager.loadState() resolved. Possible data race! Loading data instead.');
                    return this.barrier.entry();
                case StateManagerImplState.READY: {
                    this.meta = StateManagerImplState.SAVING;
                    const entry = this.barrier.entry();
                    this.saveStateInternal();
                    return entry;
                }
                case StateManagerImplState.SAVING:
                    // Another save is in progress
                    this.meta = StateManagerImplState.SAVING_OVERRIDE;
                    return this.barrier.entry();
                case StateManagerImplState.SAVING_OVERRIDE:
                    return this.barrier.entry();
                case StateManagerImplState.ONCHANGE_RACE:
                    this.logWarn('StateManager.saveState was called during active read/write operation. Possible data race! Loading data instead.');
                    return this.barrier.entry();
                case StateManagerImplState.RECOVERY:
                    this.logWarn('StateManager.saveState was called during active read operation. Possible data race! Waiting for data load instead.');
                    return this.barrier.entry();
            }
        }
        loadStateInternal() {
            this.storage.get(this.localStorageKey, (data) => {
                switch (this.meta) {
                    case StateManagerImplState.INITIAL:
                    case StateManagerImplState.READY:
                    case StateManagerImplState.SAVING:
                    case StateManagerImplState.SAVING_OVERRIDE:
                        this.logWarn('Unexpected state. Possible data race!');
                        return;
                    case StateManagerImplState.LOADING:
                        this.meta = StateManagerImplState.READY;
                        this.applyState(data[this.localStorageKey]);
                        this.releaseBarrier();
                        return;
                    case StateManagerImplState.ONCHANGE_RACE:
                        this.meta = StateManagerImplState.RECOVERY;
                        this.loadStateInternal();
                    // eslint-disable-next-line no-fallthrough
                    case StateManagerImplState.RECOVERY:
                        this.meta = StateManagerImplState.READY;
                        this.applyState(data[this.localStorageKey]);
                        this.releaseBarrier();
                        this.notifyListeners();
                }
            });
        }
        async loadState() {
            switch (this.meta) {
                case StateManagerImplState.INITIAL: {
                    this.meta = StateManagerImplState.LOADING;
                    const entry = this.barrier.entry();
                    this.loadStateInternal();
                    return entry;
                }
                case StateManagerImplState.READY:
                    return;
                case StateManagerImplState.SAVING:
                    return this.barrier.entry();
                case StateManagerImplState.SAVING_OVERRIDE:
                    return this.barrier.entry();
                case StateManagerImplState.LOADING:
                    return this.barrier.entry();
                case StateManagerImplState.ONCHANGE_RACE:
                    return this.barrier.entry();
                case StateManagerImplState.RECOVERY:
                    return this.barrier.entry();
            }
        }
        addChangeListener(callback) {
            this.listeners.add(callback);
        }
        getStateForTesting() {
            {
                return '';
            }
        }
    }

    /**
     * This class exists only to simplify Jest testing of the real implementation
     * which is in StateManagerImpl class.
     */
    class StateManager {
        stateManager;
        constructor(localStorageKey, parent, defaults, logWarn) {
            {
                function addListener(listener) {
                    chrome.storage.local.onChanged.addListener((changes) => {
                        if (localStorageKey in changes) {
                            listener(changes[localStorageKey].newValue);
                        }
                    });
                }
                this.stateManager = new StateManagerImpl(localStorageKey, parent, defaults, chrome.storage.local, addListener, logWarn);
            }
        }
        async saveState() {
            if (this.stateManager) {
                return this.stateManager.saveState();
            }
        }
        async loadState() {
            if (this.stateManager) {
                return this.stateManager.loadState();
            }
        }
    }

    // Promissified version of chrome.tabs.query
    async function queryTabs(query = {}) {
        return new Promise((resolve) => chrome.tabs.query(query, resolve));
    }
    /**
     * Attempts to find the current active tab
     * Despite all efforts, sometimes active tab may not be determined so we explicitly return nullable value,
     * and handle this case in callers explicitly
     */
    async function getActiveTab() {
        let log = null;
        let tab = (await queryTabs({
            active: true,
            lastFocusedWindow: true,
            // Explicitly exclude Dark Reader's Dev Tools and other special windows from the query
            windowType: 'normal',
        }))[0];
        if (!tab) {
            tab = (await queryTabs({
                active: true,
                lastFocusedWindow: true,
                windowType: 'app',
            }))[0];
        }
        if (!tab) {
            {
                log = 'method 1';
            }
            // When Dark Reader's DevTools are open, last focused window might be the DevTools window
            // so we lift this restriction and try again (with the best guess)
            tab = (await queryTabs({
                active: true,
                windowType: 'normal',
            }))[0];
        }
        if (!tab) {
            {
                log = 'method 2';
            }
            tab = (await queryTabs({
                active: true,
                windowType: 'app',
            }))[0];
        }
        if (log) {
            console.warn(`TabManager.getActiveTab() could not reliably find the active tab, picking the best guess ${log}`, tab);
        }
        // In rare cases tab can be null, despite what TypeScript says
        return tab || null;
    }

    const DEFAULT_COLORS = {
        darkScheme: {
            background: '#181a1b',
            text: '#e8e6e3',
        },
        lightScheme: {
            background: '#dcdad7',
            text: '#181a1b',
        },
    };
    const DEFAULT_THEME = {
        mode: 1,
        brightness: 100,
        contrast: 100,
        grayscale: 0,
        sepia: 0,
        useFont: false,
        fontFamily: isMacOS ? 'Helvetica Neue' : isWindows ? 'Segoe UI' : 'Open Sans',
        textStroke: 0,
        engine: ThemeEngine.dynamicTheme,
        stylesheet: '',
        darkSchemeBackgroundColor: DEFAULT_COLORS.darkScheme.background,
        darkSchemeTextColor: DEFAULT_COLORS.darkScheme.text,
        lightSchemeBackgroundColor: DEFAULT_COLORS.lightScheme.background,
        lightSchemeTextColor: DEFAULT_COLORS.lightScheme.text,
        scrollbarColor: '',
        selectionColor: 'auto',
        styleSystemControls: false ,
        lightColorScheme: 'Default',
        darkColorScheme: 'Default',
        immediateModify: false,
    };
    const DEFAULT_COLORSCHEME = {
        light: {
            Default: {
                backgroundColor: DEFAULT_COLORS.lightScheme.background,
                textColor: DEFAULT_COLORS.lightScheme.text,
            },
        },
        dark: {
            Default: {
                backgroundColor: DEFAULT_COLORS.darkScheme.background,
                textColor: DEFAULT_COLORS.darkScheme.text,
            },
        },
    };
    const filterModeSites = [
        '*.officeapps.live.com',
        '*.sharepoint.com',
        'docs.google.com',
        'onedrive.live.com',
    ];
    const DEFAULT_SETTINGS = {
        schemeVersion: 0,
        enabled: true,
        fetchNews: true,
        theme: DEFAULT_THEME,
        presets: [],
        customThemes: filterModeSites.map((url) => {
            const engine = ThemeEngine.cssFilter;
            return {
                url: [url],
                theme: { ...DEFAULT_THEME, engine },
                builtIn: true,
            };
        }),
        enabledByDefault: true,
        enabledFor: [],
        disabledFor: [],
        changeBrowserTheme: false,
        syncSettings: true,
        syncSitesFixes: false,
        automation: {
            enabled: isEdge && isMobile ? true : false,
            mode: isEdge && isMobile ? AutomationMode.SYSTEM : AutomationMode.NONE,
            behavior: 'OnOff',
        },
        time: {
            activation: '18:00',
            deactivation: '9:00',
        },
        location: {
            latitude: null,
            longitude: null,
        },
        previewNewDesign: false,
        previewNewestDesign: false,
        enableForPDF: true,
        enableForProtectedPages: false,
        enableContextMenus: false,
        detectDarkTheme: true,
    };

    // Seperator is to indicate that the it should start with a new defined colorscheme.
    const SEPERATOR = '='.repeat(32);
    // Just a few constants to make the code more readable.
    const backgroundPropertyLength = 'background: '.length;
    const textPropertyLength = 'text: '.length;
    // Should return a humanized version of the given number.
    // For example:
    // humanizeNumber(0) => '0'
    // humanizeNumber(1) => '1st'
    // humanizeNumber(2) => '2nd'
    // humanizeNumber(3) => '3rd'
    // humanizeNumber(4) => '4th'
    // TODO(Anton): rewrite me with case-default
    // eslint-disable-next-line
    // @ts-ignore
    const humanizeNumber = (number) => {
        if (number > 3) {
            return `${number}th`;
        }
        switch (number) {
            case 0:
                return '0';
            case 1:
                return '1st';
            case 2:
                return '2nd';
            case 3:
                return '3rd';
        }
    };
    // Should return if the given string is a valid 3 or 6 digit hex color.
    const isValidHexColor = (color) => {
        return /^#([0-9a-fA-F]{3}){1,2}$/.test(color);
    };
    function parseColorSchemeConfig(config) {
        // Let's first get all "possible" sections of the text.
        // We're adding `\n` so the sections "first" word is the
        // name of the color scheme. We could remove this and
        // skip this in the process of parsing, but because
        // the first entry will not have this first '\n' it will
        // be more complicated to otherwise just add this '\n' here.
        const sections = config.split(`${SEPERATOR}\n\n`);
        const definedColorSchemeNames = new Set();
        let lastDefinedColorSchemeName = '';
        const definedColorSchemes = {
            light: {},
            dark: {},
        };
        // Define the interrupt and error variables.
        // Interrupt is to indicate that the parsing should stop.
        // But because we cannot break out of a forEach loop,
        // we need to use an interrupt variable.
        // The error is to indicate that there was an error.
        // And also the reason why the parsing failed.
        // It will be the first error that is found.
        let interrupt = false;
        let error = null;
        const throwError = (message) => {
            if (!interrupt) {
                interrupt = true;
                error = message;
            }
        };
        // Now we will iterate troughout each section.
        // We will always assume bad-faith and make sure to have
        // guards in place. As this could also be bad code.
        // We shouldn't rely on that the input is correct.
        sections.forEach((section) => {
            // Check if the interrupt variable is set.
            // If it is, we should stop parsing.
            if (interrupt) {
                return;
            }
            // First we split the section into lines.
            const lines = section.split('\n');
            // We have to make sure that the first line is a valid color scheme name.
            // We will also make sure that the name is not already defined.
            const name = lines[0];
            if (!name) {
                throwError('No color scheme name was found.');
                return;
            }
            if (definedColorSchemeNames.has(name)) {
                throwError(`The color scheme name "${name}" is already defined.`);
                return;
            }
            // Check if the name is on alphabetical order.
            if (lastDefinedColorSchemeName && lastDefinedColorSchemeName !== 'Default' && name.localeCompare(lastDefinedColorSchemeName) < 0) {
                throwError(`The color scheme name "${name}" is not in alphabetical order.`);
                return;
            }
            lastDefinedColorSchemeName = name;
            // Add the name to the set of defined color scheme names.
            definedColorSchemeNames.add(name);
            // Check if line[1] is empty, which is must be.
            if (lines[1]) {
                throwError(`The second line of the color scheme "${name}" is not empty.`);
                return;
            }
            const checkVariant = (lineIndex, isSecondVariant) => {
                // Get the possible variant name.
                const variant = lines[lineIndex];
                if (!variant) {
                    throwError(`The third line of the color scheme "${name}" is not defined.`);
                    return;
                }
                // Check if the variant is valid.
                // if isSecondVariant is true, then we will check if the variant is 'Light', 'Dark' is not considered valid.
                if (variant !== 'LIGHT' && variant !== 'DARK' && (isSecondVariant && variant === 'Light')) {
                    throwError(`The ${humanizeNumber(lineIndex)} line of the color scheme "${name}" is not a valid variant.`);
                    return;
                }
                // Get the possible background color.
                const firstProperty = lines[lineIndex + 1];
                if (!firstProperty) {
                    throwError(`The ${humanizeNumber(lineIndex + 1)} line of the color scheme "${name}" is not defined.`);
                    return;
                }
                // Check if the property is background color.
                if (!firstProperty.startsWith('background: ')) {
                    throwError(`The ${humanizeNumber(lineIndex + 1)} line of the color scheme "${name}" is not background-color property.`);
                    return;
                }
                // Get the background color and check if it is a valid hex color.
                const backgroundColor = firstProperty.slice(backgroundPropertyLength);
                if (!isValidHexColor(backgroundColor)) {
                    throwError(`The ${humanizeNumber(lineIndex + 1)} line of the color scheme "${name}" is not a valid hex color.`);
                    return;
                }
                // Get the possible text color.
                const secondProperty = lines[lineIndex + 2];
                if (!secondProperty) {
                    throwError(`The ${humanizeNumber(lineIndex + 2)} line of the color scheme "${name}" is not defined.`);
                    return;
                }
                // Check if the property is text color.
                if (!secondProperty.startsWith('text: ')) {
                    throwError(`The ${humanizeNumber(lineIndex + 2)} line of the color scheme "${name}" is not text-color property.`);
                    return;
                }
                // Get the text color and check if it is a valid hex color.
                const textColor = secondProperty.slice(textPropertyLength);
                if (!isValidHexColor(textColor)) {
                    throwError(`The ${humanizeNumber(lineIndex + 2)} line of the color scheme "${name}" is not a valid hex color.`);
                    return;
                }
                // If the variant is the second variant, then we will return the variant and the variant name.
                return {
                    backgroundColor,
                    textColor,
                    variant,
                };
            };
            const firstVariant = checkVariant(2, false);
            const isFirstVariantLight = firstVariant.variant === 'LIGHT';
            delete firstVariant.variant;
            // If the interrupt variable is set, we should stop parsing.
            if (interrupt) {
                return;
            }
            let secondVariant = null;
            let isSecondVariantLight = false;
            // Check if the 7th line is defined otherwise we should stop parsing.
            if (lines[6]) {
                secondVariant = checkVariant(6, true);
                isSecondVariantLight = secondVariant.variant === 'LIGHT';
                delete secondVariant.variant;
                // If the interrupt variable is set, we should stop parsing.
                if (interrupt) {
                    return;
                }
                // Must end with 1 new line(two Variants).
                if (lines.length > 11 || lines[9] || lines[10]) {
                    throwError(`The color scheme "${name}" doesn't end with 1 new line.`);
                    return;
                }
            }
            else if (lines.length > 7) {
                throwError(`The color scheme "${name}" doesn't end with 1 new line.`);
                return;
            }
            if (secondVariant) {
                if (isFirstVariantLight === isSecondVariantLight) {
                    throwError(`The color scheme "${name}" has the same variant twice.`);
                    return;
                }
                if (isFirstVariantLight) {
                    definedColorSchemes.light[name] = firstVariant;
                    definedColorSchemes.dark[name] = secondVariant;
                }
                else {
                    definedColorSchemes.light[name] = secondVariant;
                    definedColorSchemes.dark[name] = firstVariant;
                }
            }
            else if (isFirstVariantLight) {
                definedColorSchemes.light[name] = firstVariant;
            }
            else {
                definedColorSchemes.dark[name] = firstVariant;
            }
        });
        return { result: definedColorSchemes, error: error };
    }

    function isBoolean(x) {
        return typeof x === 'boolean';
    }
    function isPlainObject(x) {
        return typeof x === 'object' && x != null && !Array.isArray(x);
    }
    function isArray(x) {
        return Array.isArray(x);
    }
    function isString(x) {
        return typeof x === 'string';
    }
    function isNonEmptyString(x) {
        return x && isString(x);
    }
    function isNonEmptyArrayOfNonEmptyStrings(x) {
        return Array.isArray(x) && x.length > 0 && x.every((s) => isNonEmptyString(s));
    }
    function isRegExpMatch(regexp) {
        return (x) => {
            return isString(x) && x.match(regexp) != null;
        };
    }
    const isTime = isRegExpMatch(/^((0?[0-9])|(1[0-9])|(2[0-3])):([0-5][0-9])$/);
    function isNumber(x) {
        return typeof x === 'number' && !isNaN(x);
    }
    function isNumberBetween(min, max) {
        return (x) => {
            return isNumber(x) && x >= min && x <= max;
        };
    }
    function isOneOf(...values) {
        return (x) => values.includes(x);
    }
    function hasRequiredProperties(obj, keys) {
        return keys.every((key) => obj.hasOwnProperty(key));
    }
    function createValidator() {
        const errors = [];
        function validateProperty(obj, key, validator, fallback) {
            if (!obj.hasOwnProperty(key) || validator(obj[key])) {
                return;
            }
            errors.push(`Unexpected value for "${key}": ${JSON.stringify(obj[key])}`);
            obj[key] = fallback[key];
        }
        function validateArray(obj, key, validator) {
            if (!obj.hasOwnProperty(key)) {
                return;
            }
            const wrongValues = new Set();
            const arr = obj[key];
            for (let i = 0; i < arr.length; i++) {
                if (!validator(arr[i])) {
                    wrongValues.add(arr[i]);
                    arr.splice(i, 1);
                    i--;
                }
            }
            if (wrongValues.size > 0) {
                errors.push(`Array "${key}" has wrong values: ${Array.from(wrongValues).map((v) => JSON.stringify(v)).join('; ')}`);
            }
        }
        return { validateProperty, validateArray, errors };
    }
    function validateSettings(settings) {
        if (!isPlainObject(settings)) {
            return { errors: ['Settings are not a plain object'], settings: DEFAULT_SETTINGS };
        }
        const { validateProperty, validateArray, errors } = createValidator();
        const isValidPresetTheme = (theme) => {
            if (!isPlainObject(theme)) {
                return false;
            }
            const { errors: themeErrors } = validateTheme(theme);
            return themeErrors.length === 0;
        };
        validateProperty(settings, 'schemeVersion', isNumber, DEFAULT_SETTINGS);
        validateProperty(settings, 'enabled', isBoolean, DEFAULT_SETTINGS);
        validateProperty(settings, 'fetchNews', isBoolean, DEFAULT_SETTINGS);
        validateProperty(settings, 'theme', isPlainObject, DEFAULT_SETTINGS);
        const { errors: themeErrors } = validateTheme(settings.theme);
        errors.push(...themeErrors);
        validateProperty(settings, 'presets', isArray, DEFAULT_SETTINGS);
        validateArray(settings, 'presets', (preset) => {
            const presetValidator = createValidator();
            if (!(isPlainObject(preset) && hasRequiredProperties(preset, ['id', 'name', 'urls', 'theme']))) {
                return false;
            }
            presetValidator.validateProperty(preset, 'id', isNonEmptyString, preset);
            presetValidator.validateProperty(preset, 'name', isNonEmptyString, preset);
            presetValidator.validateProperty(preset, 'urls', isNonEmptyArrayOfNonEmptyStrings, preset);
            presetValidator.validateProperty(preset, 'theme', isValidPresetTheme, preset);
            return presetValidator.errors.length === 0;
        });
        validateProperty(settings, 'customThemes', isArray, DEFAULT_SETTINGS);
        validateArray(settings, 'customThemes', (custom) => {
            if (!(isPlainObject(custom) && hasRequiredProperties(custom, ['url', 'theme']))) {
                return false;
            }
            const presetValidator = createValidator();
            presetValidator.validateProperty(custom, 'url', isNonEmptyArrayOfNonEmptyStrings, custom);
            presetValidator.validateProperty(custom, 'theme', isValidPresetTheme, custom);
            return presetValidator.errors.length === 0;
        });
        validateProperty(settings, 'enabledFor', isArray, DEFAULT_SETTINGS);
        validateArray(settings, 'enabledFor', isNonEmptyString);
        validateProperty(settings, 'disabledFor', isArray, DEFAULT_SETTINGS);
        validateArray(settings, 'disabledFor', isNonEmptyString);
        validateProperty(settings, 'enabledByDefault', isBoolean, DEFAULT_SETTINGS);
        validateProperty(settings, 'changeBrowserTheme', isBoolean, DEFAULT_SETTINGS);
        validateProperty(settings, 'syncSettings', isBoolean, DEFAULT_SETTINGS);
        validateProperty(settings, 'syncSitesFixes', isBoolean, DEFAULT_SETTINGS);
        validateProperty(settings, 'automation', (automation) => {
            if (!isPlainObject(automation)) {
                return false;
            }
            const automationValidator = createValidator();
            automationValidator.validateProperty(automation, 'enabled', isBoolean, automation);
            automationValidator.validateProperty(automation, 'mode', isOneOf(AutomationMode.SYSTEM, AutomationMode.TIME, AutomationMode.LOCATION, AutomationMode.NONE), automation);
            automationValidator.validateProperty(automation, 'behavior', isOneOf('OnOff', 'Scheme'), automation);
            return automationValidator.errors.length === 0;
        }, DEFAULT_SETTINGS);
        validateProperty(settings, AutomationMode.TIME, (time) => {
            if (!isPlainObject(time)) {
                return false;
            }
            const timeValidator = createValidator();
            timeValidator.validateProperty(time, 'activation', isTime, time);
            timeValidator.validateProperty(time, 'deactivation', isTime, time);
            return timeValidator.errors.length === 0;
        }, DEFAULT_SETTINGS);
        validateProperty(settings, AutomationMode.LOCATION, (location) => {
            if (!isPlainObject(location)) {
                return false;
            }
            const locValidator = createValidator();
            const isValidLoc = (x) => x === null || isNumber(x);
            locValidator.validateProperty(location, 'latitude', isValidLoc, location);
            locValidator.validateProperty(location, 'longitude', isValidLoc, location);
            return locValidator.errors.length === 0;
        }, DEFAULT_SETTINGS);
        validateProperty(settings, 'previewNewDesign', isBoolean, DEFAULT_SETTINGS);
        validateProperty(settings, 'previewNewestDesign', isBoolean, DEFAULT_SETTINGS);
        validateProperty(settings, 'enableForPDF', isBoolean, DEFAULT_SETTINGS);
        validateProperty(settings, 'enableForProtectedPages', isBoolean, DEFAULT_SETTINGS);
        validateProperty(settings, 'enableContextMenus', isBoolean, DEFAULT_SETTINGS);
        validateProperty(settings, 'detectDarkTheme', isBoolean, DEFAULT_SETTINGS);
        return { errors, settings };
    }
    function validateTheme(theme) {
        if (!isPlainObject(theme)) {
            return { errors: ['Theme is not a plain object'], theme: DEFAULT_THEME };
        }
        const { validateProperty, errors } = createValidator();
        validateProperty(theme, 'mode', isOneOf(0, 1), DEFAULT_THEME);
        validateProperty(theme, 'brightness', isNumberBetween(0, 200), DEFAULT_THEME);
        validateProperty(theme, 'contrast', isNumberBetween(0, 200), DEFAULT_THEME);
        validateProperty(theme, 'grayscale', isNumberBetween(0, 100), DEFAULT_THEME);
        validateProperty(theme, 'sepia', isNumberBetween(0, 100), DEFAULT_THEME);
        validateProperty(theme, 'useFont', isBoolean, DEFAULT_THEME);
        validateProperty(theme, 'fontFamily', isNonEmptyString, DEFAULT_THEME);
        validateProperty(theme, 'textStroke', isNumberBetween(0, 1), DEFAULT_THEME);
        validateProperty(theme, 'engine', isOneOf('dynamicTheme', 'staticTheme', 'cssFilter', 'svgFilter'), DEFAULT_THEME);
        validateProperty(theme, 'stylesheet', isString, DEFAULT_THEME);
        validateProperty(theme, 'darkSchemeBackgroundColor', isRegExpMatch(/^#[0-9a-f]{6}$/i), DEFAULT_THEME);
        validateProperty(theme, 'darkSchemeTextColor', isRegExpMatch(/^#[0-9a-f]{6}$/i), DEFAULT_THEME);
        validateProperty(theme, 'lightSchemeBackgroundColor', isRegExpMatch(/^#[0-9a-f]{6}$/i), DEFAULT_THEME);
        validateProperty(theme, 'lightSchemeTextColor', isRegExpMatch(/^#[0-9a-f]{6}$/i), DEFAULT_THEME);
        validateProperty(theme, 'scrollbarColor', (x) => x === '' || isRegExpMatch(/^(auto)|(#[0-9a-f]{6})$/i)(x), DEFAULT_THEME);
        validateProperty(theme, 'selectionColor', isRegExpMatch(/^(auto)|(#[0-9a-f]{6})$/i), DEFAULT_THEME);
        validateProperty(theme, 'styleSystemControls', isBoolean, DEFAULT_THEME);
        validateProperty(theme, 'lightColorScheme', isNonEmptyString, DEFAULT_THEME);
        validateProperty(theme, 'darkColorScheme', isNonEmptyString, DEFAULT_THEME);
        validateProperty(theme, 'immediateModify', isBoolean, DEFAULT_THEME);
        return { errors, theme };
    }

    function sendLog(level, ...args) {
        {
            return;
        }
    }

    function logInfo(...args) {
        {
            console.info(...args);
            sendLog('info', args);
        }
    }
    function logWarn(...args) {
        {
            console.warn(...args);
            sendLog('warn', args);
        }
    }
    function logAssert(...args) {
        {
            console.assert(...args);
            sendLog('assert', ...args);
        }
    }
    function ASSERT(description, condition) {
        if ((typeof condition === 'function' && !condition()) || !condition) {
            logAssert(description);
        }
    }

    const SAVE_TIMEOUT = 1000;
    class UserStorage {
        static loadBarrier;
        static saveStorageBarrier;
        static settings;
        static async loadSettings() {
            if (!UserStorage.settings) {
                UserStorage.settings = await UserStorage.loadSettingsFromStorage();
            }
        }
        static fillDefaults(settings) {
            settings.theme = { ...DEFAULT_THEME, ...settings.theme };
            settings.time = { ...DEFAULT_SETTINGS.time, ...settings.time };
            settings.presets.forEach((preset) => {
                preset.theme = { ...DEFAULT_THEME, ...preset.theme };
            });
            settings.customThemes.forEach((site) => {
                site.theme = { ...DEFAULT_THEME, ...site.theme };
            });
            if (settings.customThemes.length === 0) {
                settings.customThemes = DEFAULT_SETTINGS.customThemes;
            }
        }
        // migrateAutomationSettings migrates old automation settings to the new interface.
        // It will move settings.automation & settings.automationBehavior into,
        // settings.automation = { enabled, mode, behavior }.
        // Remove this over two years(mid-2024).
        // This won't always work, because browsers can decide to instead use the default settings
        // when they notice a different type being requested for automation, in that case it's a data-loss
        // and not something we can encounter for, except for doing always two extra requests to explicitly
        // check for this case which is inefficient usage of requesting storage.
        static migrateAutomationSettings(settings) {
            if (typeof settings.automation === 'string') {
                const automationMode = settings.automation;
                const automationBehavior = settings.automationBehaviour;
                if (settings.automation === '') {
                    settings.automation = {
                        enabled: false,
                        mode: automationMode,
                        behavior: automationBehavior,
                    };
                }
                else {
                    settings.automation = {
                        enabled: true,
                        mode: automationMode,
                        behavior: automationBehavior,
                    };
                }
                delete settings.automationBehaviour;
            }
        }
        static migrateSiteListsV2(deprecated) {
            const settings = {};
            settings.enabledByDefault = !deprecated.applyToListedOnly;
            if (settings.enabledByDefault) {
                settings.disabledFor = deprecated.siteList ?? [];
                settings.enabledFor = deprecated.siteListEnabled ?? [];
            }
            else {
                settings.disabledFor = [];
                settings.enabledFor = deprecated.siteList ?? [];
            }
            return settings;
        }
        static migrateBuiltInSVGFilterToCSSFilter(settings) {
            settings?.customThemes?.forEach((c) => {
                if (c?.theme?.engine === ThemeEngine.svgFilter &&
                    (c.builtIn || c.url?.includes('docs.google.com'))) {
                    c.theme.engine = ThemeEngine.cssFilter;
                }
            });
        }
        static async loadSettingsFromStorage() {
            if (UserStorage.loadBarrier) {
                return await UserStorage.loadBarrier.entry();
            }
            UserStorage.loadBarrier = new PromiseBarrier();
            let local = await readLocalStorage(DEFAULT_SETTINGS);
            if (local.schemeVersion < 2) {
                const sync = await readSyncStorage({ schemeVersion: 0 });
                if (!sync || sync.schemeVersion < 2) {
                    const deprecatedDefaults = {
                        siteList: [],
                        siteListEnabled: [],
                        applyToListedOnly: false,
                    };
                    const localDeprecated = await readLocalStorage(deprecatedDefaults);
                    const localTransformed = UserStorage.migrateSiteListsV2(localDeprecated);
                    await writeLocalStorage({ schemeVersion: 2, ...localTransformed });
                    await removeLocalStorage(Object.keys(deprecatedDefaults));
                    const syncDeprecated = await readSyncStorage(deprecatedDefaults);
                    const syncTransformed = UserStorage.migrateSiteListsV2(syncDeprecated);
                    await writeSyncStorage({ schemeVersion: 2, ...syncTransformed });
                    await removeSyncStorage(Object.keys(deprecatedDefaults));
                    local = await readLocalStorage(DEFAULT_SETTINGS);
                }
            }
            const { errors: localCfgErrors } = validateSettings(local);
            localCfgErrors.forEach((err) => logWarn(err));
            if (local.syncSettings == null) {
                local.syncSettings = DEFAULT_SETTINGS.syncSettings;
            }
            if (!local.syncSettings) {
                UserStorage.migrateAutomationSettings(local);
                UserStorage.migrateBuiltInSVGFilterToCSSFilter(local);
                UserStorage.fillDefaults(local);
                UserStorage.loadBarrier.resolve(local);
                return local;
            }
            const $sync = await readSyncStorage(DEFAULT_SETTINGS);
            if (!$sync) {
                logWarn('Sync settings are missing');
                local.syncSettings = false;
                UserStorage.set({ syncSettings: false });
                UserStorage.saveSyncSetting(false);
                UserStorage.loadBarrier.resolve(local);
                return local;
            }
            const { errors: syncCfgErrors } = validateSettings($sync);
            syncCfgErrors.forEach((err) => logWarn(err));
            UserStorage.migrateAutomationSettings($sync);
            UserStorage.migrateBuiltInSVGFilterToCSSFilter($sync);
            UserStorage.fillDefaults($sync);
            UserStorage.loadBarrier.resolve($sync);
            return $sync;
        }
        static async saveSettings() {
            if (!UserStorage.settings) {
                // This path is never taken because Extension always calls UserStorage.loadSettings()
                // before calling UserStorage.saveSettings().
                logWarn('Could not save settings into storage because the settings are missing.');
                return;
            }
            await UserStorage.saveSettingsIntoStorage();
        }
        static async saveSyncSetting(sync) {
            const obj = { syncSettings: sync };
            await writeLocalStorage(obj);
            try {
                await writeSyncStorage(obj);
            }
            catch (err) {
                logWarn('Settings synchronization was disabled due to error:', chrome.runtime.lastError);
                UserStorage.set({ syncSettings: false });
            }
        }
        static saveSettingsIntoStorage = debounce(SAVE_TIMEOUT, async () => {
            if (UserStorage.saveStorageBarrier) {
                await UserStorage.saveStorageBarrier.entry();
                return;
            }
            UserStorage.saveStorageBarrier = new PromiseBarrier();
            const settings = UserStorage.settings;
            if (settings.syncSettings) {
                try {
                    await writeSyncStorage(settings);
                }
                catch (err) {
                    logWarn('Settings synchronization was disabled due to error:', chrome.runtime.lastError);
                    UserStorage.set({ syncSettings: false });
                    await UserStorage.saveSyncSetting(false);
                    await writeLocalStorage(settings);
                }
            }
            else {
                await writeLocalStorage(settings);
            }
            UserStorage.saveStorageBarrier.resolve();
            UserStorage.saveStorageBarrier = null;
        });
        static set($settings) {
            if (!UserStorage.settings) {
                // This path is never taken because Extension always calls UserStorage.loadSettings()
                // before calling UserStorage.set().
                logWarn('Could not modify settings because the settings are missing.');
                return;
            }
            const filterSiteList = (siteList) => {
                if (!Array.isArray(siteList)) {
                    const list = [];
                    for (const key in siteList) {
                        const index = Number(key);
                        if (!isNaN(index)) {
                            list[index] = siteList[key];
                        }
                    }
                    siteList = list;
                }
                return siteList.filter((pattern) => {
                    let isOK = false;
                    try {
                        isURLMatched('https://google.com/', pattern);
                        isURLMatched('[::1]:1337', pattern);
                        isOK = true;
                    }
                    catch (err) {
                        logWarn(`Pattern "${pattern}" excluded`);
                    }
                    return isOK && pattern !== '/';
                });
            };
            const { enabledFor, disabledFor } = $settings;
            const updatedSettings = { ...UserStorage.settings, ...$settings };
            if (enabledFor) {
                updatedSettings.enabledFor = filterSiteList(enabledFor);
            }
            if (disabledFor) {
                updatedSettings.disabledFor = filterSiteList(disabledFor);
            }
            UserStorage.settings = updatedSettings;
        }
    }

    async function getOKResponse(url, mimeType, origin) {
        const credentials = origin && url.startsWith(`${origin}/`) ? undefined : 'omit';
        const response = await fetch(url, {
            cache: 'force-cache',
            credentials,
            referrer: origin,
        });
        if (mimeType && !(response.headers.get('Content-Type') === mimeType || response.headers.get('Content-Type').startsWith(`${mimeType};`))) {
            throw new Error(`Mime type mismatch when loading ${url}`);
        }
        if (!response.ok) {
            throw new Error(`Unable to load ${url} ${response.status} ${response.statusText}`);
        }
        return response;
    }
    async function loadAsDataURL(url, mimeType) {
        const response = await getOKResponse(url, mimeType);
        return await readResponseAsDataURL(response);
    }
    async function readResponseAsDataURL(response) {
        const blob = await response.blob();
        const dataURL = await (new Promise((resolve) => {
            const reader = new FileReader();
            reader.onloadend = () => resolve(reader.result);
            reader.readAsDataURL(blob);
        }));
        return dataURL;
    }
    async function loadAsText(url, mimeType, origin) {
        const response = await getOKResponse(url, mimeType, origin);
        return await response.text();
    }

    async function readText(params) {
        return new Promise((resolve, reject) => {
            if (isXMLHttpRequestSupported) {
                // Use XMLHttpRequest if it is available
                const request = new XMLHttpRequest();
                request.overrideMimeType('text/plain');
                request.open('GET', params.url, true);
                request.onload = () => {
                    if (request.status >= 200 && request.status < 300) {
                        resolve(request.responseText);
                    }
                    else {
                        reject(new Error(`${request.status}: ${request.statusText}`));
                    }
                };
                request.onerror = () => reject(new Error(`${request.status}: ${request.statusText}`));
                if (params.timeout) {
                    request.timeout = params.timeout;
                    request.ontimeout = () => reject(new Error('File loading stopped due to timeout'));
                }
                request.send();
            }
            else if (isFetchSupported) {
                // XMLHttpRequest is not available in Service Worker contexts like
                // Manifest V3 background context
                let abortController;
                let signal;
                let timedOut = false;
                if (params.timeout) {
                    abortController = new AbortController();
                    signal = abortController.signal;
                    setTimeout(() => {
                        abortController.abort();
                        timedOut = true;
                    }, params.timeout);
                }
                fetch(params.url, { signal })
                    .then((response) => {
                    if (response.status >= 200 && (response.status < 300)) {
                        resolve(response.text());
                    }
                    else {
                        reject(new Error(`${response.status}: ${response.statusText}`));
                    }
                }).catch((error) => {
                    if (timedOut) {
                        reject(new Error('File loading stopped due to timeout'));
                    }
                    else {
                        reject(error);
                    }
                });
            }
            else {
                reject(new Error(`Neither XMLHttpRequest nor Fetch API are accessible!`));
            }
        });
    }
    class LimitedCacheStorage {
        // TODO: remove type cast after dependency update
        static QUOTA_BYTES = ((navigator.deviceMemory) || 4) * 16 * 1024 * 1024;
        static TTL = getDuration({ minutes: 10 });
        static ALARM_NAME = 'network';
        bytesInUse = 0;
        records = new Map();
        static alarmIsActive = false;
        constructor() {
            chrome.alarms.onAlarm.addListener(async (alarm) => {
                if (alarm.name === LimitedCacheStorage.ALARM_NAME) {
                    // We schedule only one-time alarms, so once it goes off,
                    // there are no more alarms scheduled.
                    LimitedCacheStorage.alarmIsActive = false;
                    this.removeExpiredRecords();
                }
            });
        }
        static ensureAlarmIsScheduled() {
            if (!this.alarmIsActive) {
                chrome.alarms.create(LimitedCacheStorage.ALARM_NAME, { delayInMinutes: 1 });
                this.alarmIsActive = true;
            }
        }
        has(url) {
            return this.records.has(url);
        }
        get(url) {
            if (this.records.has(url)) {
                const record = this.records.get(url);
                record.expires = Date.now() + LimitedCacheStorage.TTL;
                this.records.delete(url);
                this.records.set(url, record);
                return record.value;
            }
            return null;
        }
        set(url, value) {
            LimitedCacheStorage.ensureAlarmIsScheduled();
            const size = getStringSize(value);
            if (size > LimitedCacheStorage.QUOTA_BYTES) {
                return;
            }
            for (const [url, record] of this.records) {
                if (this.bytesInUse + size > LimitedCacheStorage.QUOTA_BYTES) {
                    this.records.delete(url);
                    this.bytesInUse -= record.size;
                }
                else {
                    break;
                }
            }
            if (this.records.size === 0) {
                this.bytesInUse = 0;
            }
            const expires = Date.now() + LimitedCacheStorage.TTL;
            this.records.set(url, { url, value, size, expires });
            this.bytesInUse += size;
        }
        removeExpiredRecords() {
            const now = Date.now();
            for (const [url, record] of this.records) {
                if (record.expires < now) {
                    this.records.delete(url);
                    this.bytesInUse -= record.size;
                }
                else {
                    break;
                }
            }
            if (this.records.size === 0) {
                this.bytesInUse = 0;
            }
            else {
                LimitedCacheStorage.ensureAlarmIsScheduled();
            }
        }
    }
    function createLimiter() {
        const loadingUrls = new Set();
        const awaitingUrls = new Map();
        function loading(url) {
            const result = loadingUrls.has(url);
            loadingUrls.add(url);
            return result;
        }
        async function wait(url) {
            return new Promise((resolve) => {
                if (!awaitingUrls.has(url)) {
                    awaitingUrls.set(url, new Set());
                }
                awaitingUrls.get(url)?.add(resolve);
            });
        }
        async function loaded(url, data) {
            loadingUrls.delete(url);
            if (awaitingUrls.has(url)) {
                const response = { data };
                awaitingUrls.get(url).forEach((callback) => callback(response));
                awaitingUrls.delete(url);
            }
        }
        async function failed(url, error) {
            loadingUrls.delete(url);
            if (awaitingUrls.has(url)) {
                const response = { error };
                awaitingUrls.get(url).forEach((callback) => callback(response));
                awaitingUrls.delete(url);
            }
        }
        return { loading, wait, loaded, failed };
    }
    function createFileLoader() {
        const caches = {
            'data-url': new LimitedCacheStorage(),
            'text': new LimitedCacheStorage(),
        };
        const loaders = {
            'data-url': loadAsDataURL,
            'text': loadAsText,
        };
        const limiters = {
            'data-url': createLimiter(),
            'text': createLimiter(),
        };
        async function get({ url, responseType, mimeType, origin }) {
            const cache = caches[responseType];
            const load = loaders[responseType];
            const limiter = limiters[responseType];
            if (cache.has(url)) {
                const data = cache.get(url);
                return { data };
            }
            if (limiter.loading(url)) {
                return limiter.wait(url);
            }
            try {
                const data = await load(url, mimeType, origin);
                cache.set(url, data);
                limiter.loaded(url, data);
                return { data };
            }
            catch (error) {
                limiter.failed(url, error);
                return { error };
            }
        }
        return { get };
    }

    const CONFIG_URLs = {
        darkSites: {
            remote: `${CONFIG_URL_BASE}/dark-sites.config`,
            local: '../config/dark-sites.config',
        },
        dynamicThemeFixes: {
            remote: `${CONFIG_URL_BASE}/dynamic-theme-fixes.config`,
            local: '../config/dynamic-theme-fixes.config',
        },
        inversionFixes: {
            remote: `${CONFIG_URL_BASE}/inversion-fixes.config`,
            local: '../config/inversion-fixes.config',
        },
        staticThemes: {
            remote: `${CONFIG_URL_BASE}/static-themes.config`,
            local: '../config/static-themes.config',
        },
        colorSchemes: {
            remote: `${CONFIG_URL_BASE}/color-schemes.drconf`,
            local: '../config/color-schemes.drconf',
        },
        detectorHints: {
            remote: `${CONFIG_URL_BASE}/detector-hints.config`,
            local: '../config/detector-hints.config',
        },
    };
    const REMOTE_TIMEOUT_MS = getDuration({ seconds: 10 });
    class ConfigManager {
        static DARK_SITES_INDEX;
        static DETECTOR_HINTS_INDEX;
        static DETECTOR_HINTS_RAW;
        static DYNAMIC_THEME_FIXES_INDEX;
        static DYNAMIC_THEME_FIXES_RAW;
        static INVERSION_FIXES_INDEX;
        static INVERSION_FIXES_RAW;
        static STATIC_THEMES_INDEX;
        static STATIC_THEMES_RAW;
        static COLOR_SCHEMES_RAW;
        static raw = {
            darkSites: null,
            detectorHints: null,
            dynamicThemeFixes: null,
            inversionFixes: null,
            staticThemes: null,
            colorSchemes: null,
        };
        static overrides = {
            darkSites: null,
            detectorHints: null,
            dynamicThemeFixes: null,
            inversionFixes: null,
            staticThemes: null,
        };
        static async loadConfig({ name, local, localURL, remoteURL, }) {
            let $config;
            const loadLocal = async () => await readText({ url: localURL });
            if (local) {
                $config = await loadLocal();
            }
            else {
                try {
                    $config = await readText({
                        url: `${remoteURL}?nocache=${Date.now()}`,
                        timeout: REMOTE_TIMEOUT_MS,
                    });
                }
                catch (err) {
                    console.error(`${name} remote load error`, err);
                    $config = await loadLocal();
                }
            }
            return $config;
        }
        static async loadColorSchemes({ local }) {
            const $config = await ConfigManager.loadConfig({
                name: 'Color Schemes',
                local,
                localURL: CONFIG_URLs.colorSchemes.local,
                remoteURL: CONFIG_URLs.colorSchemes.remote,
            });
            ConfigManager.raw.colorSchemes = $config;
            ConfigManager.handleColorSchemes();
        }
        static async loadDarkSites({ local }) {
            const sites = await ConfigManager.loadConfig({
                name: 'Dark Sites',
                local,
                localURL: CONFIG_URLs.darkSites.local,
                remoteURL: CONFIG_URLs.darkSites.remote,
            });
            ConfigManager.raw.darkSites = sites;
            ConfigManager.handleDarkSites();
        }
        static async loadDetectorHints({ local }) {
            const $config = await ConfigManager.loadConfig({
                name: 'Detector Hints',
                local,
                localURL: CONFIG_URLs.detectorHints.local,
                remoteURL: CONFIG_URLs.detectorHints.remote,
            });
            ConfigManager.raw.detectorHints = $config;
            ConfigManager.handleDetectorHints();
        }
        static async loadDynamicThemeFixes({ local }) {
            const fixes = await ConfigManager.loadConfig({
                name: 'Dynamic Theme Fixes',
                local,
                localURL: CONFIG_URLs.dynamicThemeFixes.local,
                remoteURL: CONFIG_URLs.dynamicThemeFixes.remote,
            });
            ConfigManager.raw.dynamicThemeFixes = fixes;
            ConfigManager.handleDynamicThemeFixes();
        }
        static async loadInversionFixes({ local }) {
            const fixes = await ConfigManager.loadConfig({
                name: 'Inversion Fixes',
                local,
                localURL: CONFIG_URLs.inversionFixes.local,
                remoteURL: CONFIG_URLs.inversionFixes.remote,
            });
            ConfigManager.raw.inversionFixes = fixes;
            ConfigManager.handleInversionFixes();
        }
        static async loadStaticThemes({ local }) {
            const themes = await ConfigManager.loadConfig({
                name: 'Static Themes',
                local,
                localURL: CONFIG_URLs.staticThemes.local,
                remoteURL: CONFIG_URLs.staticThemes.remote,
            });
            ConfigManager.raw.staticThemes = themes;
            ConfigManager.handleStaticThemes();
        }
        static async load(config) {
            if (!config) {
                await UserStorage.loadSettings();
                config = {
                    local: !UserStorage.settings.syncSitesFixes,
                };
            }
            await Promise.all([
                ConfigManager.loadColorSchemes(config),
                ConfigManager.loadDarkSites(config),
                ConfigManager.loadDetectorHints(config),
                ConfigManager.loadDynamicThemeFixes(config),
                ConfigManager.loadInversionFixes(config),
                ConfigManager.loadStaticThemes(config),
            ]).catch((err) => console.error('Fatality', err));
        }
        static handleColorSchemes() {
            const $config = ConfigManager.raw.colorSchemes;
            const { result, error } = parseColorSchemeConfig($config || '');
            if (error) {
                logWarn(`Color Schemes parse error, defaulting to fallback. ${error}.`);
                ConfigManager.COLOR_SCHEMES_RAW = DEFAULT_COLORSCHEME;
                return;
            }
            ConfigManager.COLOR_SCHEMES_RAW = result;
        }
        static handleDarkSites() {
            const $sites = ConfigManager.raw.darkSites;
            const templates = parseArray($sites);
            ConfigManager.DARK_SITES_INDEX = indexURLTemplateList(templates);
        }
        static handleDetectorHints() {
            const $hints = ConfigManager.raw.detectorHints || '';
            ConfigManager.DETECTOR_HINTS_INDEX = indexSitesFixesConfig($hints);
            ConfigManager.DETECTOR_HINTS_RAW = $hints;
        }
        static handleDynamicThemeFixes() {
            const $fixes = ConfigManager.overrides.dynamicThemeFixes || ConfigManager.raw.dynamicThemeFixes || '';
            ConfigManager.DYNAMIC_THEME_FIXES_INDEX = indexSitesFixesConfig($fixes);
            ConfigManager.DYNAMIC_THEME_FIXES_RAW = $fixes;
        }
        static handleInversionFixes() {
            const $fixes = ConfigManager.overrides.inversionFixes || ConfigManager.raw.inversionFixes || '';
            ConfigManager.INVERSION_FIXES_INDEX = indexSitesFixesConfig($fixes);
            ConfigManager.INVERSION_FIXES_RAW = $fixes;
        }
        static handleStaticThemes() {
            const $themes = ConfigManager.overrides.staticThemes || ConfigManager.raw.staticThemes || '';
            ConfigManager.STATIC_THEMES_INDEX = indexSitesFixesConfig($themes);
            ConfigManager.STATIC_THEMES_RAW = $themes;
        }
        static isURLInDarkList(url) {
            if (!ConfigManager.DARK_SITES_INDEX) {
                return false;
            }
            return isURLInIndexedList(url, ConfigManager.DARK_SITES_INDEX);
        }
    }

    class PersistentStorageWrapper {
        // Cache information within background context for future use without waiting.
        cache = {};
        async get(key) {
            if (key in this.cache) {
                return this.cache[key];
            }
            return new Promise((resolve) => {
                chrome.storage.local.get(key, (result) => {
                    // If cache received a new value (from call to set())
                    // before we retrieved the old value from storage,
                    // return the new value.
                    if (key in this.cache) {
                        logInfo(`Key ${key} was written to during read operation.`);
                        resolve(this.cache[key]);
                        return;
                    }
                    if (chrome.runtime.lastError) {
                        console.error('Failed to query DevTools data', chrome.runtime.lastError);
                        resolve(null);
                        return;
                    }
                    this.cache[key] = result[key];
                    resolve(result[key]);
                });
            });
        }
        async set(key, value) {
            this.cache[key] = value;
            return new Promise((resolve) => chrome.storage.local.set({ [key]: value }, () => {
                if (chrome.runtime.lastError) {
                    console.error('Failed to write DevTools data', chrome.runtime.lastError);
                }
                else {
                    resolve();
                }
            }));
        }
        async remove(key) {
            this.cache[key] = null;
            return new Promise((resolve) => chrome.storage.local.remove(key, () => {
                if (chrome.runtime.lastError) {
                    console.error('Failed to delete DevTools data', chrome.runtime.lastError);
                }
                else {
                    resolve();
                }
            }));
        }
        async has(key) {
            return Boolean(await this.get(key));
        }
    }
    class TempStorage {
        map = new Map();
        async get(key) {
            return this.map.get(key) || null;
        }
        set(key, value) {
            this.map.set(key, value);
        }
        remove(key) {
            this.map.delete(key);
        }
        async has(key) {
            return this.map.has(key);
        }
    }
    class DevTools {
        static onChange;
        static store;
        static init(onChange) {
            // Firefox don't seem to like using storage.local to store big data on the background-extension.
            // Disabling it for now and defaulting back to localStorage.
            if (typeof chrome.storage.local !== 'undefined' && chrome.storage.local !== null) {
                DevTools.store = new PersistentStorageWrapper();
            }
            else {
                DevTools.store = new TempStorage();
            }
            DevTools.loadConfigOverrides();
            DevTools.onChange = onChange;
        }
        static KEY_DYNAMIC = 'dev_dynamic_theme_fixes';
        static KEY_FILTER = 'dev_inversion_fixes';
        static KEY_STATIC = 'dev_static_themes';
        static async loadConfigOverrides() {
            const [dynamicThemeFixes, inversionFixes, staticThemes,] = await Promise.all([
                DevTools.getSavedDynamicThemeFixes(),
                DevTools.getSavedInversionFixes(),
                DevTools.getSavedStaticThemes(),
            ]);
            ConfigManager.overrides.dynamicThemeFixes = dynamicThemeFixes || null;
            ConfigManager.overrides.inversionFixes = inversionFixes || null;
            ConfigManager.overrides.staticThemes = staticThemes || null;
        }
        static async getSavedDynamicThemeFixes() {
            return DevTools.store.get(DevTools.KEY_DYNAMIC);
        }
        static saveDynamicThemeFixes(text) {
            DevTools.store.set(DevTools.KEY_DYNAMIC, text);
        }
        static async getDynamicThemeFixesText() {
            let rawFixes = await DevTools.getSavedDynamicThemeFixes();
            if (!rawFixes) {
                await ConfigManager.load();
                rawFixes = ConfigManager.DYNAMIC_THEME_FIXES_RAW || '';
            }
            const fixes = parseDynamicThemeFixes(rawFixes);
            return formatDynamicThemeFixes(fixes);
        }
        static resetDynamicThemeFixes() {
            DevTools.store.remove(DevTools.KEY_DYNAMIC);
            ConfigManager.overrides.dynamicThemeFixes = null;
            ConfigManager.handleDynamicThemeFixes();
            DevTools.onChange();
        }
        // TODO(Anton): remove any
        static applyDynamicThemeFixes(text) {
            try {
                const formatted = formatDynamicThemeFixes(parseDynamicThemeFixes(text));
                ConfigManager.overrides.dynamicThemeFixes = formatted;
                ConfigManager.handleDynamicThemeFixes();
                DevTools.saveDynamicThemeFixes(formatted);
                DevTools.onChange();
                return null;
            }
            catch (err) {
                return err;
            }
        }
        static async getSavedInversionFixes() {
            return this.store.get(DevTools.KEY_FILTER);
        }
        static saveInversionFixes(text) {
            this.store.set(DevTools.KEY_FILTER, text);
        }
        static async getInversionFixesText() {
            let rawFixes = await DevTools.getSavedInversionFixes();
            if (!rawFixes) {
                await ConfigManager.load();
                rawFixes = ConfigManager.INVERSION_FIXES_RAW || '';
            }
            const fixes = parseInversionFixes(rawFixes);
            return formatInversionFixes(fixes);
        }
        static resetInversionFixes() {
            DevTools.store.remove(DevTools.KEY_FILTER);
            ConfigManager.overrides.inversionFixes = null;
            ConfigManager.handleInversionFixes();
            DevTools.onChange();
        }
        // TODO(Anton): remove any
        static applyInversionFixes(text) {
            try {
                const formatted = formatInversionFixes(parseInversionFixes(text));
                ConfigManager.overrides.inversionFixes = formatted;
                ConfigManager.handleInversionFixes();
                DevTools.saveInversionFixes(formatted);
                DevTools.onChange();
                return null;
            }
            catch (err) {
                return err;
            }
        }
        static async getSavedStaticThemes() {
            return DevTools.store.get(DevTools.KEY_STATIC);
        }
        static saveStaticThemes(text) {
            DevTools.store.set(DevTools.KEY_STATIC, text);
        }
        static async getStaticThemesText() {
            let rawThemes = await DevTools.getSavedStaticThemes();
            if (!rawThemes) {
                await ConfigManager.load();
                rawThemes = ConfigManager.STATIC_THEMES_RAW || '';
            }
            const themes = parseStaticThemes(rawThemes);
            return formatStaticThemes(themes);
        }
        static resetStaticThemes() {
            DevTools.store.remove(DevTools.KEY_STATIC);
            ConfigManager.overrides.staticThemes = null;
            ConfigManager.handleStaticThemes();
            DevTools.onChange();
        }
        // TODO(Anton): remove any
        static applyStaticThemes(text) {
            try {
                const formatted = formatStaticThemes(parseStaticThemes(text));
                ConfigManager.overrides.staticThemes = formatted;
                ConfigManager.handleStaticThemes();
                DevTools.saveStaticThemes(formatted);
                DevTools.onChange();
                return null;
            }
            catch (err) {
                return err;
            }
        }
    }

    class IconManager {
        static ICON_PATHS = {
            activeDark: {
                19: '../icons/dr_active_19.png',
                38: '../icons/dr_active_38.png',
            },
            activeLight: {
                19: '../icons/dr_active_light_19.png',
                38: '../icons/dr_active_light_38.png',
            },
            // Temporary disable the gray icon
            /*
            inactiveDark: {
                19: '../icons/dr_inactive_dark_19.png',
                38: '../icons/dr_inactive_dark_38.png',
            },
            inactiveLight: {
                19: '../icons/dr_inactive_light_19.png',
                38: '../icons/dr_inactive_light_38.png',
            },
            */
        };
        static iconState = {
            badgeText: '',
            active: true,
        };
        static onStartup() {
            /**
             * This empty listener invokes extension background if extension has non-default
             * icon or badge. It is empty because all icon customizations will be initiated by
             * Extension class.
             * TODO: eventually, avoid running the whole Extension class on startup.
             */
        }
        /**
         * This method registers onStartup listener only if we are in non-persistent world and
         * icon is in non-default configuration.
         */
        static handleUpdate() {
            if (IconManager.iconState.badgeText !== '' || !IconManager.iconState.active) {
                chrome.runtime.onStartup.addListener(IconManager.onStartup);
            }
            else {
                chrome.runtime.onStartup.removeListener(IconManager.onStartup);
            }
        }
        static setIcon({ isActive = this.iconState.active, colorScheme = 'dark', tabId }) {
            if (!chrome.action.setIcon) {
                // Fix for Firefox Android and Thunderbird.
                return;
            }
            if (tabId) {
                return;
            }
            this.iconState.active = isActive;
            let path = this.ICON_PATHS.activeDark;
            if (isActive) {
                // Temporary disable the gray icon
                // path = colorScheme === 'dark' ? IconManager.ICON_PATHS.activeDark : IconManager.ICON_PATHS.activeLight;
                path = IconManager.ICON_PATHS.activeDark;
            }
            else {
                // Temporary disable the gray icon
                // path = colorScheme === 'dark' ? IconManager.ICON_PATHS.inactiveDark : IconManager.ICON_PATHS.inactiveLight;
                path = IconManager.ICON_PATHS.activeLight;
            }
            // Temporary disable per-site icons
            /*
            if (tabId) {
                chrome.action.setIcon({tabId, path});
            } else {
                chrome.action.setIcon({path});
                IconManager.handleUpdate();
            }
            */
            chrome.action.setIcon({ path });
            IconManager.handleUpdate();
        }
        static showBadge(text) {
            IconManager.iconState.badgeText = text;
            chrome.action.setBadgeBackgroundColor({ color: '#e96c4c' });
            chrome.action.setBadgeText({ text });
            IconManager.handleUpdate();
        }
        static hideBadge() {
            IconManager.iconState.badgeText = '';
            chrome.action.setBadgeText({ text: '' });
            IconManager.handleUpdate();
        }
    }

    class Messenger {
        static adapter;
        static changeListenerCount;
        static init(adapter) {
            Messenger.adapter = adapter;
            Messenger.changeListenerCount = 0;
            chrome.runtime.onMessage.addListener(Messenger.messageListener);
        }
        static messageListener(message, sender, sendResponse) {
            const allowedSenderURL = [
                chrome.runtime.getURL('/ui/popup/index.html'),
                chrome.runtime.getURL('/ui/devtools/index.html'),
                chrome.runtime.getURL('/ui/options/index.html'),
                chrome.runtime.getURL('/ui/stylesheet-editor/index.html'),
            ];
            if (allowedSenderURL.includes(sender.url) || (false)) {
                Messenger.onUIMessage(message, sendResponse);
                return ([
                    MessageTypeUItoBG.GET_DATA,
                    MessageTypeUItoBG.GET_DEVTOOLS_DATA,
                ].includes(message.type));
            }
        }
        static firefoxPortListener(port) {
            ASSERT('Messenger.firefoxPortListener() is used only on Firefox', isFirefox);
            {
                return;
            }
        }
        static onUIMessage({ type, data }, sendResponse) {
            switch (type) {
                case MessageTypeUItoBG.GET_DATA:
                    Messenger.adapter.collect().then((data) => sendResponse({ data }));
                    break;
                case MessageTypeUItoBG.GET_DEVTOOLS_DATA:
                    Messenger.adapter.collectDevToolsData().then((data) => sendResponse({ data }));
                    break;
                case MessageTypeUItoBG.SUBSCRIBE_TO_CHANGES:
                    Messenger.changeListenerCount++;
                    break;
                case MessageTypeUItoBG.UNSUBSCRIBE_FROM_CHANGES:
                    Messenger.changeListenerCount--;
                    break;
                case MessageTypeUItoBG.CHANGE_SETTINGS:
                    Messenger.adapter.changeSettings(data);
                    break;
                case MessageTypeUItoBG.SET_THEME:
                    Messenger.adapter.setTheme(data);
                    break;
                case MessageTypeUItoBG.TOGGLE_ACTIVE_TAB:
                    Messenger.adapter.toggleActiveTab();
                    break;
                case MessageTypeUItoBG.MARK_NEWS_AS_READ:
                    Messenger.adapter.markNewsAsRead(data);
                    break;
                case MessageTypeUItoBG.MARK_NEWS_AS_DISPLAYED:
                    Messenger.adapter.markNewsAsDisplayed(data);
                    break;
                case MessageTypeUItoBG.LOAD_CONFIG:
                    Messenger.adapter.loadConfig(data);
                    break;
                case MessageTypeUItoBG.APPLY_DEV_DYNAMIC_THEME_FIXES: {
                    const error = Messenger.adapter.applyDevDynamicThemeFixes(data);
                    sendResponse({ error: (error ? error.message : undefined) });
                    break;
                }
                case MessageTypeUItoBG.RESET_DEV_DYNAMIC_THEME_FIXES:
                    Messenger.adapter.resetDevDynamicThemeFixes();
                    break;
                case MessageTypeUItoBG.APPLY_DEV_INVERSION_FIXES: {
                    const error = Messenger.adapter.applyDevInversionFixes(data);
                    sendResponse({ error: (error ? error.message : undefined) });
                    break;
                }
                case MessageTypeUItoBG.RESET_DEV_INVERSION_FIXES:
                    Messenger.adapter.resetDevInversionFixes();
                    break;
                case MessageTypeUItoBG.APPLY_DEV_STATIC_THEMES: {
                    const error = Messenger.adapter.applyDevStaticThemes(data);
                    sendResponse({ error: error ? error.message : undefined });
                    break;
                }
                case MessageTypeUItoBG.RESET_DEV_STATIC_THEMES:
                    Messenger.adapter.resetDevStaticThemes();
                    break;
                case MessageTypeUItoBG.START_ACTIVATION:
                    Messenger.adapter.startActivation(data.email, data.key);
                    break;
                case MessageTypeUItoBG.RESET_ACTIVATION:
                    Messenger.adapter.resetActivation();
                    break;
                case MessageTypeUItoBG.HIDE_HIGHLIGHTS:
                    Messenger.adapter.hideHighlights(data);
                    break;
            }
        }
        static reportChanges(data) {
            if (Messenger.changeListenerCount > 0) {
                chrome.runtime.sendMessage({
                    type: MessageTypeBGtoUI.CHANGES,
                    data,
                });
            }
        }
    }

    class Newsmaker {
        static UPDATE_INTERVAL = getDurationInMinutes({ hours: 4 });
        static ALARM_NAME = 'newsmaker';
        static LOCAL_STORAGE_KEY = 'Newsmaker-state';
        static initialized;
        static stateManager;
        static latest;
        static latestTimestamp;
        static init() {
            if (Newsmaker.initialized) {
                // This path is never taken since Extension.constructor() ever creates one instance.
                logWarn('Attempting to re-initialize Newsmaker. Doing nothing.');
                return;
            }
            Newsmaker.initialized = true;
            Newsmaker.stateManager = new StateManager(Newsmaker.LOCAL_STORAGE_KEY, this, { latest: [], latestTimestamp: null }, logWarn);
            Newsmaker.latest = [];
            Newsmaker.latestTimestamp = null;
        }
        static onUpdate() {
            Newsmaker.init();
            const latestNews = Newsmaker.latest.length > 0 && Newsmaker.latest[0];
            if (latestNews && latestNews.badge && !latestNews.read && !latestNews.displayed) {
                IconManager.showBadge(latestNews.badge);
                return;
            }
            IconManager.hideBadge();
        }
        static async getLatest() {
            Newsmaker.init();
            await Newsmaker.stateManager.loadState();
            return Newsmaker.latest;
        }
        static alarmListener = (alarm) => {
            Newsmaker.init();
            if (alarm.name === Newsmaker.ALARM_NAME) {
                Newsmaker.updateNews();
            }
        };
        static subscribe() {
            Newsmaker.init();
            if ((Newsmaker.latestTimestamp === null) || (Newsmaker.latestTimestamp + Newsmaker.UPDATE_INTERVAL < Date.now())) {
                Newsmaker.updateNews();
            }
            chrome.alarms.onAlarm.addListener(Newsmaker.alarmListener);
            chrome.alarms.create(Newsmaker.ALARM_NAME, { periodInMinutes: Newsmaker.UPDATE_INTERVAL });
        }
        static unSubscribe() {
            // No need to call Newsmaker.init()
            chrome.alarms.onAlarm.removeListener(Newsmaker.alarmListener);
            chrome.alarms.clear(Newsmaker.ALARM_NAME);
        }
        static async updateNews() {
            Newsmaker.init();
            const news = await Newsmaker.getNews();
            if (Array.isArray(news)) {
                Newsmaker.latest = news;
                Newsmaker.latestTimestamp = Date.now();
                Newsmaker.onUpdate();
                await Newsmaker.stateManager.saveState();
            }
        }
        static async getReadNews() {
            Newsmaker.init();
            const [sync, local,] = await Promise.all([
                readSyncStorage({ readNews: [] }),
                readLocalStorage({ readNews: [] }),
            ]);
            return Array.from(new Set([
                ...sync ? sync.readNews : [],
                ...local ? local.readNews : [],
            ]));
        }
        static async getDisplayedNews() {
            Newsmaker.init();
            const [sync, local,] = await Promise.all([
                readSyncStorage({ displayedNews: [] }),
                readLocalStorage({ displayedNews: [] }),
            ]);
            return Array.from(new Set([
                ...sync ? sync.displayedNews : [],
                ...local ? local.displayedNews : [],
            ]));
        }
        static async getNews() {
            Newsmaker.init();
            try {
                const response = await fetch(NEWS_URL, { cache: 'no-cache' });
                const $news = await response.json();
                const readNews = await Newsmaker.getReadNews();
                const displayedNews = await Newsmaker.getDisplayedNews();
                const news = $news.map((n) => {
                    const url = getBlogPostURL(n.id);
                    const read = Newsmaker.wasRead(n.id, readNews);
                    const displayed = Newsmaker.wasDisplayed(n.id, displayedNews);
                    return { ...n, url, read, displayed };
                });
                for (let i = 0; i < news.length; i++) {
                    const date = new Date(news[i].date);
                    if (isNaN(date.getTime())) {
                        throw new Error(`Unable to parse date ${date}`);
                    }
                }
                return news;
            }
            catch (err) {
                console.error(err);
                return null;
            }
        }
        static async markAsRead(ids) {
            Newsmaker.init();
            const readNews = await Newsmaker.getReadNews();
            const results = readNews.slice();
            let changed = false;
            ids.forEach((id) => {
                if (readNews.indexOf(id) < 0) {
                    results.push(id);
                    changed = true;
                }
            });
            if (changed) {
                Newsmaker.latest = Newsmaker.latest.map((n) => {
                    const read = Newsmaker.wasRead(n.id, results);
                    return { ...n, read };
                });
                Newsmaker.onUpdate();
                const obj = { readNews: results };
                await Promise.all([
                    writeLocalStorage(obj),
                    writeSyncStorage(obj),
                    Newsmaker.stateManager.saveState(),
                ]);
            }
        }
        static async markAsDisplayed(ids) {
            Newsmaker.init();
            const displayedNews = await Newsmaker.getDisplayedNews();
            const results = displayedNews.slice();
            let changed = false;
            ids.forEach((id) => {
                if (displayedNews.indexOf(id) < 0) {
                    results.push(id);
                    changed = true;
                }
            });
            if (changed) {
                Newsmaker.latest = Newsmaker.latest.map((n) => {
                    const displayed = Newsmaker.wasDisplayed(n.id, results);
                    return { ...n, displayed };
                });
                Newsmaker.onUpdate();
                const obj = { displayedNews: results };
                await Promise.all([
                    writeLocalStorage(obj),
                    writeSyncStorage(obj),
                    Newsmaker.stateManager.saveState(),
                ]);
            }
        }
        static wasRead(id, readNews) {
            return readNews.includes(id);
        }
        static wasDisplayed(id, displayedNews) {
            return displayedNews.includes(id);
        }
    }

    // On Thunderbird, sometimes sender.tab is undefined but accessing it will throw a very nice error.
    // On Vivaldi, sometimes sender.tab is undefined as well, but error is not very helpful.
    // On Opera, sender.tab.index === -1.
    function isPanel(sender) {
        return typeof sender === 'undefined' || typeof sender.tab === 'undefined' || (isOpera && sender.tab.index === -1);
    }

    /**
     * These states correspond to possible document states in Page Lifecycle API:
     * https://developers.google.com/web/updates/2018/07/page-lifecycle-api#developer-recommendations-for-each-state
     * Some states are not currently used (they are declared for future-proofing).
     */
    var DocumentState;
    (function (DocumentState) {
        DocumentState[DocumentState["ACTIVE"] = 0] = "ACTIVE";
        DocumentState[DocumentState["PASSIVE"] = 1] = "PASSIVE";
        DocumentState[DocumentState["HIDDEN"] = 2] = "HIDDEN";
        DocumentState[DocumentState["FROZEN"] = 3] = "FROZEN";
        DocumentState[DocumentState["TERMINATED"] = 4] = "TERMINATED";
        DocumentState[DocumentState["DISCARDED"] = 5] = "DISCARDED";
    })(DocumentState || (DocumentState = {}));
    /**
     * Note: On Chromium builds, we use documentId if it is available.
     * We avoid messaging using frameId entirely since when document is pre-rendered, it gets a temporary frameId
     * and if we attempt to send to {frameId, documentId} with old frameId, then the message will be dropped.
     */
    class TabManager {
        static tabs;
        static stateManager;
        static fileLoader = null;
        static onColorSchemeChange;
        static getTabMessage;
        static timestamp;
        static LOCAL_STORAGE_KEY = 'TabManager-state';
        static init({ getConnectionMessage, onColorSchemeChange, getTabMessage }) {
            TabManager.stateManager = new StateManager(TabManager.LOCAL_STORAGE_KEY, this, { tabs: {}, timestamp: 0 }, logWarn);
            TabManager.tabs = {};
            TabManager.onColorSchemeChange = onColorSchemeChange;
            TabManager.getTabMessage = getTabMessage;
            chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
                switch (message.type) {
                    case MessageTypeCStoBG.DOCUMENT_CONNECT: {
                        if (isPanel(sender)) {
                            sendResponse({
                                type: MessageTypeBGtoCS.UNSUPPORTED_SENDER,
                            });
                            return false;
                        }
                        TabManager.onColorSchemeMessage(message, sender);
                        const reply = (tabURL, url, isTopFrame, topFrameHasDarkTheme) => {
                            getConnectionMessage(tabURL, url, isTopFrame, topFrameHasDarkTheme).then((response) => {
                                if (!response) {
                                    return;
                                }
                                response.scriptId = message.scriptId;
                                TabManager.sendDocumentMessage(sender.tab.id, sender.documentId, response, sender.frameId);
                            });
                        };
                        if (isPanel(sender)) {
                            // NOTE: Vivaldi and Opera can show a page in a side panel,
                            // but it is not possible to handle messaging correctly (no tab ID, frame ID).
                            {
                                sendResponse('unsupportedSender');
                            }
                            return false;
                        }
                        const { frameId } = sender;
                        const isTopFrame = (frameId === 0 || message.data.isTopFrame) ;
                        const url = sender.url;
                        const tabId = sender.tab.id;
                        const scriptId = message.scriptId;
                        // Chromium 106+ may prerender frames resulting in top-level frames with chrome.runtime.MessageSender.tab.url
                        // set to chrome://newtab/ and positive chrome.runtime.MessageSender.frameId
                        const tabURL = (isTopFrame) ? url : sender.tab.url;
                        const documentId = sender.documentId ;
                        TabManager.stateManager.loadState().then(() => {
                            TabManager.addFrame(tabId, frameId, documentId, scriptId, url, isTopFrame);
                            const topFrameHasDarkTheme = isTopFrame ? false : TabManager.tabs[tabId]?.[0]?.darkThemeDetected;
                            reply(tabURL, url, isTopFrame, topFrameHasDarkTheme);
                            TabManager.stateManager.saveState();
                        });
                        break;
                    }
                    case MessageTypeCStoBG.DOCUMENT_FORGET:
                        if (!sender.tab) {
                            logWarn('Unexpected message', message, sender);
                            break;
                        }
                        ASSERT('Has a scriptId', () => Boolean(message.scriptId));
                        TabManager.removeFrame(sender.tab.id, sender.frameId);
                        break;
                    case MessageTypeCStoBG.DOCUMENT_FREEZE: {
                        TabManager.stateManager.loadState().then(() => {
                            const info = TabManager.tabs[sender.tab.id][sender.frameId];
                            info.state = DocumentState.FROZEN;
                            info.url = null;
                            TabManager.stateManager.saveState();
                        });
                        break;
                    }
                    case MessageTypeCStoBG.DOCUMENT_RESUME: {
                        TabManager.onColorSchemeMessage(message, sender);
                        const tabId = sender.tab.id;
                        const tabURL = sender.tab.url;
                        const frameId = sender.frameId;
                        const url = sender.url;
                        const documentId = sender.documentId ;
                        const isTopFrame = (frameId === 0 || message.data.isTopFrame) ;
                        TabManager.stateManager.loadState().then(() => {
                            if (TabManager.tabs[tabId][frameId].timestamp < TabManager.timestamp) {
                                const response = TabManager.getTabMessage(tabURL, url, isTopFrame);
                                response.scriptId = message.scriptId;
                                TabManager.sendDocumentMessage(tabId, documentId, response, frameId);
                            }
                            TabManager.tabs[sender.tab.id][sender.frameId] = {
                                documentId,
                                scriptId: message.scriptId,
                                url,
                                isTop: isTopFrame || undefined,
                                state: DocumentState.ACTIVE,
                                darkThemeDetected: false,
                                timestamp: TabManager.timestamp,
                            };
                            TabManager.stateManager.saveState();
                        });
                        break;
                    }
                    case MessageTypeCStoBG.DARK_THEME_DETECTED: {
                        const tabId = sender.tab.id;
                        const frames = TabManager.tabs[tabId];
                        if (!frames) {
                            break;
                        }
                        for (const entry of Object.entries(frames)) {
                            const frameId = Number(entry[0]);
                            const frame = entry[1];
                            frame.darkThemeDetected = true;
                            const { documentId, scriptId } = frame;
                            if (documentId) {
                                const message = {
                                    type: MessageTypeBGtoCS.CLEAN_UP,
                                    scriptId,
                                };
                                TabManager.sendDocumentMessage(tabId, documentId, message, frameId);
                            }
                            if (frameId === 0) {
                                IconManager.setIcon({ tabId, isActive: false });
                            }
                        }
                        break;
                    }
                    case MessageTypeCStoBG.FETCH: {
                        // Using custom response due to Chrome and Firefox incompatibility
                        // Sometimes fetch error behaves like synchronous and sends `undefined`
                        const id = message.id;
                        // We do not need to use scriptId here since every request has a unique id already
                        const sendResponse = (response) => {
                            TabManager.sendDocumentMessage(sender.tab.id, sender.documentId, { type: MessageTypeBGtoCS.FETCH_RESPONSE, id, ...response }, sender.frameId);
                        };
                        const { url, responseType, mimeType, origin } = message.data;
                        if (!TabManager.fileLoader) {
                            TabManager.fileLoader = createFileLoader();
                        }
                        TabManager.fileLoader.get({ url, responseType, mimeType, origin }).then((response) => {
                            if (response.error) {
                                const err = response.error;
                                sendResponse({ error: err?.message ?? err });
                            }
                            else {
                                sendResponse({ data: response.data });
                            }
                        });
                        return true;
                    }
                    case MessageTypeUItoBG.COLOR_SCHEME_CHANGE:
                    // fallthrough
                    case MessageTypeCStoBG.COLOR_SCHEME_CHANGE:
                        TabManager.onColorSchemeMessage(message, sender);
                        break;
                }
                return false;
            });
            chrome.tabs.onRemoved.addListener(async (tabId) => TabManager.removeFrame(tabId, 0));
        }
        static sendDocumentMessage(tabId, documentId, message, frameId) {
            if (frameId === 0) {
                const themeMessageTypes = [
                    MessageTypeBGtoCS.ADD_CSS_FILTER,
                    MessageTypeBGtoCS.ADD_DYNAMIC_THEME,
                    MessageTypeBGtoCS.ADD_STATIC_THEME,
                    MessageTypeBGtoCS.ADD_SVG_FILTER,
                ];
                if (themeMessageTypes.includes(message.type)) {
                    IconManager.setIcon({ tabId, isActive: true, colorScheme: message.data?.theme?.mode ? 'dark' : 'light' });
                }
                else if (message.type === MessageTypeBGtoCS.CLEAN_UP) {
                    const isActive = TabManager.tabs[tabId]?.[0]?.url?.startsWith('https://darkreader.org/');
                    IconManager.setIcon({ tabId, isActive });
                }
            }
            {
                // On MV3, Chromium has a bug which prevents sending messages to pre-rendered frames without specifying frameId
                // Furthermore, if we send a message addressed to a temporary frameId after the document exits prerender state,
                // the message will also fail to be delivered.
                //
                // To work around this:
                //  1. Attempt to send the message by documentId. If this fails, this means the document is in prerender state.
                //  2. Attempt to send the message by documentId and temporary frameId. If this fails, this means the document
                //     either already exited pre-rendered state or was discarded.
                //  3. Attempt to send the message by documentId (omitting the permanent frameId which is 0).If this fails, this
                //     means the document was already discarded.
                //
                // More info: https://crbug.com/1455817
                chrome.tabs.sendMessage(tabId, message, { documentId }).catch(() => chrome.tabs.sendMessage(tabId, message, { frameId, documentId }).catch(() => chrome.tabs.sendMessage(tabId, message, { documentId }).catch(() => { })));
                return;
            }
        }
        static onColorSchemeMessage(message, sender) {
            ASSERT('TabManager.onColorSchemeMessage is set', () => Boolean(TabManager.onColorSchemeChange));
            // We honor only messages which come from tab's top frame
            // because sub-frames color scheme can be overridden by style with prefers-color-scheme
            // TODO(MV3): instead of dropping these messages, consider making a query to an authoritative source
            // like offscreen document
            if (sender && sender.frameId === 0) {
                TabManager.onColorSchemeChange(message.data.isDark);
            }
        }
        static addFrame(tabId, frameId, documentId, scriptId, url, isTop) {
            let frames;
            if (TabManager.tabs[tabId]) {
                frames = TabManager.tabs[tabId];
            }
            else {
                frames = {};
                TabManager.tabs[tabId] = frames;
            }
            frames[frameId] = {
                documentId,
                scriptId,
                url,
                isTop: isTop || undefined,
                state: DocumentState.ACTIVE,
                darkThemeDetected: false,
                timestamp: TabManager.timestamp,
            };
        }
        static async removeFrame(tabId, frameId) {
            await TabManager.stateManager.loadState();
            if (frameId === 0) {
                delete TabManager.tabs[tabId];
            }
            if (TabManager.tabs[tabId] && TabManager.tabs[tabId][frameId]) {
                // We need to use delete here because Object.entries()
                // in sendMessage() would enumerate undefined as well.
                delete TabManager.tabs[tabId][frameId];
            }
            TabManager.stateManager.saveState();
        }
        static async cleanState() {
            await TabManager.stateManager.loadState();
            const actualTabs = await queryTabs({});
            const tabIds = Object.keys(TabManager.tabs).map((id) => Number(id));
            const staleTabs = new Set(tabIds);
            actualTabs.forEach((actualTab) => {
                const tabId = actualTab.id;
                if (tabId) {
                    staleTabs.delete(tabId);
                }
            });
            staleTabs.forEach((staleTabId) => {
                if (TabManager.tabs[staleTabId]) {
                    delete TabManager.tabs[staleTabId];
                }
            });
            TabManager.stateManager.saveState();
        }
        static async getTabURL(tab) {
            {
                if (!tab) {
                    return 'about:blank';
                }
                try {
                    return (await chrome.tabs.get(tab.id)).url || 'about:blank';
                }
                catch (e) {
                    try {
                        return (await chrome.scripting.executeScript({
                            target: {
                                tabId: tab.id,
                                frameIds: [0],
                            },
                            world: 'MAIN',
                            injectImmediately: true,
                            func: () => window.location.href,
                        }))[0].result || 'about:blank';
                    }
                    catch (e) {
                        const errMessage = String(e);
                        if (errMessage.includes('chrome://') ||
                            errMessage.includes('chrome-extension://') ||
                            errMessage.includes('gallery')) {
                            return 'chrome://protected';
                        }
                        return 'about:blank';
                    }
                }
            }
            // It can happen in cases whereby the tab.url is empty.
            // Luckily this only and will only happen on `about:blank`-like pages.
            // Due to this we can safely use `about:blank` as fallback value.
            // In some extraordinary circumstances tab may be undefined.
            return tab && tab.url || 'about:blank';
        }
        static async updateContentScript(options) {
            (await queryTabs({ discarded: false }))
                .filter((tab) => true)
                .filter((tab) => !TabManager.tabs[tab.id])
                .forEach((tab) => {
                {
                    chrome.scripting.executeScript({
                        target: {
                            tabId: tab.id,
                            allFrames: true,
                        },
                        files: ['/inject/index.js'],
                    }, () => logInfo('Could not update content script in tab', tab, chrome.runtime.lastError));
                }
            });
        }
        static async registerMailDisplayScript() {
            await chrome.messageDisplayScripts.register({
                js: [
                    { file: '/inject/fallback.js' },
                    { file: '/inject/index.js' },
                ],
            });
        }
        // sendMessage will send a tab messages to all active tabs and their frames.
        // If onlyUpdateActiveTab is specified, it will only send a new message to any
        // tab that matches the active tab's hostname. This is to ensure that when a user
        // has multiple tabs of the same website, every tab will receive the new message
        // and not just that tab as Dark Reader currently doesn't have per-tab operations,
        // this should be the expected behavior.
        static async sendMessage(onlyUpdateActiveTab = false) {
            TabManager.timestamp++;
            const activeTabHostname = onlyUpdateActiveTab ? getURLHostOrProtocol(await TabManager.getActiveTabURL()) : null;
            (await queryTabs({ discarded: false }))
                .filter((tab) => Boolean(TabManager.tabs[tab.id]))
                .forEach((tab) => {
                const frames = TabManager.tabs[tab.id];
                Object.entries(frames)
                    .filter(([, { state }]) => state === DocumentState.ACTIVE || state === DocumentState.PASSIVE)
                    .forEach(async ([id, { url, documentId, scriptId, isTop }]) => {
                    const frameId = Number(id);
                    const tabURL = await TabManager.getTabURL(tab);
                    // Check if hostname are equal when we only want to update active tab.
                    if (onlyUpdateActiveTab && getURLHostOrProtocol(tabURL) !== activeTabHostname) {
                        return;
                    }
                    const message = TabManager.getTabMessage(tabURL, url, isTop || false);
                    message.scriptId = scriptId;
                    if (tab.active && isTop) {
                        TabManager.sendDocumentMessage(tab.id, documentId, message, frameId);
                    }
                    else {
                        setTimeout(() => {
                            TabManager.sendDocumentMessage(tab.id, documentId, message, frameId);
                        });
                    }
                    if (TabManager.tabs[tab.id][frameId]) {
                        TabManager.tabs[tab.id][frameId].timestamp = TabManager.timestamp;
                    }
                });
            });
        }
        static canAccessTab(tab) {
            return tab && Boolean(TabManager.tabs[tab.id]) || false;
        }
        static getTabDocumentId(tab) {
            return tab && TabManager.tabs[tab.id] && TabManager.tabs[tab.id][0] && TabManager.tabs[tab.id][0].documentId;
        }
        static isTabDarkThemeDetected(tab) {
            return tab && TabManager.tabs[tab.id] && TabManager.tabs[tab.id][0] && TabManager.tabs[tab.id][0].darkThemeDetected || null;
        }
        static async getActiveTabURL() {
            return TabManager.getTabURL(await getActiveTab());
        }
    }

    const proposedHighlights = [
        'anniversary',
    ];
    const KEY_UI_HIDDEN_HIGHLIGHTS = 'ui-hidden-highlights';
    async function getHiddenHighlights() {
        const options = await readLocalStorage({ [KEY_UI_HIDDEN_HIGHLIGHTS]: [] });
        return options[KEY_UI_HIDDEN_HIGHLIGHTS];
    }
    async function getHighlightsToShow() {
        const hiddenHighlights = await getHiddenHighlights();
        return proposedHighlights.filter((h) => !hiddenHighlights.includes(h));
    }
    async function hideHighlights(keys) {
        const hiddenHighlights = await getHiddenHighlights();
        const update = Array.from(new Set([...hiddenHighlights, ...keys]));
        await writeLocalStorage({ [KEY_UI_HIDDEN_HIGHLIGHTS]: update });
    }
    async function restoreHighlights(keys) {
        const hiddenHighlights = await getHiddenHighlights();
        const update = Array.from(new Set([...hiddenHighlights.filter((h) => !keys.includes(h))]));
        await writeLocalStorage({ [KEY_UI_HIDDEN_HIGHLIGHTS]: update });
    }
    var UIHighlights = {
        getHighlightsToShow,
        hideHighlights,
        restoreHighlights,
    };

    // evalMath is a function that's able to evaluates a mathematical expression and return it's output.
    //
    // Internally it uses the Shunting Yard algorithm. First it produces a reverse polish notation(RPN) stack.
    // Example: 1 + 2 * 3 -> [1, 2, 3, *, +] which with parentheses means 1 (2 3 *) +
    //
    // Then it evaluates the RPN stack and returns the output.
    function evalMath(expression) {
        // Stack where operators & numbers are stored in RPN.
        const rpnStack = [];
        // The working stack where new tokens are pushed.
        const workingStack = [];
        let lastToken;
        // Iterate over the expression.
        for (let i = 0, len = expression.length; i < len; i++) {
            const token = expression[i];
            // Skip if the token is empty or a whitespace.
            if (!token || token === ' ') {
                continue;
            }
            // Is the token a operator?
            if (operators.has(token)) {
                const op = operators.get(token);
                // Go trough the workingstack and determine it's place in the workingStack
                while (workingStack.length) {
                    const currentOp = operators.get(workingStack[0]);
                    if (!currentOp) {
                        break;
                    }
                    // Is the current operation equal or less than the current operation?
                    // Then move that operation to the rpnStack.
                    if (op.lessOrEqualThan(currentOp)) {
                        rpnStack.push(workingStack.shift());
                    }
                    else {
                        break;
                    }
                }
                // Add the operation to the workingStack.
                workingStack.unshift(token);
                // Otherwise was the last token a operator?
            }
            else if (!lastToken || operators.has(lastToken)) {
                rpnStack.push(token);
                // Otherwise just append the result to the last token(e.g. multiple digits numbers).
            }
            else {
                rpnStack[rpnStack.length - 1] += token;
            }
            // Set the last token.
            lastToken = token;
        }
        // Push the working stack on top of the rpnStack.
        rpnStack.push(...workingStack);
        // Now evaluate the rpnStack.
        const stack = [];
        for (let i = 0, len = rpnStack.length; i < len; i++) {
            const op = operators.get(rpnStack[i]);
            if (op) {
                // Get the arguments of for the operation(first two in the stack).
                const args = stack.splice(0, 2);
                // Excute it, because of reverse notation we first pass second item then the first item.
                stack.push(op.exec(args[1], args[0]));
            }
            else {
                // Add the number to the stack.
                stack.unshift(parseFloat(rpnStack[i]));
            }
        }
        return stack[0];
    }
    // Operator class  defines a operator that can be parsed & evaluated by evalMath.
    class Operator {
        precendce;
        execMethod;
        constructor(precedence, method) {
            this.precendce = precedence;
            this.execMethod = method;
        }
        exec(left, right) {
            return this.execMethod(left, right);
        }
        lessOrEqualThan(op) {
            return this.precendce <= op.precendce;
        }
    }
    const operators = new Map([
        ['+', new Operator(1, (left, right) => left + right)],
        ['-', new Operator(1, (left, right) => left - right)],
        ['*', new Operator(2, (left, right) => left * right)],
        ['/', new Operator(2, (left, right) => left / right)],
    ]);

    const hslaParseCache = new Map();
    const rgbaParseCache = new Map();
    function parseColorWithCache($color) {
        $color = $color.trim();
        if (rgbaParseCache.has($color)) {
            return rgbaParseCache.get($color);
        }
        // We cannot _really_ parse any color which has the calc() expression,
        // so we try our best to remove those and then parse the value.
        if ($color.includes('calc(')) {
            $color = lowerCalcExpression($color);
        }
        const color = parse($color);
        if (color) {
            rgbaParseCache.set($color, color);
            return color;
        }
        return null;
    }
    function parseToHSLWithCache(color) {
        if (hslaParseCache.has(color)) {
            return hslaParseCache.get(color);
        }
        const rgb = parseColorWithCache(color);
        if (!rgb) {
            return null;
        }
        const hsl = rgbToHSL(rgb);
        hslaParseCache.set(color, hsl);
        return hsl;
    }
    // https://en.wikipedia.org/wiki/HSL_and_HSV
    function hslToRGB({ h, s, l, a = 1 }) {
        if (s === 0) {
            const [r, b, g] = [l, l, l].map((x) => Math.round(x * 255));
            return { r, g, b, a };
        }
        const c = (1 - Math.abs(2 * l - 1)) * s;
        const x = c * (1 - Math.abs((h / 60) % 2 - 1));
        const m = l - c / 2;
        const [r, g, b] = (h < 60 ? [c, x, 0] :
            h < 120 ? [x, c, 0] :
                h < 180 ? [0, c, x] :
                    h < 240 ? [0, x, c] :
                        h < 300 ? [x, 0, c] :
                            [c, 0, x]).map((n) => Math.round((n + m) * 255));
        return { r, g, b, a };
    }
    // https://en.wikipedia.org/wiki/HSL_and_HSV
    function rgbToHSL({ r: r255, g: g255, b: b255, a = 1 }) {
        const r = r255 / 255;
        const g = g255 / 255;
        const b = b255 / 255;
        const max = Math.max(r, g, b);
        const min = Math.min(r, g, b);
        const c = max - min;
        const l = (max + min) / 2;
        if (c === 0) {
            return { h: 0, s: 0, l, a };
        }
        let h = (max === r ? (((g - b) / c) % 6) :
            max === g ? ((b - r) / c + 2) :
                ((r - g) / c + 4)) * 60;
        if (h < 0) {
            h += 360;
        }
        const s = c / (1 - Math.abs(2 * l - 1));
        return { h, s, l, a };
    }
    function toFixed(n, digits = 0) {
        const fixed = n.toFixed(digits);
        if (digits === 0) {
            return fixed;
        }
        const dot = fixed.indexOf('.');
        if (dot >= 0) {
            const zerosMatch = fixed.match(/0+$/);
            if (zerosMatch) {
                if (zerosMatch.index === dot + 1) {
                    return fixed.substring(0, dot);
                }
                return fixed.substring(0, zerosMatch.index);
            }
        }
        return fixed;
    }
    function rgbToString(rgb) {
        const { r, g, b, a } = rgb;
        if (a != null && a < 1) {
            return `rgba(${toFixed(r)}, ${toFixed(g)}, ${toFixed(b)}, ${toFixed(a, 2)})`;
        }
        return `rgb(${toFixed(r)}, ${toFixed(g)}, ${toFixed(b)})`;
    }
    function rgbToHexString({ r, g, b, a }) {
        return `#${(a != null && a < 1 ? [r, g, b, Math.round(a * 255)] : [r, g, b]).map((x) => {
        return `${x < 16 ? '0' : ''}${x.toString(16)}`;
    }).join('')}`;
    }
    const rgbMatch = /^rgba?\([^\(\)]+\)$/;
    const hslMatch = /^hsla?\([^\(\)]+\)$/;
    const hexMatch = /^#[0-9a-f]+$/i;
    const supportedColorFuncs = [
        'color',
        'color-mix',
        'hwb',
        'lab',
        'lch',
        'oklab',
        'oklch',
    ];
    function parse($color) {
        const c = $color.trim().toLowerCase();
        if (c.includes('(from ')) {
            if (c.indexOf('(from') !== c.lastIndexOf('(from')) {
                return null;
            }
            return domParseColor(c);
        }
        if (c.match(rgbMatch)) {
            if (c.startsWith('rgb(#') || c.startsWith('rgba(#')) {
                if (c.lastIndexOf('rgb') > 0) {
                    return null;
                }
                return domParseColor(c);
            }
            return parseRGB(c);
        }
        if (c.match(hslMatch)) {
            return parseHSL(c);
        }
        if (c.match(hexMatch)) {
            return parseHex(c);
        }
        if (knownColors.has(c)) {
            return getColorByName(c);
        }
        if (systemColors.has(c)) {
            return getSystemColor(c);
        }
        if (c === 'transparent') {
            return { r: 0, g: 0, b: 0, a: 0 };
        }
        if (c.endsWith(')') &&
            supportedColorFuncs.some((fn) => c.startsWith(fn) && c[fn.length] === '(' && c.lastIndexOf(fn) === 0)) {
            return domParseColor(c);
        }
        if (c.startsWith('light-dark(') && c.endsWith(')')) {
            // light-dark([color()], [color()])
            const match = c.match(/^light-dark\(\s*([a-z]+(\(.*\))?),\s*([a-z]+(\(.*\))?)\s*\)$/);
            if (match) {
                const schemeColor = isSystemDarkModeEnabled() ? match[3] : match[1];
                return parse(schemeColor);
            }
        }
        return null;
    }
    const C_0 = '0'.charCodeAt(0);
    const C_9 = '9'.charCodeAt(0);
    const C_e = 'e'.charCodeAt(0);
    const C_DOT = '.'.charCodeAt(0);
    const C_PLUS = '+'.charCodeAt(0);
    const C_MINUS = '-'.charCodeAt(0);
    const C_SPACE = ' '.charCodeAt(0);
    const C_COMMA = ','.charCodeAt(0);
    const C_SLASH = '/'.charCodeAt(0);
    function getNumbersFromString(input, range, units) {
        const numbers = [];
        const searchStart = input.indexOf('(') + 1;
        const searchEnd = input.length - 1;
        let numStart = -1;
        let unitStart = -1;
        const push = (matchEnd) => {
            const numEnd = unitStart > -1 ? unitStart : matchEnd;
            const $num = input.slice(numStart, numEnd);
            let n = parseFloat($num);
            const r = range[numbers.length];
            if (unitStart > -1) {
                const unit = input.slice(unitStart, matchEnd);
                const u = units[unit];
                if (u != null) {
                    n *= r / u;
                }
            }
            if (r > 1) {
                n = Math.round(n);
            }
            numbers.push(n);
            numStart = -1;
            unitStart = -1;
        };
        for (let i = searchStart; i < searchEnd; i++) {
            const c = input.charCodeAt(i);
            const isNumChar = (c >= C_0 && c <= C_9) || c === C_DOT || c === C_PLUS || c === C_MINUS || c === C_e;
            const isDelimiter = c === C_SPACE || c === C_COMMA || c === C_SLASH;
            if (isNumChar) {
                if (numStart === -1) {
                    numStart = i;
                }
            }
            else if (numStart > -1) {
                if (isDelimiter) {
                    push(i);
                }
                else if (unitStart === -1) {
                    unitStart = i;
                }
            }
        }
        if (numStart > -1) {
            push(searchEnd);
        }
        return numbers;
    }
    const rgbRange = [255, 255, 255, 1];
    const rgbUnits = { '%': 100 };
    function parseRGB($rgb) {
        const [r, g, b, a = 1] = getNumbersFromString($rgb, rgbRange, rgbUnits);
        if (r == null || g == null || b == null || a == null) {
            return null;
        }
        return { r, g, b, a };
    }
    const hslRange = [360, 1, 1, 1];
    const hslUnits = { '%': 100, 'deg': 360, 'rad': 2 * Math.PI, 'turn': 1 };
    function parseHSL($hsl) {
        const [h, s, l, a = 1] = getNumbersFromString($hsl, hslRange, hslUnits);
        if (h == null || s == null || l == null || a == null) {
            return null;
        }
        return hslToRGB({ h, s, l, a });
    }
    const C_A = 'A'.charCodeAt(0);
    const C_F = 'F'.charCodeAt(0);
    const C_a = 'a'.charCodeAt(0);
    const C_f = 'f'.charCodeAt(0);
    function parseHex($hex) {
        const length = $hex.length;
        const digitCount = length - 1;
        const isShort = digitCount === 3 || digitCount === 4;
        const isLong = digitCount === 6 || digitCount === 8;
        if (!isShort && !isLong) {
            return null;
        }
        const hex = (i) => {
            const c = $hex.charCodeAt(i);
            if (c >= C_A && c <= C_F) {
                return c + 10 - C_A;
            }
            if (c >= C_a && c <= C_f) {
                return c + 10 - C_a;
            }
            return c - C_0;
        };
        let r;
        let g;
        let b;
        let a = 1;
        if (isShort) {
            r = hex(1) * 17;
            g = hex(2) * 17;
            b = hex(3) * 17;
            if (digitCount === 4) {
                a = hex(4) * 17 / 255;
            }
        }
        else {
            r = hex(1) * 16 + hex(2);
            g = hex(3) * 16 + hex(4);
            b = hex(5) * 16 + hex(6);
            if (digitCount === 8) {
                a = (hex(7) * 16 + hex(8)) / 255;
            }
        }
        return { r, g, b, a };
    }
    function getColorByName($color) {
        const n = knownColors.get($color);
        return {
            r: (n >> 16) & 255,
            g: (n >> 8) & 255,
            b: (n >> 0) & 255,
            a: 1,
        };
    }
    function getSystemColor($color) {
        const n = systemColors.get($color);
        return {
            r: (n >> 16) & 255,
            g: (n >> 8) & 255,
            b: (n >> 0) & 255,
            a: 1,
        };
    }
    // lowerCalcExpression is a helper function that tries to remove `calc(...)`
    // expressions from the given string. It can only lower expressions to a certain
    // degree so we can keep this function easy and simple to understand.
    function lowerCalcExpression(color) {
        // searchIndex will be used as searchIndex and as a "cursor" within
        // the calc(...) expression.
        let searchIndex = 0;
        // Replace the content between two indices.
        const replaceBetweenIndices = (start, end, replacement) => {
            color = color.substring(0, start) + replacement + color.substring(end);
        };
        // Run this code until it doesn't find any `calc(...)`.
        while ((searchIndex = color.indexOf('calc(')) !== -1) {
            // Get the parentheses ranges of `calc(...)`.
            const range = getParenthesesRange(color, searchIndex);
            if (!range) {
                break;
            }
            // Get the content between the parentheses.
            let slice = color.slice(range.start + 1, range.end - 1);
            // Does the content include a percentage?
            const includesPercentage = slice.includes('%');
            // Remove all percentages.
            slice = slice.split('%').join('');
            // Pass the content to the evalMath library and round its output.
            const output = Math.round(evalMath(slice));
            // Replace `calc(...)` with the result.
            replaceBetweenIndices(range.start - 4, range.end, output + (includesPercentage ? '%' : ''));
        }
        return color;
    }
    const knownColors = new Map(Object.entries({
        aliceblue: 0xf0f8ff,
        antiquewhite: 0xfaebd7,
        aqua: 0x00ffff,
        aquamarine: 0x7fffd4,
        azure: 0xf0ffff,
        beige: 0xf5f5dc,
        bisque: 0xffe4c4,
        black: 0x000000,
        blanchedalmond: 0xffebcd,
        blue: 0x0000ff,
        blueviolet: 0x8a2be2,
        brown: 0xa52a2a,
        burlywood: 0xdeb887,
        cadetblue: 0x5f9ea0,
        chartreuse: 0x7fff00,
        chocolate: 0xd2691e,
        coral: 0xff7f50,
        cornflowerblue: 0x6495ed,
        cornsilk: 0xfff8dc,
        crimson: 0xdc143c,
        cyan: 0x00ffff,
        darkblue: 0x00008b,
        darkcyan: 0x008b8b,
        darkgoldenrod: 0xb8860b,
        darkgray: 0xa9a9a9,
        darkgrey: 0xa9a9a9,
        darkgreen: 0x006400,
        darkkhaki: 0xbdb76b,
        darkmagenta: 0x8b008b,
        darkolivegreen: 0x556b2f,
        darkorange: 0xff8c00,
        darkorchid: 0x9932cc,
        darkred: 0x8b0000,
        darksalmon: 0xe9967a,
        darkseagreen: 0x8fbc8f,
        darkslateblue: 0x483d8b,
        darkslategray: 0x2f4f4f,
        darkslategrey: 0x2f4f4f,
        darkturquoise: 0x00ced1,
        darkviolet: 0x9400d3,
        deeppink: 0xff1493,
        deepskyblue: 0x00bfff,
        dimgray: 0x696969,
        dimgrey: 0x696969,
        dodgerblue: 0x1e90ff,
        firebrick: 0xb22222,
        floralwhite: 0xfffaf0,
        forestgreen: 0x228b22,
        fuchsia: 0xff00ff,
        gainsboro: 0xdcdcdc,
        ghostwhite: 0xf8f8ff,
        gold: 0xffd700,
        goldenrod: 0xdaa520,
        gray: 0x808080,
        grey: 0x808080,
        green: 0x008000,
        greenyellow: 0xadff2f,
        honeydew: 0xf0fff0,
        hotpink: 0xff69b4,
        indianred: 0xcd5c5c,
        indigo: 0x4b0082,
        ivory: 0xfffff0,
        khaki: 0xf0e68c,
        lavender: 0xe6e6fa,
        lavenderblush: 0xfff0f5,
        lawngreen: 0x7cfc00,
        lemonchiffon: 0xfffacd,
        lightblue: 0xadd8e6,
        lightcoral: 0xf08080,
        lightcyan: 0xe0ffff,
        lightgoldenrodyellow: 0xfafad2,
        lightgray: 0xd3d3d3,
        lightgrey: 0xd3d3d3,
        lightgreen: 0x90ee90,
        lightpink: 0xffb6c1,
        lightsalmon: 0xffa07a,
        lightseagreen: 0x20b2aa,
        lightskyblue: 0x87cefa,
        lightslategray: 0x778899,
        lightslategrey: 0x778899,
        lightsteelblue: 0xb0c4de,
        lightyellow: 0xffffe0,
        lime: 0x00ff00,
        limegreen: 0x32cd32,
        linen: 0xfaf0e6,
        magenta: 0xff00ff,
        maroon: 0x800000,
        mediumaquamarine: 0x66cdaa,
        mediumblue: 0x0000cd,
        mediumorchid: 0xba55d3,
        mediumpurple: 0x9370db,
        mediumseagreen: 0x3cb371,
        mediumslateblue: 0x7b68ee,
        mediumspringgreen: 0x00fa9a,
        mediumturquoise: 0x48d1cc,
        mediumvioletred: 0xc71585,
        midnightblue: 0x191970,
        mintcream: 0xf5fffa,
        mistyrose: 0xffe4e1,
        moccasin: 0xffe4b5,
        navajowhite: 0xffdead,
        navy: 0x000080,
        oldlace: 0xfdf5e6,
        olive: 0x808000,
        olivedrab: 0x6b8e23,
        orange: 0xffa500,
        orangered: 0xff4500,
        orchid: 0xda70d6,
        palegoldenrod: 0xeee8aa,
        palegreen: 0x98fb98,
        paleturquoise: 0xafeeee,
        palevioletred: 0xdb7093,
        papayawhip: 0xffefd5,
        peachpuff: 0xffdab9,
        peru: 0xcd853f,
        pink: 0xffc0cb,
        plum: 0xdda0dd,
        powderblue: 0xb0e0e6,
        purple: 0x800080,
        rebeccapurple: 0x663399,
        red: 0xff0000,
        rosybrown: 0xbc8f8f,
        royalblue: 0x4169e1,
        saddlebrown: 0x8b4513,
        salmon: 0xfa8072,
        sandybrown: 0xf4a460,
        seagreen: 0x2e8b57,
        seashell: 0xfff5ee,
        sienna: 0xa0522d,
        silver: 0xc0c0c0,
        skyblue: 0x87ceeb,
        slateblue: 0x6a5acd,
        slategray: 0x708090,
        slategrey: 0x708090,
        snow: 0xfffafa,
        springgreen: 0x00ff7f,
        steelblue: 0x4682b4,
        tan: 0xd2b48c,
        teal: 0x008080,
        thistle: 0xd8bfd8,
        tomato: 0xff6347,
        turquoise: 0x40e0d0,
        violet: 0xee82ee,
        wheat: 0xf5deb3,
        white: 0xffffff,
        whitesmoke: 0xf5f5f5,
        yellow: 0xffff00,
        yellowgreen: 0x9acd32,
    }));
    const systemColors = new Map(Object.entries({
        ActiveBorder: 0x3b99fc,
        ActiveCaption: 0x000000,
        AppWorkspace: 0xaaaaaa,
        Background: 0x6363ce,
        ButtonFace: 0xffffff,
        ButtonHighlight: 0xe9e9e9,
        ButtonShadow: 0x9fa09f,
        ButtonText: 0x000000,
        CaptionText: 0x000000,
        GrayText: 0x7f7f7f,
        Highlight: 0xb2d7ff,
        HighlightText: 0x000000,
        InactiveBorder: 0xffffff,
        InactiveCaption: 0xffffff,
        InactiveCaptionText: 0x000000,
        InfoBackground: 0xfbfcc5,
        InfoText: 0x000000,
        Menu: 0xf6f6f6,
        MenuText: 0xffffff,
        Scrollbar: 0xaaaaaa,
        ThreeDDarkShadow: 0x000000,
        ThreeDFace: 0xc0c0c0,
        ThreeDHighlight: 0xffffff,
        ThreeDLightShadow: 0xffffff,
        ThreeDShadow: 0x000000,
        Window: 0xececec,
        WindowFrame: 0xaaaaaa,
        WindowText: 0x000000,
        '-webkit-focus-ring-color': 0xe59700,
    }).map(([key, value]) => [key.toLowerCase(), value]));
    let canvas;
    let context;
    function domParseColor($color) {
        if (!context) {
            canvas = document.createElement('canvas');
            canvas.width = 1;
            canvas.height = 1;
            context = canvas.getContext('2d', { willReadFrequently: true });
        }
        context.fillStyle = $color;
        context.fillRect(0, 0, 1, 1);
        const d = context.getImageData(0, 0, 1, 1).data;
        const color = `rgba(${d[0]}, ${d[1]}, ${d[2]}, ${(d[3] / 255).toFixed(2)})`;
        return parseRGB(color);
    }

    const registeredColors = new Map();
    function getRegisteredVariableValue(type, registered) {
        return `var(${registered[type].variable}, ${registered[type].value})`;
    }
    function getRegisteredColor(type, parsed) {
        const hex = rgbToHexString(parsed);
        const registered = registeredColors.get(hex);
        if (registered?.[type]) {
            return getRegisteredVariableValue(type, registered);
        }
        return null;
    }
    function registerColor(type, parsed, value) {
        const hex = rgbToHexString(parsed);
        let registered;
        if (registeredColors.has(hex)) {
            registered = registeredColors.get(hex);
        }
        else {
            const parsed = parseColorWithCache(hex);
            registered = { parsed };
            registeredColors.set(hex, registered);
        }
        const variable = `--darkreader-${type}-${hex.replace('#', '')}`;
        registered[type] = { variable, value };
        return getRegisteredVariableValue(type, registered);
    }

    function getBgPole(theme) {
        const isDarkScheme = theme.mode === 1;
        const prop = isDarkScheme ? 'darkSchemeBackgroundColor' : 'lightSchemeBackgroundColor';
        return theme[prop];
    }
    function getFgPole(theme) {
        const isDarkScheme = theme.mode === 1;
        const prop = isDarkScheme ? 'darkSchemeTextColor' : 'lightSchemeTextColor';
        return theme[prop];
    }
    const colorModificationCache = new Map();
    const rgbCacheKeys = ['r', 'g', 'b', 'a'];
    const themeCacheKeys = [
        'mode',
        'brightness',
        'contrast',
        'grayscale',
        'sepia',
        'darkSchemeBackgroundColor',
        'darkSchemeTextColor',
        'lightSchemeBackgroundColor',
        'lightSchemeTextColor',
    ];
    function getCacheId(rgb, theme) {
        let resultId = '';
        rgbCacheKeys.forEach((key) => {
            resultId += `${rgb[key]};`;
        });
        themeCacheKeys.forEach((key) => {
            resultId += `${theme[key]};`;
        });
        return resultId;
    }
    function modifyColorWithCache(rgb, theme, modifyHSL, poleColor, anotherPoleColor) {
        let fnCache;
        if (colorModificationCache.has(modifyHSL)) {
            fnCache = colorModificationCache.get(modifyHSL);
        }
        else {
            fnCache = new Map();
            colorModificationCache.set(modifyHSL, fnCache);
        }
        const id = getCacheId(rgb, theme);
        if (fnCache.has(id)) {
            return fnCache.get(id);
        }
        const hsl = rgbToHSL(rgb);
        const pole = poleColor == null ? null : parseToHSLWithCache(poleColor);
        const anotherPole = anotherPoleColor == null ? null : parseToHSLWithCache(anotherPoleColor);
        const modified = modifyHSL(hsl, pole, anotherPole);
        const { r, g, b, a } = hslToRGB(modified);
        const matrix = createFilterMatrix({ ...theme, mode: 0 });
        const [rf, gf, bf] = applyColorMatrix([r, g, b], matrix);
        const color = (a === 1 ?
            rgbToHexString({ r: rf, g: gf, b: bf }) :
            rgbToString({ r: rf, g: gf, b: bf, a }));
        fnCache.set(id, color);
        return color;
    }
    function modifyAndRegisterColor(type, rgb, theme, modifier) {
        const registered = getRegisteredColor(type, rgb);
        if (registered) {
            return registered;
        }
        const value = modifier(rgb, theme);
        return registerColor(type, rgb, value);
    }
    function modifyLightSchemeColor(rgb, theme) {
        const poleBg = getBgPole(theme);
        const poleFg = getFgPole(theme);
        return modifyColorWithCache(rgb, theme, modifyLightModeHSL, poleFg, poleBg);
    }
    function modifyLightModeHSL({ h, s, l, a }, poleFg, poleBg) {
        const isDark = l < 0.5;
        let isNeutral;
        if (isDark) {
            isNeutral = l < 0.2 || s < 0.12;
        }
        else {
            const isBlue = h > 200 && h < 280;
            isNeutral = s < 0.24 || (l > 0.8 && isBlue);
        }
        let hx = h;
        let sx = s;
        if (isNeutral) {
            if (isDark) {
                hx = poleFg.h;
                sx = poleFg.s;
            }
            else {
                hx = poleBg.h;
                sx = poleBg.s;
            }
        }
        const lx = scale(l, 0, 1, poleFg.l, poleBg.l);
        return { h: hx, s: sx, l: lx, a };
    }
    const MAX_BG_LIGHTNESS = 0.4;
    function modifyBgHSL({ h, s, l, a }, pole) {
        const isDark = l < 0.5;
        const isBlue = h > 200 && h < 280;
        const isNeutral = s < 0.12 || (l > 0.8 && isBlue);
        if (isDark) {
            const lx = scale(l, 0, 0.5, 0, MAX_BG_LIGHTNESS);
            if (isNeutral) {
                const hx = pole.h;
                const sx = pole.s;
                return { h: hx, s: sx, l: lx, a };
            }
            return { h, s, l: lx, a };
        }
        let lx = scale(l, 0.5, 1, MAX_BG_LIGHTNESS, pole.l);
        if (isNeutral) {
            const hx = pole.h;
            const sx = pole.s;
            return { h: hx, s: sx, l: lx, a };
        }
        let hx = h;
        const isYellow = h > 60 && h < 180;
        if (isYellow) {
            const isCloserToGreen = h > 120;
            if (isCloserToGreen) {
                hx = scale(h, 120, 180, 135, 180);
            }
            else {
                hx = scale(h, 60, 120, 60, 105);
            }
        }
        // Lower the lightness, if the resulting
        // hue is in lower yellow spectrum.
        if (hx > 40 && hx < 80) {
            lx *= 0.75;
        }
        return { h: hx, s, l: lx, a };
    }
    function _modifyBackgroundColor(rgb, theme) {
        if (theme.mode === 0) {
            return modifyLightSchemeColor(rgb, theme);
        }
        const pole = getBgPole(theme);
        return modifyColorWithCache(rgb, theme, modifyBgHSL, pole);
    }
    function modifyBackgroundColor(rgb, theme, shouldRegisterColorVariable = true) {
        if (!shouldRegisterColorVariable) {
            return _modifyBackgroundColor(rgb, theme);
        }
        return modifyAndRegisterColor('background', rgb, theme, _modifyBackgroundColor);
    }
    const MIN_FG_LIGHTNESS = 0.55;
    function modifyBlueFgHue(hue) {
        return scale(hue, 205, 245, 205, 220);
    }
    function modifyFgHSL({ h, s, l, a }, pole) {
        const isLight = l > 0.5;
        const isNeutral = l < 0.2 || s < 0.24;
        const isBlue = !isNeutral && h > 205 && h < 245;
        if (isLight) {
            const lx = scale(l, 0.5, 1, MIN_FG_LIGHTNESS, pole.l);
            if (isNeutral) {
                const hx = pole.h;
                const sx = pole.s;
                return { h: hx, s: sx, l: lx, a };
            }
            let hx = h;
            if (isBlue) {
                hx = modifyBlueFgHue(h);
            }
            return { h: hx, s, l: lx, a };
        }
        if (isNeutral) {
            const hx = pole.h;
            const sx = pole.s;
            const lx = scale(l, 0, 0.5, pole.l, MIN_FG_LIGHTNESS);
            return { h: hx, s: sx, l: lx, a };
        }
        let hx = h;
        let lx;
        if (isBlue) {
            hx = modifyBlueFgHue(h);
            lx = scale(l, 0, 0.5, pole.l, Math.min(1, MIN_FG_LIGHTNESS + 0.05));
        }
        else {
            lx = scale(l, 0, 0.5, pole.l, MIN_FG_LIGHTNESS);
        }
        return { h: hx, s, l: lx, a };
    }
    function _modifyForegroundColor(rgb, theme) {
        if (theme.mode === 0) {
            return modifyLightSchemeColor(rgb, theme);
        }
        const pole = getFgPole(theme);
        return modifyColorWithCache(rgb, theme, modifyFgHSL, pole);
    }
    function modifyForegroundColor(rgb, theme, shouldRegisterColorVariable = true) {
        if (!shouldRegisterColorVariable) {
            return _modifyForegroundColor(rgb, theme);
        }
        return modifyAndRegisterColor('text', rgb, theme, _modifyForegroundColor);
    }
    function modifyBorderHSL({ h, s, l, a }, poleFg, poleBg) {
        const isDark = l < 0.5;
        const isNeutral = l < 0.2 || s < 0.24;
        let hx = h;
        let sx = s;
        if (isNeutral) {
            if (isDark) {
                hx = poleFg.h;
                sx = poleFg.s;
            }
            else {
                hx = poleBg.h;
                sx = poleBg.s;
            }
        }
        const lx = scale(l, 0, 1, 0.5, 0.2);
        return { h: hx, s: sx, l: lx, a };
    }
    function _modifyBorderColor(rgb, theme) {
        if (theme.mode === 0) {
            return modifyLightSchemeColor(rgb, theme);
        }
        const poleFg = getFgPole(theme);
        const poleBg = getBgPole(theme);
        return modifyColorWithCache(rgb, theme, modifyBorderHSL, poleFg, poleBg);
    }
    function modifyBorderColor(rgb, theme, shouldRegisterColorVariable = true) {
        if (!shouldRegisterColorVariable) {
            return _modifyBorderColor(rgb, theme);
        }
        return modifyAndRegisterColor('border', rgb, theme, _modifyBorderColor);
    }

    const themeColorTypes = {
        accentcolor: 'bg',
        button_background_active: 'text',
        button_background_hover: 'text',
        frame: 'bg',
        icons: 'text',
        icons_attention: 'text',
        ntp_background: 'bg',
        ntp_text: 'text',
        popup: 'bg',
        popup_border: 'bg',
        popup_highlight: 'bg',
        popup_highlight_text: 'text',
        popup_text: 'text',
        sidebar: 'bg',
        sidebar_border: 'border',
        sidebar_text: 'text',
        tab_background_text: 'text',
        tab_line: 'bg',
        tab_loading: 'bg',
        tab_selected: 'bg',
        textcolor: 'text',
        toolbar: 'bg',
        toolbar_bottom_separator: 'border',
        toolbar_field: 'bg',
        toolbar_field_border: 'border',
        toolbar_field_border_focus: 'border',
        toolbar_field_focus: 'bg',
        toolbar_field_separator: 'border',
        toolbar_field_text: 'text',
        toolbar_field_text_focus: 'text',
        toolbar_text: 'text',
        toolbar_top_separator: 'border',
        toolbar_vertical_separator: 'border',
    };
    const $colors = {
        // 'accentcolor' is the deprecated predecessor of 'frame'.
        // https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/theme#colors
        accentcolor: '#111111',
        frame: '#111111',
        ntp_background: 'white',
        ntp_text: 'black',
        popup: '#cccccc',
        popup_text: 'black',
        sidebar: '#cccccc',
        sidebar_border: '#333',
        sidebar_text: 'black',
        tab_background_text: 'white',
        tab_loading: '#23aeff',
        // 'textcolor' is the predecessor of 'tab_background_text'.
        // https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/theme#colors
        textcolor: 'white',
        toolbar: '#707070',
        toolbar_field: 'lightgray',
        toolbar_field_text: 'black',
    };
    function setWindowTheme(theme) {
        const colors = Object.entries($colors).reduce((obj, [key, value]) => {
            const type = themeColorTypes[key];
            const modify = {
                'bg': modifyBackgroundColor,
                'text': modifyForegroundColor,
                'border': modifyBorderColor,
            }[type];
            const rgb = parseColorWithCache(value);
            const modified = modify(rgb, theme, false);
            obj[key] = modified;
            return obj;
        }, {});
        if (typeof browser !== 'undefined' && browser.theme && browser.theme.update) {
            browser.theme.update({ colors });
        }
    }
    function resetWindowTheme() {
        if (typeof browser !== 'undefined' && browser.theme && browser.theme.reset) {
            // BUG: resets browser theme to entire
            // https://bugzilla.mozilla.org/show_bug.cgi?id=1415267
            browser.theme.reset();
        }
    }

    class Extension {
        static autoState = '';
        static wasEnabledOnLastCheck = null;
        static registeredContextMenus = null;
        /**
         * This value is used for two purposes:
         *  - to bypass Firefox bug
         *  - to filter out excessive Extension.onColorSchemeChange() invocations
         */
        static wasLastColorSchemeDark = null;
        static startBarrier = null;
        static stateManager = null;
        static ALARM_NAME = 'auto-time-alarm';
        static LOCAL_STORAGE_KEY = 'Extension-state';
        // Store system color theme
        static SYSTEM_COLOR_LOCAL_STORAGE_KEY = 'system-color-state';
        static systemColorStateManager;
        // Record whether Extension.init() already ran since the last GB start
        static initialized = false;
        static isFirstLoad = false;
        // This sync initializer needs to run on every BG restart before anything else can happen
        static init() {
            if (Extension.initialized) {
                return;
            }
            Extension.initialized = true;
            DevTools.init(Extension.onSettingsChanged);
            Messenger.init(Extension.getMessengerAdapter());
            TabManager.init({
                getConnectionMessage: Extension.getConnectionMessage,
                getTabMessage: Extension.getTabMessage,
                onColorSchemeChange: Extension.onColorSchemeChange,
            });
            Extension.startBarrier = new PromiseBarrier();
            Extension.stateManager = new StateManager(Extension.LOCAL_STORAGE_KEY, Extension, {
                autoState: '',
                wasEnabledOnLastCheck: null,
                registeredContextMenus: null,
            }, logWarn);
            chrome.alarms.onAlarm.addListener(Extension.alarmListener);
            if (chrome.commands) {
                // Firefox Android does not support chrome.commands
                {
                    chrome.commands.onCommand.addListener(async (command, tab) => Extension.onCommand(command, tab && tab.id || null, 0, null));
                }
            }
            if (chrome.permissions.onRemoved) {
                chrome.permissions.onRemoved.addListener((permissions) => {
                    // As far as we know, this code is never actually run because there
                    // is no browser UI for removing 'contextMenus' permission.
                    // This code exists for future-proofing in case browsers ever add such UI.
                    if (!permissions?.permissions?.includes('contextMenus')) {
                        Extension.registeredContextMenus = false;
                    }
                });
            }
        }
        static async MV3syncSystemColorStateManager(isDark) {
            if (!Extension.systemColorStateManager) {
                Extension.systemColorStateManager = new StateManager(Extension.SYSTEM_COLOR_LOCAL_STORAGE_KEY, Extension, {
                    wasLastColorSchemeDark: isDark,
                }, logWarn);
            }
            if (isDark === null) {
                // Attempt to restore data from storage
                return Extension.systemColorStateManager.loadState();
            }
            else if (Extension.wasLastColorSchemeDark !== isDark) {
                Extension.wasLastColorSchemeDark = isDark;
                return Extension.systemColorStateManager.saveState();
            }
        }
        static alarmListener = (alarm) => {
            if (alarm.name === Extension.ALARM_NAME) {
                Extension.loadData().then(() => Extension.handleAutomationCheck());
            }
        };
        static isExtensionSwitchedOn() {
            return (Extension.autoState === 'turn-on' ||
                Extension.autoState === 'scheme-dark' ||
                Extension.autoState === 'scheme-light' ||
                (Extension.autoState === '' && UserStorage.settings.enabled));
        }
        static updateAutoState() {
            const { mode, behavior, enabled } = UserStorage.settings.automation;
            let isAutoDark;
            let nextCheck;
            switch (mode) {
                case AutomationMode.TIME: {
                    const { time } = UserStorage.settings;
                    isAutoDark = isInTimeIntervalLocal(time.activation, time.deactivation);
                    nextCheck = nextTimeInterval(time.activation, time.deactivation);
                    break;
                }
                case AutomationMode.SYSTEM:
                    {
                        isAutoDark = Extension.wasLastColorSchemeDark;
                        if (Extension.wasLastColorSchemeDark === null) {
                            logWarn('System color scheme is unknown. Defaulting to Dark.');
                            isAutoDark = true;
                        }
                        break;
                    }
                case AutomationMode.LOCATION: {
                    const { latitude, longitude } = UserStorage.settings.location;
                    if (latitude != null && longitude != null) {
                        isAutoDark = isNightAtLocation(latitude, longitude);
                        nextCheck = nextTimeChangeAtLocation(latitude, longitude);
                    }
                    break;
                }
                case AutomationMode.NONE:
                    break;
            }
            let state = '';
            if (enabled) {
                if (behavior === 'OnOff') {
                    state = isAutoDark ? 'turn-on' : 'turn-off';
                }
                else if (behavior === 'Scheme') {
                    state = isAutoDark ? 'scheme-dark' : 'scheme-light';
                }
            }
            Extension.autoState = state;
            if (nextCheck) {
                if (nextCheck < Date.now()) {
                    logWarn(`Alarm is set in the past: ${nextCheck}. The time is: ${new Date()}. ISO: ${(new Date()).toISOString()}`);
                }
                else {
                    chrome.alarms.create(Extension.ALARM_NAME, { when: nextCheck });
                }
            }
        }
        static wakeInterval = -1;
        static runWakeDetector() {
            const WAKE_CHECK_INTERVAL = getDuration({ minutes: 1 });
            const WAKE_CHECK_INTERVAL_ERROR = getDuration({ seconds: 10 });
            if (this.wakeInterval >= 0) {
                clearInterval(this.wakeInterval);
            }
            let lastRun = Date.now();
            this.wakeInterval = setInterval(() => {
                const now = Date.now();
                if (now - lastRun > WAKE_CHECK_INTERVAL + WAKE_CHECK_INTERVAL_ERROR) {
                    Extension.handleAutomationCheck();
                }
                lastRun = now;
            }, WAKE_CHECK_INTERVAL);
        }
        static async start() {
            Extension.init();
            await TabManager.cleanState();
            await Promise.all([
                ConfigManager.load({ local: true }),
                Extension.MV3syncSystemColorStateManager(null),
                UserStorage.loadSettings(),
            ]);
            if (UserStorage.settings.enableContextMenus && !Extension.registeredContextMenus) {
                chrome.permissions.contains({ permissions: ['contextMenus'] }, (permitted) => {
                    if (permitted) {
                        Extension.registerContextMenus();
                    }
                    else {
                        logWarn('User has enabled context menus, but did not provide permission.');
                    }
                });
            }
            if (UserStorage.settings.syncSitesFixes) {
                await ConfigManager.load({ local: false });
            }
            Extension.updateAutoState();
            Extension.runWakeDetector();
            Extension.onAppToggle();
            logInfo('loaded', UserStorage.settings);
            if (Extension.isFirstLoad) {
                TabManager.updateContentScript({ runOnProtectedPages: UserStorage.settings.enableForProtectedPages });
            }
            UserStorage.settings.fetchNews && Newsmaker.subscribe();
            Extension.startBarrier.resolve();
        }
        static getMessengerAdapter() {
            return {
                collect: async () => {
                    return await Extension.collectData();
                },
                collectDevToolsData: async () => {
                    return await Extension.collectDevToolsData();
                },
                changeSettings: Extension.changeSettings,
                setTheme: Extension.setTheme,
                toggleActiveTab: Extension.toggleActiveTab,
                markNewsAsRead: Newsmaker.markAsRead,
                markNewsAsDisplayed: Newsmaker.markAsDisplayed,
                loadConfig: ConfigManager.load,
                applyDevDynamicThemeFixes: DevTools.applyDynamicThemeFixes,
                resetDevDynamicThemeFixes: DevTools.resetDynamicThemeFixes,
                applyDevInversionFixes: DevTools.applyInversionFixes,
                resetDevInversionFixes: DevTools.resetInversionFixes,
                applyDevStaticThemes: DevTools.applyStaticThemes,
                resetDevStaticThemes: DevTools.resetStaticThemes,
                startActivation: Extension.startActivation,
                resetActivation: Extension.resetActivation,
                hideHighlights: UIHighlights.hideHighlights,
            };
        }
        static onCommandInternal = async (command, tabId, frameId, frameURL) => {
            if (Extension.startBarrier.isPending()) {
                await Extension.startBarrier.entry();
            }
            Extension.stateManager.loadState();
            switch (command) {
                case 'toggle':
                    logInfo('Toggle command entered');
                    Extension.changeSettings({
                        enabled: !Extension.isExtensionSwitchedOn(),
                        automation: { ...UserStorage.settings.automation, ...{ enabled: false } },
                    });
                    break;
                case 'addSite': {
                    logInfo('Add Site command entered');
                    async function scriptPDF(tabId, frameId) {
                        // We can not detect PDF if we do not know where we are looking for it
                        if (!(Number.isInteger(tabId) && Number.isInteger(frameId))) {
                            return false;
                        }
                        function detectPDF() {
                            if (document.body.childElementCount !== 1) {
                                return false;
                            }
                            const { nodeName, type } = document.body.childNodes[0];
                            return nodeName === 'EMBED' && type === 'application/pdf';
                        }
                        {
                            return (await chrome.scripting.executeScript({
                                target: { tabId, frameIds: [frameId] },
                                func: detectPDF,
                            }))[0].result || false;
                        }
                    }
                    const pdf = async () => isPDF(frameURL || await TabManager.getActiveTabURL());
                    if ((await scriptPDF(tabId, frameId)) || await pdf()) {
                        Extension.changeSettings({ enableForPDF: !UserStorage.settings.enableForPDF });
                    }
                    else {
                        Extension.toggleActiveTab();
                    }
                    break;
                }
                case 'switchEngine': {
                    logInfo('Switch Engine command entered');
                    const engines = Object.values(ThemeEngine);
                    const index = engines.indexOf(UserStorage.settings.theme.engine);
                    const next = engines[(index + 1) % engines.length];
                    Extension.setTheme({ engine: next });
                    break;
                }
            }
        };
        // 75 is small enough to not notice it, and still catches when someone
        // is holding down a certain shortcut.
        static onCommand = debounce(75, Extension.onCommandInternal);
        static registerContextMenus() {
            chrome.contextMenus.onClicked.addListener(async ({ menuItemId, frameId, frameUrl, pageUrl }, tab) => Extension.onCommand(menuItemId, tab && tab.id || null, frameId || null, frameUrl || pageUrl || null));
            chrome.contextMenus.removeAll(() => {
                Extension.registeredContextMenus = false;
                chrome.contextMenus.create({
                    id: 'DarkReader-top',
                    title: 'Dark Reader',
                }, () => {
                    if (chrome.runtime.lastError) {
                        // Failed to create the context menu
                        return;
                    }
                    const msgToggle = chrome.i18n.getMessage('toggle_extension');
                    const msgAddSite = chrome.i18n.getMessage('toggle_current_site');
                    const msgSwitchEngine = chrome.i18n.getMessage('theme_generation_mode');
                    chrome.contextMenus.create({
                        id: 'toggle',
                        parentId: 'DarkReader-top',
                        title: msgToggle || 'Toggle everywhere',
                    });
                    chrome.contextMenus.create({
                        id: 'addSite',
                        parentId: 'DarkReader-top',
                        title: msgAddSite || 'Toggle for current site',
                    });
                    chrome.contextMenus.create({
                        id: 'switchEngine',
                        parentId: 'DarkReader-top',
                        title: msgSwitchEngine || 'Switch engine',
                    });
                    Extension.registeredContextMenus = true;
                });
            });
        }
        static async getShortcuts() {
            const commands = await getCommands();
            return commands.reduce((map, cmd) => Object.assign(map, { [cmd.name]: cmd.shortcut }), {});
        }
        static async collectData() {
            await Extension.loadData();
            const [news, shortcuts, activeTab, isAllowedFileSchemeAccess, uiHighlights,] = await Promise.all([
                Newsmaker.getLatest(),
                Extension.getShortcuts(),
                Extension.getActiveTabInfo(),
                new Promise((r) => chrome.extension.isAllowedFileSchemeAccess(r)),
                UIHighlights.getHighlightsToShow(),
            ]);
            return {
                isEnabled: Extension.isExtensionSwitchedOn(),
                isReady: true,
                isAllowedFileSchemeAccess,
                settings: UserStorage.settings,
                news,
                shortcuts,
                colorScheme: ConfigManager.COLOR_SCHEMES_RAW,
                forcedScheme: Extension.autoState === 'scheme-dark' ? 'dark' : Extension.autoState === 'scheme-light' ? 'light' : null,
                activeTab,
                uiHighlights,
            };
        }
        static async collectDevToolsData() {
            const [dynamicFixesText, filterFixesText, staticThemesText,] = await Promise.all([
                DevTools.getDynamicThemeFixesText(),
                DevTools.getInversionFixesText(),
                DevTools.getStaticThemesText(),
            ]);
            return {
                dynamicFixesText,
                filterFixesText,
                staticThemesText,
            };
        }
        static async getActiveTabInfo() {
            await Extension.loadData();
            const tab = await getActiveTab();
            const url = await TabManager.getTabURL(tab);
            const { isInDarkList, isProtected } = Extension.getTabInfo(url);
            const isInjected = TabManager.canAccessTab(tab);
            const documentId = TabManager.getTabDocumentId(tab);
            let isDarkThemeDetected = null;
            if (UserStorage.settings.detectDarkTheme) {
                isDarkThemeDetected = TabManager.isTabDarkThemeDetected(tab);
            }
            const id = tab && tab.id || null;
            return {
                id,
                documentId,
                url,
                isInDarkList,
                isProtected,
                isInjected,
                isDarkThemeDetected,
            };
        }
        static async getConnectionMessage(tabURL, url, isTopFrame, topFrameHasDarkTheme) {
            await Extension.loadData();
            return Extension.getTabMessage(tabURL, url, isTopFrame, topFrameHasDarkTheme);
        }
        static async loadData() {
            Extension.init();
            await Promise.all([
                Extension.stateManager.loadState(),
                UserStorage.loadSettings(),
            ]);
        }
        static onColorSchemeChange = async (isDark) => {
            if (Extension.wasLastColorSchemeDark === isDark) {
                // If color scheme was already correct, we do not need to do anything
                return;
            }
            Extension.wasLastColorSchemeDark = isDark;
            Extension.MV3syncSystemColorStateManager(isDark);
            await Extension.loadData();
            if (UserStorage.settings.automation.mode !== AutomationMode.SYSTEM) {
                return;
            }
            Extension.handleAutomationCheck();
        };
        static handleAutomationCheck = () => {
            Extension.updateAutoState();
            const isSwitchedOn = Extension.isExtensionSwitchedOn();
            if (Extension.wasEnabledOnLastCheck === null ||
                Extension.wasEnabledOnLastCheck !== isSwitchedOn ||
                Extension.autoState === 'scheme-dark' ||
                Extension.autoState === 'scheme-light') {
                Extension.wasEnabledOnLastCheck = isSwitchedOn;
                Extension.onAppToggle();
                TabManager.sendMessage();
                Extension.reportChanges();
                Extension.stateManager.saveState();
            }
        };
        static async changeSettings($settings, onlyUpdateActiveTab = false) {
            const promises = [];
            const prev = { ...UserStorage.settings };
            UserStorage.set($settings);
            if ((prev.enabled !== UserStorage.settings.enabled) ||
                (prev.automation.enabled !== UserStorage.settings.automation.enabled) ||
                (prev.automation.mode !== UserStorage.settings.automation.mode) ||
                (prev.automation.behavior !== UserStorage.settings.automation.behavior) ||
                (prev.time.activation !== UserStorage.settings.time.activation) ||
                (prev.time.deactivation !== UserStorage.settings.time.deactivation) ||
                (prev.location.latitude !== UserStorage.settings.location.latitude) ||
                (prev.location.longitude !== UserStorage.settings.location.longitude)) {
                Extension.updateAutoState();
                Extension.onAppToggle();
            }
            if (prev.syncSettings !== UserStorage.settings.syncSettings) {
                const promise = UserStorage.saveSyncSetting(UserStorage.settings.syncSettings);
                promises.push(promise);
            }
            if (Extension.isExtensionSwitchedOn() && $settings.changeBrowserTheme != null && prev.changeBrowserTheme !== $settings.changeBrowserTheme) {
                if ($settings.changeBrowserTheme) {
                    setWindowTheme(UserStorage.settings.theme);
                }
                else {
                    resetWindowTheme();
                }
            }
            if (prev.fetchNews !== UserStorage.settings.fetchNews) {
                UserStorage.settings.fetchNews ? Newsmaker.subscribe() : Newsmaker.unSubscribe();
            }
            if (prev.enableContextMenus !== UserStorage.settings.enableContextMenus) {
                if (UserStorage.settings.enableContextMenus) {
                    Extension.registerContextMenus();
                }
                else {
                    chrome.contextMenus.removeAll();
                }
            }
            const promise = Extension.onSettingsChanged(onlyUpdateActiveTab);
            promises.push(promise);
            await Promise.all(promises);
        }
        static setTheme($theme) {
            UserStorage.set({ theme: { ...UserStorage.settings.theme, ...$theme } });
            if (Extension.isExtensionSwitchedOn() && UserStorage.settings.changeBrowserTheme) {
                setWindowTheme(UserStorage.settings.theme);
            }
            Extension.onSettingsChanged();
        }
        static async reportChanges() {
            const info = await Extension.collectData();
            Messenger.reportChanges(info);
        }
        static async toggleActiveTab() {
            const settings = UserStorage.settings;
            const tab = await Extension.getActiveTabInfo();
            if (!tab) {
                return;
            }
            const { url } = tab;
            const isInDarkList = ConfigManager.isURLInDarkList(url);
            const host = getURLHostOrProtocol(url);
            function getToggledList(sourceList) {
                const list = sourceList.slice();
                let index = list.indexOf(host);
                if (index < 0 && host.startsWith('www.')) {
                    const noWwwHost = host.substring(4);
                    index = list.indexOf(noWwwHost);
                }
                if (index < 0) {
                    list.push(host);
                }
                else {
                    list.splice(index, 1);
                }
                return list;
            }
            const darkThemeDetected = settings.enabledByDefault && settings.detectDarkTheme && tab.isDarkThemeDetected;
            if (!settings.enabledByDefault || isInDarkList || darkThemeDetected) {
                const toggledList = getToggledList(settings.enabledFor);
                Extension.changeSettings({ enabledFor: toggledList }, true);
                return;
            }
            if (settings.enabledByDefault && settings.enabledFor.includes(host)) {
                const enabledFor = getToggledList(settings.enabledFor);
                const disabledFor = getToggledList(settings.disabledFor);
                Extension.changeSettings({ enabledFor, disabledFor }, true);
                return;
            }
            const toggledList = getToggledList(settings.disabledFor);
            Extension.changeSettings({ disabledFor: toggledList }, true);
        }
        //------------------------------------
        //
        //       Handle config changes
        //
        static onAppToggle() {
            if (Extension.isExtensionSwitchedOn()) {
                IconManager.setIcon({ isActive: true, colorScheme: UserStorage.settings.theme.mode ? 'dark' : 'light' });
            }
            else {
                IconManager.setIcon({ isActive: false, colorScheme: UserStorage.settings.theme.mode ? 'dark' : 'light' });
            }
            if (UserStorage.settings.changeBrowserTheme) {
                if (Extension.isExtensionSwitchedOn() && Extension.autoState !== 'scheme-light') {
                    setWindowTheme(UserStorage.settings.theme);
                }
                else {
                    resetWindowTheme();
                }
            }
        }
        static async onSettingsChanged(onlyUpdateActiveTab = false) {
            await Extension.loadData();
            Extension.wasEnabledOnLastCheck = Extension.isExtensionSwitchedOn();
            TabManager.sendMessage(onlyUpdateActiveTab);
            Extension.saveUserSettings();
            Extension.reportChanges();
            IconManager.setIcon({ colorScheme: UserStorage.settings.theme.mode ? 'dark' : 'light' });
            Extension.stateManager.saveState();
        }
        static async startActivation(email, key) {
            const delay = 2000 + Math.round(Math.random() * 2000);
            const checkEmail = (email) => email && email.trim().includes('@');
            const checkKey = (key) => key.replaceAll('-', '').length === 25 && key.toLocaleLowerCase().startsWith('dr') && key.replaceAll('-', '').match(/^[0-9a-z]{25}$/i);
            setTimeout(async () => {
                await writeLocalStorage({ activationEmail: email, activationKey: key });
                if (checkEmail(email) && checkKey(key)) {
                    await UIHighlights.hideHighlights(['anniversary']);
                }
                Extension.reportChanges();
            }, delay);
        }
        static async resetActivation() {
            await removeLocalStorage(['activationEmail', 'activationKey']);
            await UIHighlights.restoreHighlights(['anniversary']);
            Extension.reportChanges();
        }
        //----------------------
        //
        // Add/remove css to tab
        //
        //----------------------
        static getTabInfo(tabURL) {
            const isInDarkList = ConfigManager.isURLInDarkList(tabURL);
            const isProtected = !canInjectScript(tabURL);
            return {
                isInDarkList,
                isProtected,
            };
        }
        static getTabMessage = (tabURL, url, isTopFrame, topFrameHasDarkTheme) => {
            const settings = UserStorage.settings;
            const tabInfo = Extension.getTabInfo(tabURL);
            if (Extension.isExtensionSwitchedOn() && isURLEnabled(tabURL, settings, tabInfo) && !topFrameHasDarkTheme) {
                const custom = settings.customThemes.find(({ url: urlList }) => isURLInList(tabURL, urlList));
                const preset = custom ? null : settings.presets.find(({ urls }) => isURLInList(tabURL, urls));
                let theme = custom ? custom.theme : preset ? preset.theme : settings.theme;
                if (Extension.autoState === 'scheme-dark' || Extension.autoState === 'scheme-light') {
                    const mode = Extension.autoState === 'scheme-dark' ? 1 : 0;
                    theme = { ...theme, mode };
                }
                const detectorHints = settings.detectDarkTheme ? getDetectorHintsFor(url, ConfigManager.DETECTOR_HINTS_RAW, ConfigManager.DETECTOR_HINTS_INDEX) : null;
                const detectDarkTheme = (settings.detectDarkTheme &&
                    (isTopFrame || detectorHints?.some((h) => h.iframe)) &&
                    !isURLInList(tabURL, settings.enabledFor) &&
                    !isPDF(tabURL));
                logInfo(`Creating CSS for url: ${url}`);
                logInfo(`Custom theme ${custom ? 'was found' : 'was not found'}, Preset theme ${preset ? 'was found' : 'was not found'}
            The theme(${custom ? 'custom' : preset ? 'preset' : 'global'} settings) used is: ${JSON.stringify(theme)}`);
                switch (theme.engine) {
                    case ThemeEngine.cssFilter: {
                        return {
                            type: MessageTypeBGtoCS.ADD_CSS_FILTER,
                            data: {
                                css: createCSSFilterStyleSheet(theme, url, isTopFrame, ConfigManager.INVERSION_FIXES_RAW, ConfigManager.INVERSION_FIXES_INDEX),
                                detectDarkTheme,
                                detectorHints,
                                theme,
                            },
                        };
                    }
                    case ThemeEngine.svgFilter: {
                        return {
                            type: MessageTypeBGtoCS.ADD_SVG_FILTER,
                            data: {
                                css: createSVGFilterStylesheet(theme, url, isTopFrame, ConfigManager.INVERSION_FIXES_RAW, ConfigManager.INVERSION_FIXES_INDEX),
                                svgMatrix: getSVGFilterMatrixValue(theme),
                                svgReverseMatrix: getSVGReverseFilterMatrixValue(),
                                detectDarkTheme,
                                detectorHints,
                                theme,
                            },
                        };
                    }
                    case ThemeEngine.staticTheme: {
                        return {
                            type: MessageTypeBGtoCS.ADD_STATIC_THEME,
                            data: {
                                css: theme.stylesheet && theme.stylesheet.trim() ?
                                    theme.stylesheet :
                                    createStaticStylesheet(theme, url, isTopFrame, ConfigManager.STATIC_THEMES_RAW, ConfigManager.STATIC_THEMES_INDEX),
                                detectDarkTheme: settings.detectDarkTheme,
                                detectorHints,
                                theme,
                            },
                        };
                    }
                    case ThemeEngine.dynamicTheme: {
                        const fixes = getDynamicThemeFixesFor(url, isTopFrame, ConfigManager.DYNAMIC_THEME_FIXES_RAW, ConfigManager.DYNAMIC_THEME_FIXES_INDEX, UserStorage.settings.enableForPDF);
                        return {
                            type: MessageTypeBGtoCS.ADD_DYNAMIC_THEME,
                            data: {
                                theme,
                                fixes,
                                isIFrame: !isTopFrame,
                                detectDarkTheme,
                                detectorHints,
                            },
                        };
                    }
                    default:
                        throw new Error(`Unknown engine ${theme.engine}`);
                }
            }
            logInfo(`Site is not inverted: ${tabURL}`);
            return {
                type: MessageTypeBGtoCS.CLEAN_UP,
            };
        };
        //-------------------------------------
        //          User settings
        static async saveUserSettings() {
            await UserStorage.saveSettings();
            logInfo('saved', UserStorage.settings);
        }
    }

    // Start extension
    Extension.start();
    const welcome = `  /''''\\
 (0)==(0)
/__||||__\\
Welcome to Dark Reader!`;
    console.log(welcome);
    {
        chrome.runtime.onInstalled.addListener(async () => {
            Extension.isFirstLoad = true;
        });
        keepListeningToEvents();
    }
    function writeInstallationVersion(storage, details) {
        storage.get({ installation: { version: '' } }, (data) => {
            if (data?.installation?.version) {
                return;
            }
            storage.set({ installation: {
                    date: Date.now(),
                    reason: details.reason,
                    version: details.previousVersion ?? chrome.runtime.getManifest().version,
                } });
        });
    }
    chrome.runtime.onInstalled.addListener((details) => {
        writeInstallationVersion(chrome.storage.local, details);
        writeInstallationVersion(chrome.storage.sync, details);
    });

})();
//# sourceMappingURL=data:application/json;charset=utf-8;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiaW5kZXguanMiLCJzb3VyY2VzIjpbIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy91dGlscy9wbGF0Zm9ybS50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy91dGlscy90aW1lLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL3V0aWxzL2NhY2hlLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL3V0aWxzL3VybC50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy9iYWNrZ3JvdW5kL3V0aWxzL2V4dGVuc2lvbi1hcGkudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvdXRpbHMvbGlua3MudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvdXRpbHMvbWVkaWEtcXVlcnkudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvdXRpbHMvbWVzc2FnZS50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy91dGlscy90ZXh0LnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL2dlbmVyYXRvcnMvdGV4dC1zdHlsZS50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy91dGlscy9hcnJheS50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy9nZW5lcmF0b3JzL3V0aWxzL2Zvcm1hdC50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy91dGlscy9tYXRoLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL2dlbmVyYXRvcnMvdXRpbHMvbWF0cml4LnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL2dlbmVyYXRvcnMvdXRpbHMvcGFyc2UudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvZ2VuZXJhdG9ycy9jc3MtZmlsdGVyLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL2dlbmVyYXRvcnMvZGV0ZWN0b3ItaGludHMudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvdXRpbHMvY3NzLXRleHQvY3NzLXRleHQudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvdXRpbHMvY3NzLXRleHQvcGFyc2UtY3NzLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL3V0aWxzL2Nzcy10ZXh0L2Zvcm1hdC1jc3MudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvZ2VuZXJhdG9ycy9keW5hbWljLXRoZW1lLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL2dlbmVyYXRvcnMvc3RhdGljLXRoZW1lLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL2dlbmVyYXRvcnMvc3ZnLWZpbHRlci50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy9nZW5lcmF0b3JzL3RoZW1lLWVuZ2luZXMudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvdXRpbHMvYXV0b21hdGlvbi50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy91dGlscy9kZWJvdW5jZS50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy91dGlscy9wcm9taXNlLWJhcnJpZXIudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvdXRpbHMvc3RhdGUtbWFuYWdlci1pbXBsLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL3V0aWxzL3N0YXRlLW1hbmFnZXIudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvdXRpbHMvdGFicy50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy9kZWZhdWx0cy50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy91dGlscy9jb2xvcnNjaGVtZS1wYXJzZXIudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvdXRpbHMvdmFsaWRhdGlvbi50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy9iYWNrZ3JvdW5kL3V0aWxzL3NlbmRMb2cudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvYmFja2dyb3VuZC91dGlscy9sb2cudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvYmFja2dyb3VuZC91c2VyLXN0b3JhZ2UudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvdXRpbHMvbmV0d29yay50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy9iYWNrZ3JvdW5kL3V0aWxzL25ldHdvcmsudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvYmFja2dyb3VuZC9jb25maWctbWFuYWdlci50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy9iYWNrZ3JvdW5kL2RldnRvb2xzLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL2JhY2tncm91bmQvaWNvbi1tYW5hZ2VyLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL2JhY2tncm91bmQvbWVzc2VuZ2VyLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL2JhY2tncm91bmQvbmV3c21ha2VyLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL2JhY2tncm91bmQvdXRpbHMvdGFiLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL2JhY2tncm91bmQvdGFiLW1hbmFnZXIudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvYmFja2dyb3VuZC91aS1oaWdobGlnaHRzLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL3V0aWxzL21hdGgtZXZhbC50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy91dGlscy9jb2xvci50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy9pbmplY3QvZHluYW1pYy10aGVtZS9wYWxldHRlLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL2luamVjdC9keW5hbWljLXRoZW1lL21vZGlmeS1jb2xvcnMudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvYmFja2dyb3VuZC93aW5kb3ctdGhlbWUudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvYmFja2dyb3VuZC9leHRlbnNpb24udHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvYmFja2dyb3VuZC9pbmRleC50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJkZWNsYXJlIGNvbnN0IF9fQ0hST01JVU1fTVYyX186IGJvb2xlYW47XG5kZWNsYXJlIGNvbnN0IF9fQ0hST01JVU1fTVYzX186IGJvb2xlYW47XG5kZWNsYXJlIGNvbnN0IF9fRklSRUZPWF9NVjJfXzogYm9vbGVhbjtcbmRlY2xhcmUgY29uc3QgX19USFVOREVSQklSRF9fOiBib29sZWFuO1xuZGVjbGFyZSBjb25zdCBfX1RFU1RfXzogYm9vbGVhbjtcblxuaW50ZXJmYWNlIFVzZXJBZ2VudERhdGEge1xuICAgIGJyYW5kczogQXJyYXk8e1xuICAgICAgICBicmFuZDogc3RyaW5nO1xuICAgICAgICB2ZXJzaW9uOiBzdHJpbmc7XG4gICAgfT47XG4gICAgbW9iaWxlOiBib29sZWFuO1xuICAgIHBsYXRmb3JtOiBzdHJpbmc7XG59XG5cbmRlY2xhcmUgZ2xvYmFsIHtcbiAgICBpbnRlcmZhY2UgTmF2aWdhdG9ySUQge1xuICAgICAgICB1c2VyQWdlbnREYXRhOiBVc2VyQWdlbnREYXRhO1xuICAgIH1cbn1cblxuZGVjbGFyZSBjb25zdCBfX1BMVVNfXzogYm9vbGVhbjtcblxuY29uc3QgaXNOYXZpZ2F0b3JEZWZpbmVkID0gdHlwZW9mIG5hdmlnYXRvciAhPT0gJ3VuZGVmaW5lZCc7XG5jb25zdCB1c2VyQWdlbnQgPSBpc05hdmlnYXRvckRlZmluZWQgPyAobmF2aWdhdG9yLnVzZXJBZ2VudERhdGEgJiYgQXJyYXkuaXNBcnJheShuYXZpZ2F0b3IudXNlckFnZW50RGF0YS5icmFuZHMpKSA/XG4gICAgbmF2aWdhdG9yLnVzZXJBZ2VudERhdGEuYnJhbmRzLm1hcCgoYnJhbmQpID0+IGAke2JyYW5kLmJyYW5kLnRvTG93ZXJDYXNlKCl9ICR7YnJhbmQudmVyc2lvbn1gKS5qb2luKCcgJykgOiBuYXZpZ2F0b3IudXNlckFnZW50LnRvTG93ZXJDYXNlKClcbiAgICA6ICdzb21lIHVzZXJhZ2VudCc7XG5cbmNvbnN0IHBsYXRmb3JtID0gaXNOYXZpZ2F0b3JEZWZpbmVkID8gKG5hdmlnYXRvci51c2VyQWdlbnREYXRhICYmIHR5cGVvZiBuYXZpZ2F0b3IudXNlckFnZW50RGF0YS5wbGF0Zm9ybSA9PT0gJ3N0cmluZycpID9cbiAgICBuYXZpZ2F0b3IudXNlckFnZW50RGF0YS5wbGF0Zm9ybS50b0xvd2VyQ2FzZSgpIDogbmF2aWdhdG9yLnBsYXRmb3JtLnRvTG93ZXJDYXNlKClcbiAgICA6ICdzb21lIHBsYXRmb3JtJztcblxuLy8gTm90ZTogaWYgeW91IGFyZSB1c2luZyB0aGVzZSBjb25zdGFudHMgaW4gdGVzdHMsIG1ha2Ugc3VyZSB0aGV5IGFyZSBub3QgY29tcGlsZWQgb3V0IGJ5IGFkZGluZyBfX1RFU1RfXyB0byB0aGVtXG5leHBvcnQgY29uc3QgaXNDaHJvbWl1bSA9IF9fQ0hST01JVU1fTVYyX18gfHwgX19DSFJPTUlVTV9NVjNfXyB8fCAoIV9fRklSRUZPWF9NVjJfXyAmJiAhX19USFVOREVSQklSRF9fICYmICh1c2VyQWdlbnQuaW5jbHVkZXMoJ2Nocm9tZScpIHx8IHVzZXJBZ2VudC5pbmNsdWRlcygnY2hyb21pdW0nKSkpO1xuZXhwb3J0IGNvbnN0IGlzRmlyZWZveCA9IF9fRklSRUZPWF9NVjJfXyB8fCBfX1RIVU5ERVJCSVJEX18gfHwgKChfX1RFU1RfXyB8fCAoIV9fQ0hST01JVU1fTVYyX18gJiYgIV9fQ0hST01JVU1fTVYzX18pKSAmJiAodXNlckFnZW50LmluY2x1ZGVzKCdmaXJlZm94JykgfHwgdXNlckFnZW50LmluY2x1ZGVzKCd0aHVuZGVyYmlyZCcpIHx8IHVzZXJBZ2VudC5pbmNsdWRlcygnbGlicmV3b2xmJykpKTtcbmV4cG9ydCBjb25zdCBpc1ZpdmFsZGkgPSAoX19DSFJPTUlVTV9NVjJfXyB8fCBfX0NIUk9NSVVNX01WM19fKSAmJiAoIV9fRklSRUZPWF9NVjJfXyAmJiAhX19USFVOREVSQklSRF9fICYmIHVzZXJBZ2VudC5pbmNsdWRlcygndml2YWxkaScpKTtcbmV4cG9ydCBjb25zdCBpc1lhQnJvd3NlciA9IChfX0NIUk9NSVVNX01WMl9fIHx8IF9fQ0hST01JVU1fTVYzX18pICYmICghX19GSVJFRk9YX01WMl9fICYmICFfX1RIVU5ERVJCSVJEX18gJiYgdXNlckFnZW50LmluY2x1ZGVzKCd5YWJyb3dzZXInKSk7XG5leHBvcnQgY29uc3QgaXNPcGVyYSA9IChfX0NIUk9NSVVNX01WMl9fIHx8IF9fQ0hST01JVU1fTVYzX18pICYmICghX19GSVJFRk9YX01WMl9fICYmICFfX1RIVU5ERVJCSVJEX18gJiYgKHVzZXJBZ2VudC5pbmNsdWRlcygnb3ByJykgfHwgdXNlckFnZW50LmluY2x1ZGVzKCdvcGVyYScpKSk7XG5leHBvcnQgY29uc3QgaXNFZGdlID0gKF9fQ0hST01JVU1fTVYyX18gfHwgX19DSFJPTUlVTV9NVjNfXykgJiYgKCFfX0ZJUkVGT1hfTVYyX18gJiYgIV9fVEhVTkRFUkJJUkRfXyAmJiB1c2VyQWdlbnQuaW5jbHVkZXMoJ2VkZycpKTtcbmV4cG9ydCBjb25zdCBpc1NhZmFyaSA9ICFfX0NIUk9NSVVNX01WMl9fICYmICFfX0NIUk9NSVVNX01WM19fICYmICFfX0ZJUkVGT1hfTVYyX18gJiYgIV9fVEhVTkRFUkJJUkRfXyAmJiB1c2VyQWdlbnQuaW5jbHVkZXMoJ3NhZmFyaScpICYmICFpc0Nocm9taXVtO1xuZXhwb3J0IGNvbnN0IGlzV2luZG93cyA9IHBsYXRmb3JtLnN0YXJ0c1dpdGgoJ3dpbicpO1xuZXhwb3J0IGNvbnN0IGlzTWFjT1MgPSBwbGF0Zm9ybS5zdGFydHNXaXRoKCdtYWMnKTtcbmV4cG9ydCBjb25zdCBpc01vYmlsZSA9IChpc05hdmlnYXRvckRlZmluZWQgJiYgbmF2aWdhdG9yLnVzZXJBZ2VudERhdGEpID8gbmF2aWdhdG9yLnVzZXJBZ2VudERhdGEubW9iaWxlIDogKHVzZXJBZ2VudC5pbmNsdWRlcygnbW9iaWxlJykgfHwgKF9fUExVU19fICYmIHVzZXJBZ2VudC5pbmNsdWRlcygnZWRnaW9zJykpKTtcbmV4cG9ydCBjb25zdCBpc1NoYWRvd0RvbVN1cHBvcnRlZCA9IHR5cGVvZiBTaGFkb3dSb290ID09PSAnZnVuY3Rpb24nO1xuZXhwb3J0IGNvbnN0IGlzTWF0Y2hNZWRpYUNoYW5nZUV2ZW50TGlzdGVuZXJTdXBwb3J0ZWQgPSBfX0NIUk9NSVVNX01WM19fIHx8IChcbiAgICB0eXBlb2YgTWVkaWFRdWVyeUxpc3QgPT09ICdmdW5jdGlvbicgJiZcbiAgICB0eXBlb2YgTWVkaWFRdWVyeUxpc3QucHJvdG90eXBlLmFkZEV2ZW50TGlzdGVuZXIgPT09ICdmdW5jdGlvbidcbik7XG5leHBvcnQgY29uc3QgaXNMYXllclJ1bGVTdXBwb3J0ZWQgPSB0eXBlb2YgQ1NTTGF5ZXJCbG9ja1J1bGUgPT09ICdmdW5jdGlvbic7XG4vLyBSZXR1cm4gdHJ1ZSBpZiBicm93c2VyIGlzIGtub3duIHRvIGhhdmUgYSBidWcgd2l0aCBNZWRpYSBRdWVyaWVzLCBzcGVjaWZpY2FsbHkgQ2hyb21pdW0gb24gTGludXggYW5kIEtpd2kgb24gQW5kcm9pZFxuLy8gV2UgYXNzdW1lIHRoYXQgaWYgd2UgYXJlIG9uIEFuZHJvaWQsIHRoZW4gd2UgYXJlIHJ1bm5pbmcgaW4gS2l3aSBzaW5jZSBpdCBpcyB0aGUgb25seSBtb2JpbGUgYnJvd3NlciB3ZSBjYW4gaW5zdGFsbCBEYXJrIFJlYWRlciBpblxuZXhwb3J0IGNvbnN0IGlzTWF0Y2hNZWRpYUNoYW5nZUV2ZW50TGlzdGVuZXJCdWdneSA9ICFfX1RFU1RfXyAmJiAhX19GSVJFRk9YX01WMl9fICYmICFfX1RIVU5ERVJCSVJEX18gJiYgKF9fQ0hST01JVU1fTVYyX18gfHwgX19DSFJPTUlVTV9NVjNfXykgJiYgKFxuICAgICgoaXNOYXZpZ2F0b3JEZWZpbmVkICYmIG5hdmlnYXRvci51c2VyQWdlbnREYXRhKSAmJiBbJ0xpbnV4JywgJ0FuZHJvaWQnXS5pbmNsdWRlcyhuYXZpZ2F0b3IudXNlckFnZW50RGF0YS5wbGF0Zm9ybSkpXG4gICAgfHwgcGxhdGZvcm0uc3RhcnRzV2l0aCgnbGludXgnKSk7XG4vLyBOb3RlOiBtYWtlIHN1cmUgdGhhdCB0aGlzIHZhbHVlIG1hdGNoZXMgbWFuaWZlc3QuanNvbiBrZXlzXG5leHBvcnQgY29uc3QgaXNOb25QZXJzaXN0ZW50ID0gIV9fRklSRUZPWF9NVjJfXyAmJiAhX19USFVOREVSQklSRF9fICYmIChfX0NIUk9NSVVNX01WM19fIHx8IGlzU2FmYXJpKTtcblxuZXhwb3J0IGNvbnN0IGNocm9taXVtVmVyc2lvbiA9ICgoKSA9PiB7XG4gICAgY29uc3QgbSA9IHVzZXJBZ2VudC5tYXRjaCgvY2hyb20oPzplfGl1bSkoPzpcXC98ICkoW14gXSspLyk7XG4gICAgaWYgKG0gJiYgbVsxXSkge1xuICAgICAgICByZXR1cm4gbVsxXTtcbiAgICB9XG4gICAgcmV0dXJuICcnO1xufSkoKTtcblxuZXhwb3J0IGNvbnN0IGZpcmVmb3hWZXJzaW9uID0gKCgpID0+IHtcbiAgICBjb25zdCBtID0gdXNlckFnZW50Lm1hdGNoKC8oPzpmaXJlZm94fGxpYnJld29sZikoPzpcXC98ICkoW14gXSspLyk7XG4gICAgaWYgKG0gJiYgbVsxXSkge1xuICAgICAgICByZXR1cm4gbVsxXTtcbiAgICB9XG4gICAgcmV0dXJuICcnO1xufSkoKTtcblxuZXhwb3J0IGNvbnN0IGlzRGVmaW5lZFNlbGVjdG9yU3VwcG9ydGVkID0gKCgpID0+IHtcbiAgICB0cnkge1xuICAgICAgICBkb2N1bWVudC5xdWVyeVNlbGVjdG9yKCc6ZGVmaW5lZCcpO1xuICAgICAgICByZXR1cm4gdHJ1ZTtcbiAgICB9IGNhdGNoIChlcnIpIHtcbiAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgIH1cbn0pKCk7XG5cbmV4cG9ydCBmdW5jdGlvbiBjb21wYXJlQ2hyb21lVmVyc2lvbnMoJGE6IHN0cmluZywgJGI6IHN0cmluZyk6IC0xIHwgMCB8IDEge1xuICAgIGNvbnN0IGEgPSAkYS5zcGxpdCgnLicpLm1hcCgoeCkgPT4gcGFyc2VJbnQoeCkpO1xuICAgIGNvbnN0IGIgPSAkYi5zcGxpdCgnLicpLm1hcCgoeCkgPT4gcGFyc2VJbnQoeCkpO1xuICAgIGZvciAobGV0IGkgPSAwOyBpIDwgYS5sZW5ndGg7IGkrKykge1xuICAgICAgICBpZiAoYVtpXSAhPT0gYltpXSkge1xuICAgICAgICAgICAgcmV0dXJuIGFbaV0gPCBiW2ldID8gLTEgOiAxO1xuICAgICAgICB9XG4gICAgfVxuICAgIHJldHVybiAwO1xufVxuXG5leHBvcnQgY29uc3QgaXNYTUxIdHRwUmVxdWVzdFN1cHBvcnRlZCA9IHR5cGVvZiBYTUxIdHRwUmVxdWVzdCA9PT0gJ2Z1bmN0aW9uJztcblxuZXhwb3J0IGNvbnN0IGlzRmV0Y2hTdXBwb3J0ZWQgPSB0eXBlb2YgZmV0Y2ggPT09ICdmdW5jdGlvbic7XG5cbmV4cG9ydCBjb25zdCBpc0NTU0NvbG9yU2NoZW1lUHJvcFN1cHBvcnRlZCA9IF9fQ0hST01JVU1fTVYzX18gfHwgKCgpID0+IHtcbiAgICB0cnkge1xuICAgICAgICBpZiAodHlwZW9mIGRvY3VtZW50ID09PSAndW5kZWZpbmVkJykge1xuICAgICAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgICAgICB9XG4gICAgICAgIGNvbnN0IGVsID0gZG9jdW1lbnQuY3JlYXRlRWxlbWVudCgnZGl2Jyk7XG4gICAgICAgIGlmICghZWwgfHwgdHlwZW9mIGVsLnN0eWxlICE9PSAnb2JqZWN0Jykge1xuICAgICAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgICAgICB9XG4gICAgICAgIGlmICh0eXBlb2YgZWwuc3R5bGUuY29sb3JTY2hlbWUgPT09ICdzdHJpbmcnKSB7XG4gICAgICAgICAgICByZXR1cm4gdHJ1ZTtcbiAgICAgICAgfVxuXG4gICAgICAgIC8vIFRPRE86IHJlbW92ZSB0aGUgZm9sbG93aW5nIGNvZGUgYWZ0ZXIgZW5mb3JjaW5nIHN0cm9uZyBDU1AgaW4gYWxsIGJ1aWxkc1xuICAgICAgICAvLyBUaGlzIGZlYXR1cmUgZGV0ZWN0aW9uIG1ldGhvZCByZXF1aXJlcyB3ZWFrIG9yIG1pc3NpbmcgQ1NQIGluIG1hbmlmZXN0Lmpzb25cbiAgICAgICAgZWwuc2V0QXR0cmlidXRlKCdzdHlsZScsICdjb2xvci1zY2hlbWU6IGRhcmsnKTtcbiAgICAgICAgcmV0dXJuIGVsLnN0eWxlLmNvbG9yU2NoZW1lID09PSAnZGFyayc7XG4gICAgfSBjYXRjaCAoZSkge1xuICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgfVxufSkoKTtcbiIsImV4cG9ydCBmdW5jdGlvbiBwYXJzZVRpbWUoJHRpbWU6IHN0cmluZyk6IFtudW1iZXIsIG51bWJlcl0ge1xuICAgIGNvbnN0IHBhcnRzID0gJHRpbWUuc3BsaXQoJzonKS5zbGljZSgwLCAyKTtcbiAgICBjb25zdCBsb3dlcmNhc2VkID0gJHRpbWUudHJpbSgpLnRvTG93ZXJDYXNlKCk7XG4gICAgY29uc3QgaXNBTSA9IGxvd2VyY2FzZWQuZW5kc1dpdGgoJ2FtJykgfHwgbG93ZXJjYXNlZC5lbmRzV2l0aCgnYS5tLicpO1xuICAgIGNvbnN0IGlzUE0gPSBsb3dlcmNhc2VkLmVuZHNXaXRoKCdwbScpIHx8IGxvd2VyY2FzZWQuZW5kc1dpdGgoJ3AubS4nKTtcblxuICAgIGxldCBob3VycyA9IHBhcnRzLmxlbmd0aCA+IDAgPyBwYXJzZUludChwYXJ0c1swXSkgOiAwO1xuICAgIGlmIChpc05hTihob3VycykgfHwgaG91cnMgPiAyMykge1xuICAgICAgICBob3VycyA9IDA7XG4gICAgfVxuICAgIGlmIChpc0FNICYmIGhvdXJzID09PSAxMikge1xuICAgICAgICBob3VycyA9IDA7XG4gICAgfVxuICAgIGlmIChpc1BNICYmIGhvdXJzIDwgMTIpIHtcbiAgICAgICAgaG91cnMgKz0gMTI7XG4gICAgfVxuXG4gICAgbGV0IG1pbnV0ZXMgPSBwYXJ0cy5sZW5ndGggPiAxID8gcGFyc2VJbnQocGFydHNbMV0pIDogMDtcbiAgICBpZiAoaXNOYU4obWludXRlcykgfHwgbWludXRlcyA+IDU5KSB7XG4gICAgICAgIG1pbnV0ZXMgPSAwO1xuICAgIH1cblxuICAgIHJldHVybiBbaG91cnMsIG1pbnV0ZXNdO1xufVxuXG5mdW5jdGlvbiBwYXJzZTI0SFRpbWUodGltZTogc3RyaW5nKTogbnVtYmVyW10ge1xuICAgIHJldHVybiB0aW1lLnNwbGl0KCc6JykubWFwKCh4KSA9PiBwYXJzZUludCh4KSk7XG59XG5cbmZ1bmN0aW9uIGNvbXBhcmVUaW1lKHRpbWUxOiBudW1iZXJbXSwgdGltZTI6IG51bWJlcltdKTogLTEgfCAwIHwgMSB7XG4gICAgaWYgKHRpbWUxWzBdID09PSB0aW1lMlswXSAmJiB0aW1lMVsxXSA9PT0gdGltZTJbMV0pIHtcbiAgICAgICAgcmV0dXJuIDA7XG4gICAgfVxuICAgIGlmICh0aW1lMVswXSA8IHRpbWUyWzBdIHx8ICh0aW1lMVswXSA9PT0gdGltZTJbMF0gJiYgdGltZTFbMV0gPCB0aW1lMlsxXSkpIHtcbiAgICAgICAgcmV0dXJuIC0xO1xuICAgIH1cbiAgICByZXR1cm4gMTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIG5leHRUaW1lSW50ZXJ2YWwodGltZTA6IHN0cmluZywgdGltZTE6IHN0cmluZywgZGF0ZTogRGF0ZSA9IG5ldyBEYXRlKCkpOiBudW1iZXIgfCBudWxsIHtcbiAgICBjb25zdCBhID0gcGFyc2UyNEhUaW1lKHRpbWUwKTtcbiAgICBjb25zdCBiID0gcGFyc2UyNEhUaW1lKHRpbWUxKTtcbiAgICBjb25zdCB0ID0gW2RhdGUuZ2V0SG91cnMoKSwgZGF0ZS5nZXRNaW51dGVzKCldO1xuXG4gICAgLy8gRW5zdXJlIGEgPD0gYlxuICAgIGlmIChjb21wYXJlVGltZShhLCBiKSA+IDApIHtcbiAgICAgICAgcmV0dXJuIG5leHRUaW1lSW50ZXJ2YWwodGltZTEsIHRpbWUwLCBkYXRlKTtcbiAgICB9XG5cbiAgICBpZiAoY29tcGFyZVRpbWUoYSwgYikgPT09IDApIHtcbiAgICAgICAgcmV0dXJuIG51bGw7XG4gICAgfVxuXG4gICAgaWYgKGNvbXBhcmVUaW1lKHQsIGEpIDwgMCkge1xuICAgICAgICAvLyB0IDwgYSA8PSBiXG4gICAgICAgIC8vIFNjaGVkdWxlIGZvciB0b2RhdGUgYXQgdGltZSBhXG4gICAgICAgIGRhdGUuc2V0SG91cnMoYVswXSk7XG4gICAgICAgIGRhdGUuc2V0TWludXRlcyhhWzFdKTtcbiAgICAgICAgZGF0ZS5zZXRTZWNvbmRzKDApO1xuICAgICAgICBkYXRlLnNldE1pbGxpc2Vjb25kcygwKTtcbiAgICAgICAgcmV0dXJuIGRhdGUuZ2V0VGltZSgpO1xuICAgIH1cblxuICAgIGlmIChjb21wYXJlVGltZSh0LCBiKSA8IDApIHtcbiAgICAgICAgLy8gYSA8PSB0IDwgYlxuICAgICAgICAvLyBTY2hlZHVsZSBmb3IgdG9kYXkgYXQgdGltZSBiXG4gICAgICAgIGRhdGUuc2V0SG91cnMoYlswXSk7XG4gICAgICAgIGRhdGUuc2V0TWludXRlcyhiWzFdKTtcbiAgICAgICAgZGF0ZS5zZXRTZWNvbmRzKDApO1xuICAgICAgICBkYXRlLnNldE1pbGxpc2Vjb25kcygwKTtcbiAgICAgICAgcmV0dXJuIGRhdGUuZ2V0VGltZSgpO1xuICAgIH1cblxuICAgIC8vIGEgPD0gYiA8PSB0XG4gICAgLy8gU2NoZWR1bGUgZm9yIHRvbW9ycm93IGF0IHRpbWUgYVxuICAgIHJldHVybiAobmV3IERhdGUoZGF0ZS5nZXRGdWxsWWVhcigpLCBkYXRlLmdldE1vbnRoKCksIGRhdGUuZ2V0RGF0ZSgpICsgMSwgYVswXSwgYVsxXSkpLmdldFRpbWUoKTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGlzSW5UaW1lSW50ZXJ2YWxMb2NhbCh0aW1lMDogc3RyaW5nLCB0aW1lMTogc3RyaW5nLCBkYXRlOiBEYXRlID0gbmV3IERhdGUoKSk6IGJvb2xlYW4ge1xuICAgIGNvbnN0IGEgPSBwYXJzZTI0SFRpbWUodGltZTApO1xuICAgIGNvbnN0IGIgPSBwYXJzZTI0SFRpbWUodGltZTEpO1xuICAgIGNvbnN0IHQgPSBbZGF0ZS5nZXRIb3VycygpLCBkYXRlLmdldE1pbnV0ZXMoKV07XG4gICAgaWYgKGNvbXBhcmVUaW1lKGEsIGIpID4gMCkge1xuICAgICAgICByZXR1cm4gY29tcGFyZVRpbWUoYSwgdCkgPD0gMCB8fCBjb21wYXJlVGltZSh0LCBiKSA8IDA7XG4gICAgfVxuICAgIHJldHVybiBjb21wYXJlVGltZShhLCB0KSA8PSAwICYmIGNvbXBhcmVUaW1lKHQsIGIpIDwgMDtcbn1cblxuZnVuY3Rpb24gaXNJblRpbWVJbnRlcnZhbFVUQyh0aW1lMDogbnVtYmVyLCB0aW1lMTogbnVtYmVyLCB0aW1lc3RhbXA6IG51bWJlcik6IGJvb2xlYW4ge1xuICAgIGlmICh0aW1lMSA8IHRpbWUwKSB7XG4gICAgICAgIHJldHVybiB0aW1lc3RhbXAgPD0gdGltZTEgfHwgdGltZTAgPD0gdGltZXN0YW1wO1xuICAgIH1cbiAgICByZXR1cm4gdGltZTAgPCB0aW1lc3RhbXAgJiYgdGltZXN0YW1wIDwgdGltZTE7XG59XG5cbmludGVyZmFjZSBEdXJhdGlvbiB7XG4gICAgZGF5cz86IG51bWJlcjtcbiAgICBob3Vycz86IG51bWJlcjtcbiAgICBtaW51dGVzPzogbnVtYmVyO1xuICAgIHNlY29uZHM/OiBudW1iZXI7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBnZXREdXJhdGlvbih0aW1lOiBEdXJhdGlvbik6IG51bWJlciB7XG4gICAgbGV0IGR1cmF0aW9uID0gMDtcbiAgICBpZiAodGltZS5zZWNvbmRzKSB7XG4gICAgICAgIGR1cmF0aW9uICs9IHRpbWUuc2Vjb25kcyAqIDEwMDA7XG4gICAgfVxuICAgIGlmICh0aW1lLm1pbnV0ZXMpIHtcbiAgICAgICAgZHVyYXRpb24gKz0gdGltZS5taW51dGVzICogNjAgKiAxMDAwO1xuICAgIH1cbiAgICBpZiAodGltZS5ob3Vycykge1xuICAgICAgICBkdXJhdGlvbiArPSB0aW1lLmhvdXJzICogNjAgKiA2MCAqIDEwMDA7XG4gICAgfVxuICAgIGlmICh0aW1lLmRheXMpIHtcbiAgICAgICAgZHVyYXRpb24gKz0gdGltZS5kYXlzICogMjQgKiA2MCAqIDYwICogMTAwMDtcbiAgICB9XG4gICAgcmV0dXJuIGR1cmF0aW9uO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gZ2V0RHVyYXRpb25Jbk1pbnV0ZXModGltZTogRHVyYXRpb24pOiBudW1iZXIge1xuICAgIHJldHVybiBnZXREdXJhdGlvbih0aW1lKSAvIDEwMDAgLyA2MDtcbn1cblxuZnVuY3Rpb24gZ2V0U3Vuc2V0U3VucmlzZVVUQ1RpbWUoXG4gICAgbGF0aXR1ZGU6IG51bWJlcixcbiAgICBsb25naXR1ZGU6IG51bWJlcixcbiAgICBkYXRlOiBEYXRlLFxuKSB7XG4gICAgY29uc3QgZGVjMzEgPSBEYXRlLlVUQyhkYXRlLmdldFVUQ0Z1bGxZZWFyKCksIDAsIDAsIDAsIDAsIDAsIDApO1xuICAgIGNvbnN0IG9uZURheSA9IGdldER1cmF0aW9uKHtkYXlzOiAxfSk7XG4gICAgY29uc3QgZGF5T2ZZZWFyID0gTWF0aC5mbG9vcigoZGF0ZS5nZXRUaW1lKCkgLSBkZWMzMSkgLyBvbmVEYXkpO1xuXG4gICAgY29uc3QgemVuaXRoID0gOTAuODMzMzMzMzMzMzMzMzM7XG4gICAgY29uc3QgRDJSID0gTWF0aC5QSSAvIDE4MDtcbiAgICBjb25zdCBSMkQgPSAxODAgLyBNYXRoLlBJO1xuXG4gICAgLy8gY29udmVydCB0aGUgbG9uZ2l0dWRlIHRvIGhvdXIgdmFsdWUgYW5kIGNhbGN1bGF0ZSBhbiBhcHByb3hpbWF0ZSB0aW1lXG4gICAgY29uc3QgbG5Ib3VyID0gbG9uZ2l0dWRlIC8gMTU7XG5cbiAgICBmdW5jdGlvbiBnZXRUaW1lKGlzU3VucmlzZTogYm9vbGVhbikge1xuICAgICAgICBjb25zdCB0ID0gZGF5T2ZZZWFyICsgKCgoaXNTdW5yaXNlID8gNiA6IDE4KSAtIGxuSG91cikgLyAyNCk7XG5cbiAgICAgICAgLy8gY2FsY3VsYXRlIHRoZSBTdW4ncyBtZWFuIGFub21hbHlcbiAgICAgICAgY29uc3QgTSA9ICgwLjk4NTYgKiB0KSAtIDMuMjg5O1xuXG4gICAgICAgIC8vIGNhbGN1bGF0ZSB0aGUgU3VuJ3MgdHJ1ZSBsb25naXR1ZGVcbiAgICAgICAgbGV0IEwgPSBNICsgKDEuOTE2ICogTWF0aC5zaW4oTSAqIEQyUikpICsgKDAuMDIwICogTWF0aC5zaW4oMiAqIE0gKiBEMlIpKSArIDI4Mi42MzQ7XG4gICAgICAgIGlmIChMID4gMzYwKSB7XG4gICAgICAgICAgICBMIC09IDM2MDtcbiAgICAgICAgfSBlbHNlIGlmIChMIDwgMCkge1xuICAgICAgICAgICAgTCArPSAzNjA7XG4gICAgICAgIH1cblxuICAgICAgICAvLyBjYWxjdWxhdGUgdGhlIFN1bidzIHJpZ2h0IGFzY2Vuc2lvblxuICAgICAgICBsZXQgUkEgPSBSMkQgKiBNYXRoLmF0YW4oMC45MTc2NCAqIE1hdGgudGFuKEwgKiBEMlIpKTtcbiAgICAgICAgaWYgKFJBID4gMzYwKSB7XG4gICAgICAgICAgICBSQSAtPSAzNjA7XG4gICAgICAgIH0gZWxzZSBpZiAoUkEgPCAwKSB7XG4gICAgICAgICAgICBSQSArPSAzNjA7XG4gICAgICAgIH1cblxuICAgICAgICAvLyByaWdodCBhc2NlbnNpb24gdmFsdWUgbmVlZHMgdG8gYmUgaW4gdGhlIHNhbWUgcXVhXG4gICAgICAgIGNvbnN0IExxdWFkcmFudCA9IChNYXRoLmZsb29yKEwgLyAoOTApKSkgKiA5MDtcbiAgICAgICAgY29uc3QgUkFxdWFkcmFudCA9IChNYXRoLmZsb29yKFJBIC8gOTApKSAqIDkwO1xuICAgICAgICBSQSArPSAoTHF1YWRyYW50IC0gUkFxdWFkcmFudCk7XG5cbiAgICAgICAgLy8gcmlnaHQgYXNjZW5zaW9uIHZhbHVlIG5lZWRzIHRvIGJlIGNvbnZlcnRlZCBpbnRvIGhvdXJzXG4gICAgICAgIFJBIC89IDE1O1xuXG4gICAgICAgIC8vIGNhbGN1bGF0ZSB0aGUgU3VuJ3MgZGVjbGluYXRpb25cbiAgICAgICAgY29uc3Qgc2luRGVjID0gMC4zOTc4MiAqIE1hdGguc2luKEwgKiBEMlIpO1xuICAgICAgICBjb25zdCBjb3NEZWMgPSBNYXRoLmNvcyhNYXRoLmFzaW4oc2luRGVjKSk7XG5cbiAgICAgICAgLy8gY2FsY3VsYXRlIHRoZSBTdW4ncyBsb2NhbCBob3VyIGFuZ2xlXG4gICAgICAgIGNvbnN0IGNvc0ggPSAoTWF0aC5jb3MoemVuaXRoICogRDJSKSAtIChzaW5EZWMgKiBNYXRoLnNpbihsYXRpdHVkZSAqIEQyUikpKSAvIChjb3NEZWMgKiBNYXRoLmNvcyhsYXRpdHVkZSAqIEQyUikpO1xuICAgICAgICBpZiAoY29zSCA+IDEpIHtcbiAgICAgICAgICAgIC8vIGFsd2F5cyBuaWdodFxuICAgICAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICAgICAgICBhbHdheXNEYXk6IGZhbHNlLFxuICAgICAgICAgICAgICAgIGFsd2F5c05pZ2h0OiB0cnVlLFxuICAgICAgICAgICAgICAgIHRpbWU6IDAsXG4gICAgICAgICAgICB9O1xuICAgICAgICB9IGVsc2UgaWYgKGNvc0ggPCAtMSkge1xuICAgICAgICAgICAgLy8gYWx3YXlzIGRheVxuICAgICAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICAgICAgICBhbHdheXNEYXk6IHRydWUsXG4gICAgICAgICAgICAgICAgYWx3YXlzTmlnaHQ6IGZhbHNlLFxuICAgICAgICAgICAgICAgIHRpbWU6IDAsXG4gICAgICAgICAgICB9O1xuICAgICAgICB9XG5cbiAgICAgICAgY29uc3QgSCA9IChpc1N1bnJpc2UgPyAoMzYwIC0gUjJEICogTWF0aC5hY29zKGNvc0gpKSA6IChSMkQgKiBNYXRoLmFjb3MoY29zSCkpKSAvIDE1O1xuXG4gICAgICAgIC8vIGNhbGN1bGF0ZSBsb2NhbCBtZWFuIHRpbWUgb2YgcmlzaW5nL3NldHRpbmdcbiAgICAgICAgY29uc3QgVCA9IEggKyBSQSAtICgwLjA2NTcxICogdCkgLSA2LjYyMjtcblxuICAgICAgICAvLyBhZGp1c3QgYmFjayB0byBVVENcbiAgICAgICAgbGV0IFVUID0gVCAtIGxuSG91cjtcbiAgICAgICAgaWYgKFVUID4gMjQpIHtcbiAgICAgICAgICAgIFVUIC09IDI0O1xuICAgICAgICB9IGVsc2UgaWYgKFVUIDwgMCkge1xuICAgICAgICAgICAgVVQgKz0gMjQ7XG4gICAgICAgIH1cblxuICAgICAgICAvLyBjb252ZXJ0IHRvIG1pbGxpc2Vjb25kc1xuICAgICAgICByZXR1cm4ge1xuICAgICAgICAgICAgYWx3YXlzRGF5OiBmYWxzZSxcbiAgICAgICAgICAgIGFsd2F5c05pZ2h0OiBmYWxzZSxcbiAgICAgICAgICAgIHRpbWU6IE1hdGgucm91bmQoVVQgKiBnZXREdXJhdGlvbih7aG91cnM6IDF9KSksXG4gICAgICAgIH07XG4gICAgfVxuXG4gICAgY29uc3Qgc3VucmlzZVRpbWUgPSBnZXRUaW1lKHRydWUpO1xuICAgIGNvbnN0IHN1bnNldFRpbWUgPSBnZXRUaW1lKGZhbHNlKTtcblxuICAgIGlmIChzdW5yaXNlVGltZS5hbHdheXNEYXkgfHwgc3Vuc2V0VGltZS5hbHdheXNEYXkpIHtcbiAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICAgIGFsd2F5c0RheTogdHJ1ZSxcbiAgICAgICAgICAgIGFsd2F5c05pZ2h0OiBmYWxzZSxcbiAgICAgICAgICAgIHN1bnJpc2VUaW1lOiAwLFxuICAgICAgICAgICAgc3Vuc2V0VGltZTogMCxcbiAgICAgICAgfTtcbiAgICB9IGVsc2UgaWYgKHN1bnJpc2VUaW1lLmFsd2F5c05pZ2h0IHx8IHN1bnNldFRpbWUuYWx3YXlzTmlnaHQpIHtcbiAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICAgIGFsd2F5c0RheTogZmFsc2UsXG4gICAgICAgICAgICBhbHdheXNOaWdodDogdHJ1ZSxcbiAgICAgICAgICAgIHN1bnJpc2VUaW1lOiAwLFxuICAgICAgICAgICAgc3Vuc2V0VGltZTogMCxcbiAgICAgICAgfTtcbiAgICB9XG5cbiAgICByZXR1cm4ge1xuICAgICAgICBhbHdheXNEYXk6IGZhbHNlLFxuICAgICAgICBhbHdheXNOaWdodDogZmFsc2UsXG4gICAgICAgIHN1bnJpc2VUaW1lOiBzdW5yaXNlVGltZS50aW1lLFxuICAgICAgICBzdW5zZXRUaW1lOiBzdW5zZXRUaW1lLnRpbWUsXG4gICAgfTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGlzTmlnaHRBdExvY2F0aW9uKFxuICAgIGxhdGl0dWRlOiBudW1iZXIsXG4gICAgbG9uZ2l0dWRlOiBudW1iZXIsXG4gICAgZGF0ZTogRGF0ZSA9IG5ldyBEYXRlKCksXG4pOiBib29sZWFuIHtcbiAgICBjb25zdCB0aW1lID0gZ2V0U3Vuc2V0U3VucmlzZVVUQ1RpbWUobGF0aXR1ZGUsIGxvbmdpdHVkZSwgZGF0ZSk7XG5cbiAgICBpZiAodGltZS5hbHdheXNEYXkpIHtcbiAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgIH0gZWxzZSBpZiAodGltZS5hbHdheXNOaWdodCkge1xuICAgICAgICByZXR1cm4gdHJ1ZTtcbiAgICB9XG5cbiAgICBjb25zdCBzdW5yaXNlVGltZSA9IHRpbWUuc3VucmlzZVRpbWU7XG4gICAgY29uc3Qgc3Vuc2V0VGltZSA9IHRpbWUuc3Vuc2V0VGltZTtcbiAgICBjb25zdCBjdXJyZW50VGltZSA9IChcbiAgICAgICAgZGF0ZS5nZXRVVENIb3VycygpICogZ2V0RHVyYXRpb24oe2hvdXJzOiAxfSkgK1xuICAgICAgICBkYXRlLmdldFVUQ01pbnV0ZXMoKSAqIGdldER1cmF0aW9uKHttaW51dGVzOiAxfSkgK1xuICAgICAgICBkYXRlLmdldFVUQ1NlY29uZHMoKSAqIGdldER1cmF0aW9uKHtzZWNvbmRzOiAxfSkgK1xuICAgICAgICBkYXRlLmdldFVUQ01pbGxpc2Vjb25kcygpXG4gICAgKTtcblxuICAgIHJldHVybiBpc0luVGltZUludGVydmFsVVRDKHN1bnNldFRpbWUsIHN1bnJpc2VUaW1lLCBjdXJyZW50VGltZSk7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBuZXh0VGltZUNoYW5nZUF0TG9jYXRpb24oXG4gICAgbGF0aXR1ZGU6IG51bWJlcixcbiAgICBsb25naXR1ZGU6IG51bWJlcixcbiAgICBkYXRlOiBEYXRlID0gbmV3IERhdGUoKSxcbik6IG51bWJlciB7XG4gICAgY29uc3QgdGltZSA9IGdldFN1bnNldFN1bnJpc2VVVENUaW1lKGxhdGl0dWRlLCBsb25naXR1ZGUsIGRhdGUpO1xuXG4gICAgaWYgKHRpbWUuYWx3YXlzRGF5KSB7XG4gICAgICAgIHJldHVybiBkYXRlLmdldFRpbWUoKSArIGdldER1cmF0aW9uKHtkYXlzOiAxfSk7XG4gICAgfSBlbHNlIGlmICh0aW1lLmFsd2F5c05pZ2h0KSB7XG4gICAgICAgIHJldHVybiBkYXRlLmdldFRpbWUoKSArIGdldER1cmF0aW9uKHtkYXlzOiAxfSk7XG4gICAgfVxuXG4gICAgY29uc3QgW2ZpcnN0VGltZU9uRGF5LCBsYXN0VGltZU9uRGF5XSA9IHRpbWUuc3VucmlzZVRpbWUgPCB0aW1lLnN1bnNldFRpbWUgPyBbdGltZS5zdW5yaXNlVGltZSwgdGltZS5zdW5zZXRUaW1lXSA6IFt0aW1lLnN1bnNldFRpbWUsIHRpbWUuc3VucmlzZVRpbWVdO1xuICAgIGNvbnN0IGN1cnJlbnRUaW1lID0gKFxuICAgICAgICBkYXRlLmdldFVUQ0hvdXJzKCkgKiBnZXREdXJhdGlvbih7aG91cnM6IDF9KSArXG4gICAgICAgIGRhdGUuZ2V0VVRDTWludXRlcygpICogZ2V0RHVyYXRpb24oe21pbnV0ZXM6IDF9KSArXG4gICAgICAgIGRhdGUuZ2V0VVRDU2Vjb25kcygpICogZ2V0RHVyYXRpb24oe3NlY29uZHM6IDF9KSArXG4gICAgICAgIGRhdGUuZ2V0VVRDTWlsbGlzZWNvbmRzKClcbiAgICApO1xuXG4gICAgaWYgKGN1cnJlbnRUaW1lIDw9IGZpcnN0VGltZU9uRGF5ISkge1xuICAgICAgICAvLyBUaW1lbGluZTpcbiAgICAgICAgLy8gLS0tIGZpcnN0VGltZU9uRGF5IDwtLS0+IGxhc3RUaW1lT25EYXkgLS0tXG4gICAgICAgIC8vICBeXG4gICAgICAgIC8vIEN1cnJlbnQgdGltZVxuICAgICAgICByZXR1cm4gRGF0ZS5VVEMoZGF0ZS5nZXRVVENGdWxsWWVhcigpLCBkYXRlLmdldFVUQ01vbnRoKCksIGRhdGUuZ2V0VVRDRGF0ZSgpLCAwLCAwLCAwLCBmaXJzdFRpbWVPbkRheSk7XG4gICAgfVxuICAgIGlmIChjdXJyZW50VGltZSA8PSBsYXN0VGltZU9uRGF5ISkge1xuICAgICAgICAvLyBUaW1lbGluZTpcbiAgICAgICAgLy8gLS0tIGZpcnN0VGltZU9uRGF5IDwtLS0+IGxhc3RUaW1lT25EYXkgLS0tXG4gICAgICAgIC8vICAgICAgICAgICAgICAgICAgICAgIF5cbiAgICAgICAgLy8gICAgICAgICAgICAgICAgIEN1cnJlbnQgdGltZVxuICAgICAgICByZXR1cm4gRGF0ZS5VVEMoZGF0ZS5nZXRVVENGdWxsWWVhcigpLCBkYXRlLmdldFVUQ01vbnRoKCksIGRhdGUuZ2V0VVRDRGF0ZSgpLCAwLCAwLCAwLCBsYXN0VGltZU9uRGF5KTtcbiAgICB9XG4gICAgLy8gVGltZWxpbmU6XG4gICAgLy8gLS0tIGZpcnN0VGltZU9uRGF5IDwtLS0+IGxhc3RUaW1lT25EYXkgLS0tXG4gICAgLy8gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIF5cbiAgICAvLyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEN1cnJlbnQgdGltZVxuICAgIHJldHVybiBEYXRlLlVUQyhkYXRlLmdldFVUQ0Z1bGxZZWFyKCksIGRhdGUuZ2V0VVRDTW9udGgoKSwgZGF0ZS5nZXRVVENEYXRlKCkgKyAxLCAwLCAwLCAwLCBmaXJzdFRpbWVPbkRheSk7XG59XG4iLCJleHBvcnQgZnVuY3Rpb24gY2FjaGVkRmFjdG9yeTxLLCBWPihmYWN0b3J5OiAoa2V5OiBLKSA9PiBWLCBzaXplOiBudW1iZXIpOiAoa2V5OiBLKSA9PiBWIHtcbiAgICBjb25zdCBjYWNoZSA9IG5ldyBNYXA8SywgVj4oKTtcblxuICAgIHJldHVybiAoa2V5OiBLKSA9PiB7XG4gICAgICAgIGlmIChjYWNoZS5oYXMoa2V5KSkge1xuICAgICAgICAgICAgcmV0dXJuIGNhY2hlLmdldChrZXkpITtcbiAgICAgICAgfVxuICAgICAgICBjb25zdCB2YWx1ZSA9IGZhY3Rvcnkoa2V5KTtcbiAgICAgICAgY2FjaGUuc2V0KGtleSwgdmFsdWUpO1xuICAgICAgICBpZiAoY2FjaGUuc2l6ZSA+IHNpemUpIHtcbiAgICAgICAgICAgIGNvbnN0IGZpcnN0ID0gY2FjaGUua2V5cygpLm5leHQoKS52YWx1ZTtcbiAgICAgICAgICAgIGNhY2hlLmRlbGV0ZShmaXJzdCk7XG4gICAgICAgIH1cbiAgICAgICAgcmV0dXJuIHZhbHVlO1xuICAgIH07XG59XG4iLCJpbXBvcnQgdHlwZSB7VXNlclNldHRpbmdzLCBUYWJJbmZvfSBmcm9tICcuLi9kZWZpbml0aW9ucyc7XG5cbmltcG9ydCB7Y2FjaGVkRmFjdG9yeX0gZnJvbSAnLi9jYWNoZSc7XG5cbmRlY2xhcmUgY29uc3QgX19USFVOREVSQklSRF9fOiBib29sZWFuO1xuXG5sZXQgYW5jaG9yOiBIVE1MQW5jaG9yRWxlbWVudDtcblxuZXhwb3J0IGNvbnN0IHBhcnNlZFVSTENhY2hlID0gbmV3IE1hcDxzdHJpbmcsIFVSTD4oKTtcblxuZnVuY3Rpb24gZml4QmFzZVVSTCgkdXJsOiBzdHJpbmcpOiBzdHJpbmcge1xuICAgIGlmICghYW5jaG9yKSB7XG4gICAgICAgIGFuY2hvciA9IGRvY3VtZW50LmNyZWF0ZUVsZW1lbnQoJ2EnKTtcbiAgICB9XG4gICAgYW5jaG9yLmhyZWYgPSAkdXJsO1xuICAgIHJldHVybiBhbmNob3IuaHJlZjtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIHBhcnNlVVJMKCR1cmw6IHN0cmluZywgJGJhc2U6IHN0cmluZyB8IG51bGwgPSBudWxsKTogVVJMIHtcbiAgICBjb25zdCBrZXkgPSBgJHskdXJsfSR7JGJhc2UgPyBgOyR7JGJhc2V9YCA6ICcnfWA7XG4gICAgaWYgKHBhcnNlZFVSTENhY2hlLmhhcyhrZXkpKSB7XG4gICAgICAgIHJldHVybiBwYXJzZWRVUkxDYWNoZS5nZXQoa2V5KSE7XG4gICAgfVxuICAgIGlmICgkYmFzZSkge1xuICAgICAgICBjb25zdCBwYXJzZWRVUkwgPSBuZXcgVVJMKCR1cmwsIGZpeEJhc2VVUkwoJGJhc2UpKTtcbiAgICAgICAgcGFyc2VkVVJMQ2FjaGUuc2V0KGtleSwgcGFyc2VkVVJMKTtcbiAgICAgICAgcmV0dXJuIHBhcnNlZFVSTDtcbiAgICB9XG4gICAgY29uc3QgcGFyc2VkVVJMID0gbmV3IFVSTChmaXhCYXNlVVJMKCR1cmwpKTtcbiAgICBwYXJzZWRVUkxDYWNoZS5zZXQoJHVybCwgcGFyc2VkVVJMKTtcbiAgICByZXR1cm4gcGFyc2VkVVJMO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gZ2V0QWJzb2x1dGVVUkwoJGJhc2U6IHN0cmluZywgJHJlbGF0aXZlOiBzdHJpbmcpOiBzdHJpbmcge1xuICAgIGlmICgkcmVsYXRpdmUubWF0Y2goL15kYXRhXFxcXD9cXDovKSkge1xuICAgICAgICByZXR1cm4gJHJlbGF0aXZlO1xuICAgIH1cbiAgICAvLyBDaGVjayBpZiByZWxhdGl2ZSBzdGFydHMgd2l0aCBgLy9ob3N0bmFtZS4uLmAuXG4gICAgLy8gV2UgaGF2ZSB0byBhZGQgYSBwcm90b2NvbCB0byBtYWtlIGl0IGFic29sdXRlLlxuICAgIGlmICgvXlxcL1xcLy8udGVzdCgkcmVsYXRpdmUpKSB7XG4gICAgICAgIHJldHVybiBgJHtsb2NhdGlvbi5wcm90b2NvbH0keyRyZWxhdGl2ZX1gO1xuICAgIH1cbiAgICBjb25zdCBiID0gcGFyc2VVUkwoJGJhc2UpO1xuICAgIGNvbnN0IGEgPSBwYXJzZVVSTCgkcmVsYXRpdmUsIGIuaHJlZik7XG4gICAgcmV0dXJuIGEuaHJlZjtcbn1cblxuLy8gQ2hlY2sgaWYgYW55IHJlbGF0aXZlIFVSTCBpcyBvbiB0aGUgd2luZG93LmxvY2F0aW9uO1xuLy8gU28gdGhhdCBodHRwczovL2R1Y2suY29tL2V4dC5jc3Mgd291bGQgcmV0dXJuIHRydWUgb24gaHR0cHM6Ly9kdWNrLmNvbS9cbi8vIEJ1dCBodHRwczovL2R1Y2suY29tL3N0eWxlcy9leHQuY3NzIHdvdWxkIHJldHVybiBmYWxzZSBvbiBodHRwczovL2R1Y2suY29tL1xuLy8gVmlzYSB2ZXJzYSBodHRwczovL2R1Y2suY29tL2V4dC5jc3Mgc2hvdWxkIHJldHVybiBmYXNsZSBvbiBodHRwczovL2R1Y2suY29tL3NlYXJjaC9cbi8vIFdlJ3JlIGNoZWNraW5nIGlmIGFueSByZWxhdGl2ZSB2YWx1ZSB3aXRoaW4gZXh0LmNzcyBjb3VsZCBwb3RlbnRpYWxseSBub3QgYmUgb24gdGhlIHNhbWUgcGF0aC5cbmV4cG9ydCBmdW5jdGlvbiBpc1JlbGF0aXZlSHJlZk9uQWJzb2x1dGVQYXRoKGhyZWY6IHN0cmluZyk6IGJvb2xlYW4ge1xuICAgIGlmIChocmVmLnN0YXJ0c1dpdGgoJ2RhdGE6JykpIHtcbiAgICAgICAgcmV0dXJuIHRydWU7XG4gICAgfVxuICAgIGNvbnN0IHVybCA9IHBhcnNlVVJMKGhyZWYpO1xuXG4gICAgaWYgKHVybC5wcm90b2NvbCAhPT0gbG9jYXRpb24ucHJvdG9jb2wpIHtcbiAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgIH1cbiAgICBpZiAodXJsLmhvc3RuYW1lICE9PSBsb2NhdGlvbi5ob3N0bmFtZSkge1xuICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgfVxuICAgIGlmICh1cmwucG9ydCAhPT0gbG9jYXRpb24ucG9ydCkge1xuICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgfVxuICAgIC8vIE5vdyBjaGVjayBpZiB0aGUgcGF0aCBpcyBvbiB0aGUgc2FtZSBwYXRoIGFzIHRoZSBiYXNlXG4gICAgLy8gV2UgZG8gdGhpcyBieSBnZXR0aW5nIHRoZSBwYXRobmFtZSB1cCB1bnRpbCB0aGUgbGFzdCBzbGFzaC5cbiAgICByZXR1cm4gdXJsLnBhdGhuYW1lID09PSBsb2NhdGlvbi5wYXRobmFtZTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGdldFVSTEhvc3RPclByb3RvY29sKCR1cmw6IHN0cmluZyk6IHN0cmluZyB7XG4gICAgY29uc3QgdXJsID0gbmV3IFVSTCgkdXJsKTtcbiAgICBpZiAodXJsLmhvc3QpIHtcbiAgICAgICAgcmV0dXJuIHVybC5ob3N0O1xuICAgIH0gZWxzZSBpZiAodXJsLnByb3RvY29sID09PSAnZmlsZTonKSB7XG4gICAgICAgIHJldHVybiB1cmwucGF0aG5hbWU7XG4gICAgfVxuICAgIHJldHVybiB1cmwucHJvdG9jb2w7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBjb21wYXJlVVJMUGF0dGVybnMoYTogc3RyaW5nLCBiOiBzdHJpbmcpOiBudW1iZXIge1xuICAgIHJldHVybiBhLmxvY2FsZUNvbXBhcmUoYik7XG59XG5cbi8qKlxuICogRGV0ZXJtaW5lcyB3aGV0aGVyIFVSTCBoYXMgYSBtYXRjaCBpbiBVUkwgdGVtcGxhdGUgbGlzdC5cbiAqIEBwYXJhbSB1cmwgU2l0ZSBVUkwuXG4gKiBAcGFyYW1saXN0IExpc3QgdG8gc2VhcmNoIGludG8uXG4gKi9cbmV4cG9ydCBmdW5jdGlvbiBpc1VSTEluTGlzdCh1cmw6IHN0cmluZywgbGlzdDogc3RyaW5nW10pOiBib29sZWFuIHtcbiAgICBmb3IgKGxldCBpID0gMDsgaSA8IGxpc3QubGVuZ3RoOyBpKyspIHtcbiAgICAgICAgaWYgKGlzVVJMTWF0Y2hlZCh1cmwsIGxpc3RbaV0pKSB7XG4gICAgICAgICAgICByZXR1cm4gdHJ1ZTtcbiAgICAgICAgfVxuICAgIH1cbiAgICByZXR1cm4gZmFsc2U7XG59XG5cbi8qKlxuICogRGV0ZXJtaW5lcyB3aGV0aGVyIFVSTCBtYXRjaGVzIHRoZSB0ZW1wbGF0ZS5cbiAqIEBwYXJhbSB1cmwgVVJMLlxuICogQHBhcmFtIHVybFRlbXBsYXRlIFVSTCB0ZW1wbGF0ZSAoXCJnb29nbGUuKlwiLCBcInlvdXR1YmUuY29tXCIgZXRjKS5cbiAqL1xuZXhwb3J0IGZ1bmN0aW9uIGlzVVJMTWF0Y2hlZCh1cmw6IHN0cmluZywgdXJsVGVtcGxhdGU6IHN0cmluZyk6IGJvb2xlYW4ge1xuICAgIGlmIChpc1JlZ0V4cCh1cmxUZW1wbGF0ZSkpIHtcbiAgICAgICAgY29uc3QgcmVnZXhwID0gY3JlYXRlUmVnRXhwKHVybFRlbXBsYXRlKTtcbiAgICAgICAgcmV0dXJuIHJlZ2V4cCA/IHJlZ2V4cC50ZXN0KHVybCkgOiBmYWxzZTtcbiAgICB9XG4gICAgcmV0dXJuIG1hdGNoVVJMUGF0dGVybih1cmwsIHVybFRlbXBsYXRlKTtcbn1cblxuaW50ZXJmYWNlIFByZXBhcmVkVVJMIHtcbiAgICBob3N0UGFydHM6IHN0cmluZ1tdO1xuICAgIHBhdGhQYXJ0czogc3RyaW5nW107XG4gICAgcG9ydDogc3RyaW5nO1xuICAgIHByb3RvY29sOiBzdHJpbmc7XG59XG5cbmludGVyZmFjZSBQcmVwYXJlZFBhdHRlcm4ge1xuICAgIGhvc3RQYXJ0czogc3RyaW5nW107XG4gICAgcGF0aFBhcnRzOiBzdHJpbmdbXTtcbiAgICBwb3J0OiBzdHJpbmc7XG4gICAgcHJvdG9jb2w6IHN0cmluZztcbiAgICBleGFjdFN0YXJ0OiBib29sZWFuO1xuICAgIGV4YWN0RW5kOiBib29sZWFuO1xufVxuXG5jb25zdCBVUkxfQ0FDSEVfU0laRSA9IDMyO1xuY29uc3QgcHJlcGFyZVVSTCA9IGNhY2hlZEZhY3RvcnkoKHVybDogc3RyaW5nKTogUHJlcGFyZWRVUkwgfCBudWxsID0+IHtcbiAgICBsZXQgcGFyc2VkOiBVUkw7XG4gICAgdHJ5IHtcbiAgICAgICAgcGFyc2VkID0gbmV3IFVSTCh1cmwpO1xuICAgIH0gY2F0Y2ggKGVycikge1xuICAgICAgICByZXR1cm4gbnVsbDtcbiAgICB9XG4gICAgY29uc3Qge2hvc3RuYW1lLCBwYXRobmFtZSwgcHJvdG9jb2wsIHBvcnR9ID0gcGFyc2VkO1xuICAgIGNvbnN0IGhvc3RQYXJ0cyA9IGhvc3RuYW1lLnNwbGl0KCcuJykucmV2ZXJzZSgpO1xuICAgIGNvbnN0IHBhdGhQYXJ0cyA9IHBhdGhuYW1lLnNwbGl0KCcvJykuc2xpY2UoMSk7XG4gICAgaWYgKCFwYXRoUGFydHNbcGF0aFBhcnRzLmxlbmd0aCAtIDFdKSB7XG4gICAgICAgIHBhdGhQYXJ0cy5zcGxpY2UocGF0aFBhcnRzLmxlbmd0aCAtIDEsIDEpO1xuICAgIH1cbiAgICByZXR1cm4ge1xuICAgICAgICBob3N0UGFydHMsXG4gICAgICAgIHBhdGhQYXJ0cyxcbiAgICAgICAgcG9ydCxcbiAgICAgICAgcHJvdG9jb2wsXG4gICAgfTtcbn0sIFVSTF9DQUNIRV9TSVpFKTtcblxuY29uc3QgVVJMX01BVENIX0NBQ0hFX1NJWkUgPSAzMiAqIDEwMjQ7XG5jb25zdCBwcmVwYXJlUGF0dGVybiA9IGNhY2hlZEZhY3RvcnkoKHBhdHRlcm46IHN0cmluZyk6IFByZXBhcmVkUGF0dGVybiB8IG51bGwgPT4ge1xuICAgIGlmICghcGF0dGVybikge1xuICAgICAgICByZXR1cm4gbnVsbDtcbiAgICB9XG5cbiAgICBjb25zdCBleGFjdFN0YXJ0ID0gcGF0dGVybi5zdGFydHNXaXRoKCdeJyk7XG4gICAgY29uc3QgZXhhY3RFbmQgPSBwYXR0ZXJuLmVuZHNXaXRoKCckJyk7XG4gICAgaWYgKGV4YWN0U3RhcnQpIHtcbiAgICAgICAgcGF0dGVybiA9IHBhdHRlcm4uc3Vic3RyaW5nKDEpO1xuICAgIH1cbiAgICBpZiAoZXhhY3RFbmQpIHtcbiAgICAgICAgcGF0dGVybiA9IHBhdHRlcm4uc3Vic3RyaW5nKDAsIHBhdHRlcm4ubGVuZ3RoIC0gMSk7XG4gICAgfVxuXG4gICAgbGV0IHByb3RvY29sID0gJyc7XG4gICAgY29uc3QgcHJvdG9jb2xJbmRleCA9IHBhdHRlcm4uaW5kZXhPZignOi8vJyk7XG4gICAgaWYgKHByb3RvY29sSW5kZXggPiAwKSB7XG4gICAgICAgIHByb3RvY29sID0gcGF0dGVybi5zdWJzdHJpbmcoMCwgcHJvdG9jb2xJbmRleCArIDEpO1xuICAgICAgICBwYXR0ZXJuID0gcGF0dGVybi5zdWJzdHJpbmcocHJvdG9jb2xJbmRleCArIDMpO1xuICAgIH1cblxuICAgIGNvbnN0IHNsYXNoSW5kZXggPSBwYXR0ZXJuLmluZGV4T2YoJy8nKTtcbiAgICBjb25zdCBob3N0ID0gc2xhc2hJbmRleCA8IDAgPyBwYXR0ZXJuIDogcGF0dGVybi5zdWJzdHJpbmcoMCwgc2xhc2hJbmRleCk7XG5cbiAgICBsZXQgaG9zdE5hbWUgPSBob3N0O1xuXG4gICAgbGV0IGlzSVB2NiA9IGZhbHNlO1xuICAgIGxldCBpcFY2RW5kID0gLTE7XG4gICAgaWYgKGhvc3Quc3RhcnRzV2l0aCgnWycpKSB7XG4gICAgICAgIGlwVjZFbmQgPSBob3N0LmluZGV4T2YoJ10nKTtcbiAgICAgICAgaWYgKGlwVjZFbmQgPiAwKSB7XG4gICAgICAgICAgICBpc0lQdjYgPSB0cnVlO1xuICAgICAgICB9XG4gICAgfVxuXG4gICAgbGV0IHBvcnQgPSAnKic7XG4gICAgY29uc3QgcG9ydEluZGV4ID0gaG9zdC5sYXN0SW5kZXhPZignOicpO1xuICAgIGlmIChwb3J0SW5kZXggPj0gMCAmJiAoIWlzSVB2NiB8fCBpcFY2RW5kIDwgcG9ydEluZGV4KSkge1xuICAgICAgICBob3N0TmFtZSA9IGhvc3Quc3Vic3RyaW5nKDAsIHBvcnRJbmRleCk7XG4gICAgICAgIHBvcnQgPSBob3N0LnN1YnN0cmluZyhwb3J0SW5kZXggKyAxKTtcbiAgICB9XG5cbiAgICBpZiAoaXNJUHY2KSB7XG4gICAgICAgIHRyeSB7XG4gICAgICAgICAgICBjb25zdCBpcFY2VVJMID0gbmV3IFVSTChgaHR0cDovLyR7aG9zdE5hbWV9YCk7XG4gICAgICAgICAgICBob3N0TmFtZSA9IGlwVjZVUkwuaG9zdG5hbWU7XG4gICAgICAgIH0gY2F0Y2ggKGVycikge1xuICAgICAgICB9XG4gICAgfVxuXG4gICAgY29uc3QgaG9zdFBhcnRzID0gaG9zdE5hbWUuc3BsaXQoJy4nKS5yZXZlcnNlKCk7XG5cbiAgICBjb25zdCBwYXRoID0gc2xhc2hJbmRleCA8IDAgPyAnJyA6IHBhdHRlcm4uc3Vic3RyaW5nKHNsYXNoSW5kZXggKyAxKTtcbiAgICBjb25zdCBwYXRoUGFydHMgPSBwYXRoLnNwbGl0KCcvJyk7XG4gICAgaWYgKCFwYXRoUGFydHNbcGF0aFBhcnRzLmxlbmd0aCAtIDFdKSB7XG4gICAgICAgIHBhdGhQYXJ0cy5zcGxpY2UocGF0aFBhcnRzLmxlbmd0aCAtIDEsIDEpO1xuICAgIH1cblxuICAgIHJldHVybiB7XG4gICAgICAgIGhvc3RQYXJ0cyxcbiAgICAgICAgcGF0aFBhcnRzLFxuICAgICAgICBwb3J0LFxuICAgICAgICBleGFjdFN0YXJ0LFxuICAgICAgICBleGFjdEVuZCxcbiAgICAgICAgcHJvdG9jb2wsXG4gICAgfTtcbn0sIFVSTF9NQVRDSF9DQUNIRV9TSVpFKTtcblxuZnVuY3Rpb24gbWF0Y2hVUkxQYXR0ZXJuKHVybDogc3RyaW5nLCBwYXR0ZXJuOiBzdHJpbmcpIHtcbiAgICBjb25zdCB1ID0gcHJlcGFyZVVSTCh1cmwpO1xuICAgIGNvbnN0IHAgPSBwcmVwYXJlUGF0dGVybihwYXR0ZXJuKTtcbiAgICByZXR1cm4gbWF0Y2hQcmVwYXJlZFVSTFBhdHRlcm4odSwgcCk7XG59XG5cbmZ1bmN0aW9uIG1hdGNoUHJlcGFyZWRVUkxQYXR0ZXJuKHU6IFByZXBhcmVkVVJMIHwgbnVsbCwgcDogUHJlcGFyZWRQYXR0ZXJuIHwgbnVsbCkge1xuICAgIGlmIChcbiAgICAgICAgISh1ICYmIHApXG4gICAgICAgIHx8IChwLmhvc3RQYXJ0cy5sZW5ndGggPiB1Lmhvc3RQYXJ0cy5sZW5ndGgpXG4gICAgICAgIHx8IChwLmV4YWN0U3RhcnQgJiYgcC5ob3N0UGFydHMubGVuZ3RoICE9PSB1Lmhvc3RQYXJ0cy5sZW5ndGgpXG4gICAgICAgIHx8IChwLmV4YWN0RW5kICYmIHAucGF0aFBhcnRzLmxlbmd0aCAhPT0gdS5wYXRoUGFydHMubGVuZ3RoKVxuICAgICAgICB8fCAocC5wb3J0ICE9PSAnKicgJiYgcC5wb3J0ICE9PSB1LnBvcnQpXG4gICAgICAgIHx8IChwLnByb3RvY29sICYmIHAucHJvdG9jb2wgIT09IHUucHJvdG9jb2wpXG4gICAgKSB7XG4gICAgICAgIHJldHVybiBmYWxzZTtcbiAgICB9XG5cbiAgICBmb3IgKGxldCBpID0gMDsgaSA8IHAuaG9zdFBhcnRzLmxlbmd0aDsgaSsrKSB7XG4gICAgICAgIGNvbnN0IHBIb3N0UGFydCA9IHAuaG9zdFBhcnRzW2ldO1xuICAgICAgICBjb25zdCB1SG9zdFBhcnQgPSB1Lmhvc3RQYXJ0c1tpXTtcbiAgICAgICAgaWYgKHBIb3N0UGFydCAhPT0gJyonICYmIHBIb3N0UGFydCAhPT0gdUhvc3RQYXJ0KSB7XG4gICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBpZiAoXG4gICAgICAgIHAuaG9zdFBhcnRzLmxlbmd0aCA+PSAyXG4gICAgICAgICYmIHAuaG9zdFBhcnRzLmF0KC0xKSAhPT0gJyonXG4gICAgICAgICYmIChcbiAgICAgICAgICAgIHAuaG9zdFBhcnRzLmxlbmd0aCA8IHUuaG9zdFBhcnRzLmxlbmd0aCAtIDFcbiAgICAgICAgICAgIHx8IChcbiAgICAgICAgICAgICAgICBwLmhvc3RQYXJ0cy5sZW5ndGggPT09IHUuaG9zdFBhcnRzLmxlbmd0aCAtIDFcbiAgICAgICAgICAgICAgICAmJiB1Lmhvc3RQYXJ0cy5hdCgtMSkgIT09ICd3d3cnXG4gICAgICAgICAgICApXG4gICAgICAgIClcbiAgICApIHtcbiAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgIH1cblxuICAgIGlmIChwLnBhdGhQYXJ0cy5sZW5ndGggPT09IDApIHtcbiAgICAgICAgcmV0dXJuIHRydWU7XG4gICAgfVxuXG4gICAgaWYgKHAucGF0aFBhcnRzLmxlbmd0aCA+IHUucGF0aFBhcnRzLmxlbmd0aCkge1xuICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgfVxuXG4gICAgZm9yIChsZXQgaSA9IDA7IGkgPCBwLnBhdGhQYXJ0cy5sZW5ndGg7IGkrKykge1xuICAgICAgICBjb25zdCBwUGF0aFBhcnQgPSBwLnBhdGhQYXJ0c1tpXTtcbiAgICAgICAgY29uc3QgdVBhdGhQYXJ0ID0gdS5wYXRoUGFydHNbaV07XG4gICAgICAgIGlmIChwUGF0aFBhcnQgIT09ICcqJyAmJiBwUGF0aFBhcnQgIT09IHVQYXRoUGFydCkge1xuICAgICAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgICAgICB9XG4gICAgfVxuXG4gICAgcmV0dXJuIHRydWU7XG59XG5cbmZ1bmN0aW9uIGlzUmVnRXhwKHBhdHRlcm46IHN0cmluZykge1xuICAgIHJldHVybiBwYXR0ZXJuLnN0YXJ0c1dpdGgoJy8nKSAmJiBwYXR0ZXJuLmVuZHNXaXRoKCcvJykgJiYgcGF0dGVybi5sZW5ndGggPiAyO1xufVxuXG5jb25zdCBSRUdFWFBfQ0FDSEVfU0laRSA9IDEwMjQ7XG5jb25zdCBjcmVhdGVSZWdFeHAgPSBjYWNoZWRGYWN0b3J5KChwYXR0ZXJuOiBzdHJpbmcpID0+IHtcbiAgICBpZiAocGF0dGVybi5zdGFydHNXaXRoKCcvJykpIHtcbiAgICAgICAgcGF0dGVybiA9IHBhdHRlcm4uc3Vic3RyaW5nKDEpO1xuICAgIH1cbiAgICBpZiAocGF0dGVybi5lbmRzV2l0aCgnLycpKSB7XG4gICAgICAgIHBhdHRlcm4gPSBwYXR0ZXJuLnN1YnN0cmluZygwLCBwYXR0ZXJuLmxlbmd0aCAtIDEpO1xuICAgIH1cbiAgICB0cnkge1xuICAgICAgICByZXR1cm4gbmV3IFJlZ0V4cChwYXR0ZXJuKTtcbiAgICB9IGNhdGNoIChlcnIpIHtcbiAgICAgICAgcmV0dXJuIG51bGw7XG4gICAgfVxufSwgUkVHRVhQX0NBQ0hFX1NJWkUpO1xuXG5jb25zdCB3aWtpUERGUGF0aFJlZ2V4cCA9IC9eXFwvLipcXC9bYS16XStcXDpbXlxcOlxcL10rXFwucGRmL2k7XG5cbmV4cG9ydCBmdW5jdGlvbiBpc1BERih1cmw6IHN0cmluZyk6IGJvb2xlYW4ge1xuICAgIHRyeSB7XG4gICAgICAgIGNvbnN0IHtob3N0bmFtZSwgcGF0aG5hbWV9ID0gbmV3IFVSTCh1cmwpO1xuICAgICAgICBpZiAocGF0aG5hbWUuaW5jbHVkZXMoJy5wZGYnKSkge1xuICAgICAgICAgICAgaWYgKFxuICAgICAgICAgICAgICAgICgoaG9zdG5hbWUuZW5kc1dpdGgoJy53aWtpbWVkaWEub3JnJykgfHwgaG9zdG5hbWUuZW5kc1dpdGgoJy53aWtpcGVkaWEub3JnJykpICYmIHBhdGhuYW1lLm1hdGNoKHdpa2lQREZQYXRoUmVnZXhwKSkgfHxcbiAgICAgICAgICAgICAgICAoaG9zdG5hbWUuZW5kc1dpdGgoJy5kcm9wYm94LmNvbScpICYmIHBhdGhuYW1lLnN0YXJ0c1dpdGgoJy9zLycpICYmIChwYXRobmFtZS5lbmRzV2l0aCgnLnBkZicpIHx8IHBhdGhuYW1lLmVuZHNXaXRoKCcuUERGJykpKVxuICAgICAgICAgICAgKSB7XG4gICAgICAgICAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgaWYgKHBhdGhuYW1lLmVuZHNXaXRoKCcucGRmJykpIHtcbiAgICAgICAgICAgICAgICBmb3IgKGxldCBpID0gcGF0aG5hbWUubGVuZ3RoOyBpID49IDA7IGktLSkge1xuICAgICAgICAgICAgICAgICAgICBpZiAocGF0aG5hbWVbaV0gPT09ICc9Jykge1xuICAgICAgICAgICAgICAgICAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgICAgICAgICAgICAgICAgICB9IGVsc2UgaWYgKHBhdGhuYW1lW2ldID09PSAnLycpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgIHJldHVybiB0cnVlO1xuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICB9IGNhdGNoIChlKSB7XG4gICAgICAgIC8vIERvIG5vdGhpbmdcbiAgICB9XG4gICAgcmV0dXJuIGZhbHNlO1xufVxuXG5jb25zdCBpbmRleGVkU2l0ZUxpc3RzID0gbmV3IFdlYWtNYXA8c3RyaW5nW10sIFVSTFRlbXBsYXRlSW5kZXg+KCk7XG5cbmZ1bmN0aW9uIGlzSW5MaXN0T3B0aW1pemVkKHVybDogc3RyaW5nLCBsaXN0OiBzdHJpbmdbXSkge1xuICAgIGlmICghdXJsIHx8IGxpc3QubGVuZ3RoID09PSAwKSB7XG4gICAgICAgIHJldHVybiBmYWxzZTtcbiAgICB9XG4gICAgbGV0IGluZGV4ID0gaW5kZXhlZFNpdGVMaXN0cy5nZXQobGlzdCk7XG4gICAgaWYgKCFpbmRleCkge1xuICAgICAgICBpbmRleCA9IGluZGV4VVJMVGVtcGxhdGVMaXN0KGxpc3QpO1xuICAgICAgICBpbmRleGVkU2l0ZUxpc3RzLnNldChsaXN0LCBpbmRleCk7XG4gICAgfVxuICAgIHJldHVybiBpc1VSTEluSW5kZXhlZExpc3QodXJsLCBpbmRleCk7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBpc1VSTEVuYWJsZWQodXJsOiBzdHJpbmcsIHVzZXJTZXR0aW5nczogVXNlclNldHRpbmdzLCB7aXNQcm90ZWN0ZWQsIGlzSW5EYXJrTGlzdCwgaXNEYXJrVGhlbWVEZXRlY3RlZH06IFBhcnRpYWw8VGFiSW5mbz4sIGlzQWxsb3dlZEZpbGVTY2hlbWVBY2Nlc3MgPSB0cnVlKTogYm9vbGVhbiB7XG4gICAgaWYgKGlzTG9jYWxGaWxlKHVybCkgJiYgIWlzQWxsb3dlZEZpbGVTY2hlbWVBY2Nlc3MpIHtcbiAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgIH1cbiAgICBpZiAoaXNQcm90ZWN0ZWQgJiYgIXVzZXJTZXR0aW5ncy5lbmFibGVGb3JQcm90ZWN0ZWRQYWdlcykge1xuICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgfVxuICAgIC8vIE9ubHkgVVJMJ3Mgd2l0aCBlbWFpbHMgYXJlIGdldHRpbmcgaGVyZSBvbiB0aHVuZGVyYmlyZFxuICAgIC8vIFNvIHdlIGNhbiBza2lwIHRoZSBjaGVja3MgYW5kIGp1c3QgcmV0dXJuIHRydWUuXG4gICAgaWYgKF9fVEhVTkRFUkJJUkRfXykge1xuICAgICAgICByZXR1cm4gdHJ1ZTtcbiAgICB9XG4gICAgaWYgKGlzUERGKHVybCkpIHtcbiAgICAgICAgcmV0dXJuIHVzZXJTZXR0aW5ncy5lbmFibGVGb3JQREY7XG4gICAgfVxuICAgIGNvbnN0IGlzVVJMSW5EaXNhYmxlZExpc3QgPSBpc0luTGlzdE9wdGltaXplZCh1cmwsIHVzZXJTZXR0aW5ncy5kaXNhYmxlZEZvcik7XG4gICAgY29uc3QgaXNVUkxJbkVuYWJsZWRMaXN0ID0gaXNJbkxpc3RPcHRpbWl6ZWQodXJsLCB1c2VyU2V0dGluZ3MuZW5hYmxlZEZvcik7XG5cbiAgICBpZiAoIXVzZXJTZXR0aW5ncy5lbmFibGVkQnlEZWZhdWx0KSB7XG4gICAgICAgIHJldHVybiBpc1VSTEluRW5hYmxlZExpc3Q7XG4gICAgfVxuICAgIGlmIChpc1VSTEluRW5hYmxlZExpc3QpIHtcbiAgICAgICAgcmV0dXJuIHRydWU7XG4gICAgfVxuICAgIGlmIChpc0luRGFya0xpc3QgfHwgKHVzZXJTZXR0aW5ncy5kZXRlY3REYXJrVGhlbWUgJiYgaXNEYXJrVGhlbWVEZXRlY3RlZCkpIHtcbiAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgIH1cbiAgICByZXR1cm4gIWlzVVJMSW5EaXNhYmxlZExpc3Q7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBpc0xvY2FsRmlsZSh1cmw6IHN0cmluZyk6IGJvb2xlYW4ge1xuICAgIHJldHVybiBCb29sZWFuKHVybCkgJiYgdXJsLnN0YXJ0c1dpdGgoJ2ZpbGU6Ly8vJyk7XG59XG5cbmludGVyZmFjZSBVUkxUcmllTm9kZTxUID0gYW55PiB7XG4gICAga2V5OiBzdHJpbmc7XG4gICAgaG9zdE5vZGVzOiBNYXA8c3RyaW5nLCBVUkxUcmllTm9kZTxUPj47XG4gICAgcGF0aE5vZGVzOiBNYXA8c3RyaW5nLCBVUkxUcmllTm9kZTxUPj47XG4gICAgZGF0YTogVCB8IG51bGw7XG59XG5cbmV4cG9ydCBpbnRlcmZhY2UgVVJMVHJpZTxUID0gYW55PiBleHRlbmRzIFVSTFRyaWVOb2RlPFQ+IHtcbiAgICBoYXJkUGF0dGVybnM6IEFycmF5PHtwYXR0ZXJuOiBQcmVwYXJlZFBhdHRlcm47IGRhdGE6IFR9PjtcbiAgICByZWdleHBzOiBBcnJheTx7cmVnZXhwOiBSZWdFeHA7IGRhdGE6IFR9Pjtcbn1cblxuZXhwb3J0IHR5cGUgVVJMVGVtcGxhdGVJbmRleCA9IFVSTFRyaWU8Ym9vbGVhbj47XG5cbmV4cG9ydCBmdW5jdGlvbiBpbmRleFVSTFRlbXBsYXRlTGlzdDxUID0gYm9vbGVhbj4obGlzdDogc3RyaW5nW10sIGFzc2lnbjogKChwYXR0ZXJuOiBzdHJpbmcsIGluZGV4OiBudW1iZXIpID0+IFQpID0gKCkgPT4gdHJ1ZSBhcyBUKTogVVJMVHJpZTxUPiB7XG4gICAgY29uc3QgdHJpZTogVVJMVHJpZTxUPiA9IHtcbiAgICAgICAga2V5OiAnJyxcbiAgICAgICAgaG9zdE5vZGVzOiBuZXcgTWFwKCksXG4gICAgICAgIHBhdGhOb2RlczogbmV3IE1hcCgpLFxuICAgICAgICBoYXJkUGF0dGVybnM6IFtdLFxuICAgICAgICByZWdleHBzOiBbXSxcbiAgICAgICAgZGF0YTogbnVsbCxcbiAgICB9O1xuXG4gICAgY29uc3QgdGVtcGxhdGVJbmRpY2VzID0gbmV3IE1hcDxQcmVwYXJlZFBhdHRlcm4gfCBSZWdFeHAsIG51bWJlcj4oKTtcblxuICAgIGNvbnN0IHBhdHRlcm5zOiBQcmVwYXJlZFBhdHRlcm5bXSA9IFtdO1xuICAgIGxpc3QuZm9yRWFjaCgodSwgaSkgPT4ge1xuICAgICAgICBpZiAoaXNSZWdFeHAodSkpIHtcbiAgICAgICAgICAgIGNvbnN0IHIgPSBjcmVhdGVSZWdFeHAodSk7XG4gICAgICAgICAgICBpZiAocikge1xuICAgICAgICAgICAgICAgIHRyaWUucmVnZXhwcy5wdXNoKHtyZWdleHA6IHIsIGRhdGE6IGFzc2lnbihsaXN0W2ldLCBpKX0pO1xuICAgICAgICAgICAgfVxuICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgY29uc3QgcCA9IHByZXBhcmVQYXR0ZXJuKHUpO1xuICAgICAgICAgICAgaWYgKHApIHtcbiAgICAgICAgICAgICAgICBpZiAocC5leGFjdFN0YXJ0IHx8IHAuZXhhY3RFbmQgfHwgKHAucG9ydCAmJiBwLnBvcnQgIT09ICcqJykgfHwgcC5wcm90b2NvbCkge1xuICAgICAgICAgICAgICAgICAgICB0cmllLmhhcmRQYXR0ZXJucy5wdXNoKHtwYXR0ZXJuOiBwLCBkYXRhOiBhc3NpZ24obGlzdFtpXSwgaSl9KTtcbiAgICAgICAgICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICBwYXR0ZXJucy5wdXNoKHApO1xuICAgICAgICAgICAgICAgIHRlbXBsYXRlSW5kaWNlcy5zZXQocCwgaSk7XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICB9KTtcblxuICAgIHBhdHRlcm5zLmZvckVhY2goKHBhdHRlcm4pID0+IHtcbiAgICAgICAgY29uc3QgbGlzdEluZGV4ID0gdGVtcGxhdGVJbmRpY2VzLmdldChwYXR0ZXJuKSE7XG4gICAgICAgIGNvbnN0IGRhdGEgPSBhc3NpZ24obGlzdFtsaXN0SW5kZXhdLCBsaXN0SW5kZXgpO1xuXG4gICAgICAgIGxldCBub2RlOiBVUkxUcmllTm9kZSA9IHRyaWU7XG4gICAgICAgIHBhdHRlcm4uaG9zdFBhcnRzLmZvckVhY2goKHApID0+IHtcbiAgICAgICAgICAgIGNvbnN0IG5vZGVzID0gbm9kZS5ob3N0Tm9kZXM7XG4gICAgICAgICAgICBpZiAobm9kZXMuaGFzKHApKSB7XG4gICAgICAgICAgICAgICAgbm9kZSA9IG5vZGVzLmdldChwKSE7XG4gICAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgICAgIG5vZGUgPSB7XG4gICAgICAgICAgICAgICAgICAgIGtleTogcCxcbiAgICAgICAgICAgICAgICAgICAgaG9zdE5vZGVzOiBuZXcgTWFwKCksXG4gICAgICAgICAgICAgICAgICAgIHBhdGhOb2RlczogbmV3IE1hcCgpLFxuICAgICAgICAgICAgICAgICAgICBkYXRhOiBudWxsLFxuICAgICAgICAgICAgICAgIH07XG4gICAgICAgICAgICAgICAgbm9kZXMuc2V0KHAsIG5vZGUpO1xuICAgICAgICAgICAgfVxuICAgICAgICB9KTtcbiAgICAgICAgY29uc3QgbGFzdEhvc3ROb2RlOiBVUkxUcmllTm9kZSA9IHtcbiAgICAgICAgICAgIGtleTogJycsXG4gICAgICAgICAgICBob3N0Tm9kZXM6IG5ldyBNYXAoKSxcbiAgICAgICAgICAgIHBhdGhOb2RlczogbmV3IE1hcCgpLFxuICAgICAgICAgICAgZGF0YTogbnVsbCxcbiAgICAgICAgfTtcbiAgICAgICAgbm9kZS5ob3N0Tm9kZXMuc2V0KCcnLCBsYXN0SG9zdE5vZGUpO1xuICAgICAgICBub2RlID0gbGFzdEhvc3ROb2RlO1xuXG4gICAgICAgIGlmIChwYXR0ZXJuLnBhdGhQYXJ0cy5sZW5ndGggPT09IDApIHtcbiAgICAgICAgICAgIG5vZGUuZGF0YSA9IGRhdGE7XG4gICAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cblxuICAgICAgICBwYXR0ZXJuLnBhdGhQYXJ0cy5mb3JFYWNoKChwKSA9PiB7XG4gICAgICAgICAgICBjb25zdCBub2RlcyA9IG5vZGUucGF0aE5vZGVzO1xuICAgICAgICAgICAgaWYgKG5vZGVzLmhhcyhwKSkge1xuICAgICAgICAgICAgICAgIG5vZGUgPSBub2Rlcy5nZXQocCkhO1xuICAgICAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgICAgICBub2RlID0ge1xuICAgICAgICAgICAgICAgICAgICBrZXk6IHAsXG4gICAgICAgICAgICAgICAgICAgIGhvc3ROb2RlczogbmV3IE1hcCgpLFxuICAgICAgICAgICAgICAgICAgICBwYXRoTm9kZXM6IG5ldyBNYXAoKSxcbiAgICAgICAgICAgICAgICAgICAgZGF0YTogbnVsbCxcbiAgICAgICAgICAgICAgICB9O1xuICAgICAgICAgICAgICAgIG5vZGVzLnNldChwLCBub2RlKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfSk7XG4gICAgICAgIGNvbnN0IGxhc3RQYXRoTm9kZTogVVJMVHJpZU5vZGUgPSB7XG4gICAgICAgICAgICBrZXk6ICcnLFxuICAgICAgICAgICAgaG9zdE5vZGVzOiBuZXcgTWFwKCksXG4gICAgICAgICAgICBwYXRoTm9kZXM6IG5ldyBNYXAoKSxcbiAgICAgICAgICAgIGRhdGE6IG51bGwsXG4gICAgICAgIH07XG4gICAgICAgIG5vZGUucGF0aE5vZGVzLnNldCgnJywgbGFzdFBhdGhOb2RlKTtcbiAgICAgICAgbGFzdFBhdGhOb2RlLmRhdGEgPSBkYXRhO1xuICAgIH0pO1xuICAgIHJldHVybiB0cmllO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gaXNVUkxJbkluZGV4ZWRMaXN0KHVybDogc3RyaW5nLCB0cmllOiBVUkxUcmllPGFueT4pIHtcbiAgICBjb25zdCBtYXRjaGVzID0gZ2V0VVJMTWF0Y2hlc0Zyb21JbmRleGVkTGlzdCh1cmwsIHRyaWUsIHRydWUpO1xuICAgIHJldHVybiBtYXRjaGVzLmxlbmd0aCA+IDA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBnZXRVUkxNYXRjaGVzRnJvbUluZGV4ZWRMaXN0PFQ+KHVybDogc3RyaW5nLCB0cmllOiBVUkxUcmllPFQ+LCBicmVha09uRmlyc3RNYXRjaCA9IGZhbHNlKTogVFtdIHtcbiAgICBjb25zdCBmb3VuZCA9IG5ldyBTZXQ8VD4oKTtcbiAgICBjb25zdCBtYXRjaGVzOiBUW10gPSBbXTtcblxuICAgIGNvbnN0IHB1c2ggPSAoZGF0YTogVCkgPT4ge1xuICAgICAgICBpZiAoIWZvdW5kLmhhcyhkYXRhKSkge1xuICAgICAgICAgICAgZm91bmQuYWRkKGRhdGEpO1xuICAgICAgICAgICAgbWF0Y2hlcy5wdXNoKGRhdGEpO1xuICAgICAgICB9XG4gICAgfTtcblxuICAgIGZvciAoY29uc3QgciBvZiB0cmllLnJlZ2V4cHMpIHtcbiAgICAgICAgaWYgKHIucmVnZXhwLnRlc3QodXJsKSkge1xuICAgICAgICAgICAgcHVzaChyLmRhdGEpO1xuICAgICAgICAgICAgaWYgKGJyZWFrT25GaXJzdE1hdGNoKSB7XG4gICAgICAgICAgICAgICAgcmV0dXJuIG1hdGNoZXM7XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBjb25zdCB1ID0gcHJlcGFyZVVSTCh1cmwpO1xuICAgIGlmICghdSkge1xuICAgICAgICByZXR1cm4gbWF0Y2hlcztcbiAgICB9XG5cbiAgICBmb3IgKGNvbnN0IHAgb2YgdHJpZS5oYXJkUGF0dGVybnMpIHtcbiAgICAgICAgaWYgKG1hdGNoUHJlcGFyZWRVUkxQYXR0ZXJuKHUsIHAucGF0dGVybikpIHtcbiAgICAgICAgICAgIHB1c2gocC5kYXRhKTtcbiAgICAgICAgICAgIGlmIChicmVha09uRmlyc3RNYXRjaCkge1xuICAgICAgICAgICAgICAgIHJldHVybiBtYXRjaGVzO1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG4gICAgfVxuXG4gICAgY29uc3QgbWF0Y2hIb3N0ID0gKG5vZGU6IFVSTFRyaWVOb2RlLCBpbmRleDogbnVtYmVyKSA9PiB7XG4gICAgICAgIGNvbnN0IGZpbmFsSG9zdE5vZGUgPSBub2RlLmhvc3ROb2Rlcy5nZXQoJycpO1xuICAgICAgICBjb25zdCBub01vcmVIb3N0UGFydHMgPSBpbmRleCA9PT0gdS5ob3N0UGFydHMubGVuZ3RoO1xuICAgICAgICBjb25zdCB2YWx1ZSA9IG5vTW9yZUhvc3RQYXJ0cyA/ICcnIDogdS5ob3N0UGFydHNbaW5kZXhdO1xuXG4gICAgICAgIGlmIChcbiAgICAgICAgICAgIGZpbmFsSG9zdE5vZGUgJiYgKFxuICAgICAgICAgICAgICAgIG5vTW9yZUhvc3RQYXJ0cyB8fFxuICAgICAgICAgICAgICAgIG5vZGUua2V5ID09PSAnKicgfHxcbiAgICAgICAgICAgICAgICAoaW5kZXggPT09IHUuaG9zdFBhcnRzLmxlbmd0aCAtIDEgJiYgdmFsdWUgPT09ICd3d3cnKVxuICAgICAgICAgICAgKVxuICAgICAgICApIHtcbiAgICAgICAgICAgIGlmIChmaW5hbEhvc3ROb2RlLmRhdGEpIHtcbiAgICAgICAgICAgICAgICBwdXNoKGZpbmFsSG9zdE5vZGUuZGF0YSk7XG4gICAgICAgICAgICAgICAgaWYgKGJyZWFrT25GaXJzdE1hdGNoKSB7XG4gICAgICAgICAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICBtYXRjaFBhdGgoZmluYWxIb3N0Tm9kZSwgMCk7XG4gICAgICAgIH1cblxuICAgICAgICBpZiAobm9Nb3JlSG9zdFBhcnRzKSB7XG4gICAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cblxuICAgICAgICBjb25zdCBub2RlcyA9IG5vZGUuaG9zdE5vZGVzO1xuICAgICAgICBjb25zdCB3aWxkY2FyZE5vZGUgPSBub2Rlcy5nZXQoJyonKTtcbiAgICAgICAgaWYgKHdpbGRjYXJkTm9kZSkge1xuICAgICAgICAgICAgbWF0Y2hIb3N0KHdpbGRjYXJkTm9kZSwgaW5kZXggKyAxKTtcbiAgICAgICAgfVxuXG4gICAgICAgIGlmIChicmVha09uRmlyc3RNYXRjaCAmJiBtYXRjaGVzLmxlbmd0aCA+IDApIHtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuXG4gICAgICAgIGNvbnN0IGtleU5vZGUgPSBub2Rlcy5nZXQodmFsdWUpO1xuICAgICAgICBpZiAoa2V5Tm9kZSkge1xuICAgICAgICAgICAgbWF0Y2hIb3N0KGtleU5vZGUsIGluZGV4ICsgMSk7XG4gICAgICAgIH1cbiAgICB9O1xuXG4gICAgY29uc3QgbWF0Y2hQYXRoID0gKG5vZGU6IFVSTFRyaWVOb2RlLCBpbmRleDogbnVtYmVyKSA9PiB7XG4gICAgICAgIGNvbnN0IGZpbmFsUGF0aE5vZGUgPSBub2RlLnBhdGhOb2Rlcy5nZXQoJycpO1xuICAgICAgICBjb25zdCBub01vcmVQYXRoUGFydHMgPSBpbmRleCA9PT0gdS5wYXRoUGFydHMubGVuZ3RoO1xuICAgICAgICBjb25zdCB2YWx1ZSA9IG5vTW9yZVBhdGhQYXJ0cyA/ICcnIDogdS5wYXRoUGFydHNbaW5kZXhdO1xuXG4gICAgICAgIGlmIChmaW5hbFBhdGhOb2RlICYmIGZpbmFsUGF0aE5vZGUuZGF0YSkge1xuICAgICAgICAgICAgcHVzaChmaW5hbFBhdGhOb2RlLmRhdGEpO1xuICAgICAgICB9XG5cbiAgICAgICAgaWYgKG5vTW9yZVBhdGhQYXJ0cykge1xuICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICB9XG5cbiAgICAgICAgY29uc3Qgbm9kZXMgPSBub2RlLnBhdGhOb2RlcztcbiAgICAgICAgY29uc3Qgd2lsZGNhcmROb2RlID0gbm9kZXMuZ2V0KCcqJyk7XG4gICAgICAgIGlmICh3aWxkY2FyZE5vZGUpIHtcbiAgICAgICAgICAgIG1hdGNoUGF0aCh3aWxkY2FyZE5vZGUsIGluZGV4ICsgMSk7XG4gICAgICAgIH1cblxuICAgICAgICBpZiAoYnJlYWtPbkZpcnN0TWF0Y2ggJiYgbWF0Y2hlcy5sZW5ndGggPiAwKSB7XG4gICAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cblxuICAgICAgICBjb25zdCBrZXlOb2RlID0gbm9kZXMuZ2V0KHZhbHVlKTtcbiAgICAgICAgaWYgKGtleU5vZGUpIHtcbiAgICAgICAgICAgIG1hdGNoUGF0aChrZXlOb2RlLCBpbmRleCArIDEpO1xuICAgICAgICB9XG4gICAgfTtcblxuICAgIG1hdGNoSG9zdCh0cmllLCAwKTtcblxuICAgIHJldHVybiBtYXRjaGVzO1xufVxuIiwiaW1wb3J0IHtpc0ZpcmVmb3gsIGlzRWRnZX0gZnJvbSAnLi4vLi4vdXRpbHMvcGxhdGZvcm0nO1xuaW1wb3J0IHtnZXREdXJhdGlvbn0gZnJvbSAnLi4vLi4vdXRpbHMvdGltZSc7XG5pbXBvcnQge2lzUERGfSBmcm9tICcuLi8uLi91dGlscy91cmwnO1xuXG5leHBvcnQgZnVuY3Rpb24gY2FuSW5qZWN0U2NyaXB0KHVybDogc3RyaW5nIHwgbnVsbCB8IHVuZGVmaW5lZCk6IGJvb2xlYW4ge1xuICAgIGlmICh1cmwgPT09ICdhYm91dDpibGFuaycpIHtcbiAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgIH1cbiAgICBpZiAoaXNGaXJlZm94KSB7XG4gICAgICAgIHJldHVybiBCb29sZWFuKHVybFxuICAgICAgICAgICAgJiYgIXVybC5zdGFydHNXaXRoKCdhYm91dDonKVxuICAgICAgICAgICAgJiYgIXVybC5zdGFydHNXaXRoKCdtb3onKVxuICAgICAgICAgICAgJiYgIXVybC5zdGFydHNXaXRoKCd2aWV3LXNvdXJjZTonKVxuICAgICAgICAgICAgJiYgIXVybC5zdGFydHNXaXRoKCdyZXNvdXJjZTonKVxuICAgICAgICAgICAgJiYgIXVybC5zdGFydHNXaXRoKCdjaHJvbWU6JylcbiAgICAgICAgICAgICYmICF1cmwuc3RhcnRzV2l0aCgnamFyOicpXG4gICAgICAgICAgICAmJiAhdXJsLnN0YXJ0c1dpdGgoJ2h0dHBzOi8vYWRkb25zLm1vemlsbGEub3JnLycpXG4gICAgICAgICAgICAmJiAhaXNQREYodXJsKVxuICAgICAgICApO1xuICAgIH1cbiAgICBpZiAoaXNFZGdlKSB7XG4gICAgICAgIHJldHVybiBCb29sZWFuKHVybFxuICAgICAgICAgICAgJiYgIXVybC5zdGFydHNXaXRoKCdjaHJvbWUnKVxuICAgICAgICAgICAgJiYgIXVybC5zdGFydHNXaXRoKCdkYXRhJylcbiAgICAgICAgICAgICYmICF1cmwuc3RhcnRzV2l0aCgnZGV2dG9vbHMnKVxuICAgICAgICAgICAgJiYgIXVybC5zdGFydHNXaXRoKCdlZGdlJylcbiAgICAgICAgICAgICYmICF1cmwuc3RhcnRzV2l0aCgnaHR0cHM6Ly9jaHJvbWUuZ29vZ2xlLmNvbS93ZWJzdG9yZScpXG4gICAgICAgICAgICAmJiAhdXJsLnN0YXJ0c1dpdGgoJ2h0dHBzOi8vY2hyb21ld2Vic3RvcmUuZ29vZ2xlLmNvbS8nKVxuICAgICAgICAgICAgJiYgIXVybC5zdGFydHNXaXRoKCdodHRwczovL21pY3Jvc29mdGVkZ2UubWljcm9zb2Z0LmNvbS9hZGRvbnMnKVxuICAgICAgICAgICAgJiYgIXVybC5zdGFydHNXaXRoKCd2aWV3LXNvdXJjZScpXG4gICAgICAgICk7XG4gICAgfVxuICAgIHJldHVybiBCb29sZWFuKHVybFxuICAgICAgICAmJiAhdXJsLnN0YXJ0c1dpdGgoJ2Nocm9tZScpXG4gICAgICAgICYmICF1cmwuc3RhcnRzV2l0aCgnaHR0cHM6Ly9jaHJvbWUuZ29vZ2xlLmNvbS93ZWJzdG9yZScpXG4gICAgICAgICYmICF1cmwuc3RhcnRzV2l0aCgnaHR0cHM6Ly9jaHJvbWV3ZWJzdG9yZS5nb29nbGUuY29tLycpXG4gICAgICAgICYmICF1cmwuc3RhcnRzV2l0aCgnZGF0YScpXG4gICAgICAgICYmICF1cmwuc3RhcnRzV2l0aCgnZGV2dG9vbHMnKVxuICAgICAgICAmJiAhdXJsLnN0YXJ0c1dpdGgoJ3ZpZXctc291cmNlJylcbiAgICApO1xufVxuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gcmVhZFN5bmNTdG9yYWdlPFQgZXh0ZW5kcyB7W2tleTogc3RyaW5nXTogYW55fT4oZGVmYXVsdHM6IFQpOiBQcm9taXNlPFQgfCBudWxsPiB7XG4gICAgcmV0dXJuIG5ldyBQcm9taXNlPFQgfCBudWxsPigocmVzb2x2ZSkgPT4ge1xuICAgICAgICBjaHJvbWUuc3RvcmFnZS5zeW5jLmdldChudWxsLCAoc3luYzogYW55KSA9PiB7XG4gICAgICAgICAgICBpZiAoY2hyb21lLnJ1bnRpbWUubGFzdEVycm9yKSB7XG4gICAgICAgICAgICAgICAgY29uc29sZS5lcnJvcihjaHJvbWUucnVudGltZS5sYXN0RXJyb3IubWVzc2FnZSk7XG4gICAgICAgICAgICAgICAgcmVzb2x2ZShudWxsKTtcbiAgICAgICAgICAgICAgICByZXR1cm47XG4gICAgICAgICAgICB9XG5cbiAgICAgICAgICAgIGZvciAoY29uc3Qga2V5IGluIHN5bmMpIHtcbiAgICAgICAgICAgICAgICAvLyBKdXN0IHRvIGJlIHN1cmU6IGh0dHBzOi8vZ2l0aHViLmNvbS9kYXJrcmVhZGVyL2RhcmtyZWFkZXIvaXNzdWVzLzcyNzBcbiAgICAgICAgICAgICAgICAvLyBUaGUgdmFsdWUgb2Ygc3luY1trZXldIHNob3VsZG4ndCBiZSBudWxsLlxuICAgICAgICAgICAgICAgIGlmICghc3luY1trZXldKSB7XG4gICAgICAgICAgICAgICAgICAgIGNvbnRpbnVlO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICBjb25zdCBtZXRhS2V5c0NvdW50ID0gc3luY1trZXldLl9fbWV0YV9zcGxpdF9jb3VudDtcbiAgICAgICAgICAgICAgICBpZiAoIW1ldGFLZXlzQ291bnQpIHtcbiAgICAgICAgICAgICAgICAgICAgY29udGludWU7XG4gICAgICAgICAgICAgICAgfVxuXG4gICAgICAgICAgICAgICAgbGV0IHN0cmluZyA9ICcnO1xuICAgICAgICAgICAgICAgIGZvciAobGV0IGkgPSAwOyBpIDwgbWV0YUtleXNDb3VudDsgaSsrKSB7XG4gICAgICAgICAgICAgICAgICAgIHN0cmluZyArPSBzeW5jW2Ake2tleX1fJHtpLnRvU3RyaW5nKDM2KX1gXTtcbiAgICAgICAgICAgICAgICAgICAgZGVsZXRlIHN5bmNbYCR7a2V5fV8ke2kudG9TdHJpbmcoMzYpfWBdO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICB0cnkge1xuICAgICAgICAgICAgICAgICAgICBzeW5jW2tleV0gPSBKU09OLnBhcnNlKHN0cmluZyk7XG4gICAgICAgICAgICAgICAgfSBjYXRjaCAoZXJyb3IpIHtcbiAgICAgICAgICAgICAgICAgICAgY29uc29sZS5lcnJvcihgc3luY1ske2tleX1dOiBDb3VsZCBub3QgcGFyc2UgcmVjb3JkIGZyb20gc3luYyBzdG9yYWdlOiAke3N0cmluZ31gKTtcbiAgICAgICAgICAgICAgICAgICAgcmVzb2x2ZShudWxsKTtcbiAgICAgICAgICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH1cblxuICAgICAgICAgICAgc3luYyA9IHtcbiAgICAgICAgICAgICAgICAuLi5kZWZhdWx0cyxcbiAgICAgICAgICAgICAgICAuLi5zeW5jLFxuICAgICAgICAgICAgfTtcblxuICAgICAgICAgICAgcmVzb2x2ZShzeW5jKTtcbiAgICAgICAgfSk7XG4gICAgfSk7XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiByZWFkTG9jYWxTdG9yYWdlPFQgZXh0ZW5kcyB7W2tleTogc3RyaW5nXTogYW55fT4oZGVmYXVsdHM6IFQpOiBQcm9taXNlPFQ+IHtcbiAgICByZXR1cm4gbmV3IFByb21pc2U8VD4oKHJlc29sdmUpID0+IHtcbiAgICAgICAgY2hyb21lLnN0b3JhZ2UubG9jYWwuZ2V0KGRlZmF1bHRzLCAobG9jYWw6IFQpID0+IHtcbiAgICAgICAgICAgIGlmIChjaHJvbWUucnVudGltZS5sYXN0RXJyb3IpIHtcbiAgICAgICAgICAgICAgICBjb25zb2xlLmVycm9yKGNocm9tZS5ydW50aW1lLmxhc3RFcnJvci5tZXNzYWdlKTtcbiAgICAgICAgICAgICAgICByZXNvbHZlKGRlZmF1bHRzKTtcbiAgICAgICAgICAgICAgICByZXR1cm47XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICByZXNvbHZlKGxvY2FsKTtcbiAgICAgICAgfSk7XG4gICAgfSk7XG59XG5cbmZ1bmN0aW9uIHByZXBhcmVTeW5jU3RvcmFnZTxUIGV4dGVuZHMge1trZXk6IHN0cmluZ106IGFueX0+KHZhbHVlczogVCk6IHtba2V5OiBzdHJpbmddOiBhbnl9IHtcbiAgICBmb3IgKGNvbnN0IGtleSBpbiB2YWx1ZXMpIHtcbiAgICAgICAgY29uc3QgdmFsdWUgPSB2YWx1ZXNba2V5XTtcbiAgICAgICAgY29uc3Qgc3RyaW5nID0gSlNPTi5zdHJpbmdpZnkodmFsdWUpO1xuICAgICAgICAvLyBUaGUgbWF4aW11bSBzaXplIG9mIGFueSBvbmUgaXRlbSB0aGF0IGVhY2ggZXh0ZW5zaW9uIGlzIGFsbG93ZWQgdG8gc3RvcmUgaW4gdGhlIHN5bmMgc3RvcmFnZSBhcmVhLFxuICAgICAgICAvLyBhcyBtZWFzdXJlZCBieSB0aGUgSlNPTiBzdHJpbmdpZmljYXRpb24gb2YgdGhlIGl0ZW0ncyB2YWx1ZSBwbHVzIHRoZSBsZW5ndGggb2YgaXRzIGtleS5cbiAgICAgICAgLy8gU291cmNlOiBodHRwczovL2RldmVsb3Blci5tb3ppbGxhLm9yZy9lbi1VUy9kb2NzL01vemlsbGEvQWRkLW9ucy9XZWJFeHRlbnNpb25zL0FQSS9zdG9yYWdlL3N5bmNcbiAgICAgICAgY29uc3QgdG90YWxMZW5ndGggPSBzdHJpbmcubGVuZ3RoICsga2V5Lmxlbmd0aDtcbiAgICAgICAgaWYgKHRvdGFsTGVuZ3RoID4gY2hyb21lLnN0b3JhZ2Uuc3luYy5RVU9UQV9CWVRFU19QRVJfSVRFTSkge1xuICAgICAgICAgICAgLy8gVGhpcyBsZW5ndGggbGltaXQgcGVybWl0cyB1cyB0byBzdG9yZSB1cCB0byAxMDAwID0gKHBhcnNlSW50KCdycicsIDM2KSArIDEpIHJlY29yZHMuXG4gICAgICAgICAgICBjb25zdCBtYXhMZW5ndGggPSBjaHJvbWUuc3RvcmFnZS5zeW5jLlFVT1RBX0JZVEVTX1BFUl9JVEVNIC0ga2V5Lmxlbmd0aCAtIDEgLSAyO1xuICAgICAgICAgICAgY29uc3QgbWluaW1hbEtleXNOZWVkZWQgPSBNYXRoLmNlaWwoc3RyaW5nLmxlbmd0aCAvIG1heExlbmd0aCk7XG4gICAgICAgICAgICBmb3IgKGxldCBpID0gMDsgaSA8IG1pbmltYWxLZXlzTmVlZGVkOyBpKyspIHtcbiAgICAgICAgICAgICAgICAodmFsdWVzIGFzIGFueSlbYCR7a2V5fV8ke2kudG9TdHJpbmcoMzYpfWBdID0gc3RyaW5nLnN1YnN0cmluZyhpICogbWF4TGVuZ3RoLCAoaSArIDEpICogbWF4TGVuZ3RoKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgICh2YWx1ZXMgYXMgYW55KVtrZXldID0ge1xuICAgICAgICAgICAgICAgIF9fbWV0YV9zcGxpdF9jb3VudDogbWluaW1hbEtleXNOZWVkZWQsXG4gICAgICAgICAgICB9O1xuICAgICAgICB9XG4gICAgfVxuICAgIHJldHVybiB2YWx1ZXM7XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiB3cml0ZVN5bmNTdG9yYWdlPFQgZXh0ZW5kcyB7W2tleTogc3RyaW5nXTogYW55fT4odmFsdWVzOiBUKTogUHJvbWlzZTx2b2lkPiB7XG4gICAgcmV0dXJuIG5ldyBQcm9taXNlPHZvaWQ+KChyZXNvbHZlLCByZWplY3QpID0+IHtcbiAgICAgICAgY29uc3QgcGFja2FnZWQgPSBwcmVwYXJlU3luY1N0b3JhZ2UodmFsdWVzKTtcbiAgICAgICAgY2hyb21lLnN0b3JhZ2Uuc3luYy5zZXQocGFja2FnZWQsICgpID0+IHtcbiAgICAgICAgICAgIGlmIChjaHJvbWUucnVudGltZS5sYXN0RXJyb3IpIHtcbiAgICAgICAgICAgICAgICByZWplY3QoY2hyb21lLnJ1bnRpbWUubGFzdEVycm9yKTtcbiAgICAgICAgICAgICAgICByZXR1cm47XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICByZXNvbHZlKCk7XG4gICAgICAgIH0pO1xuICAgIH0pO1xufVxuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gd3JpdGVMb2NhbFN0b3JhZ2U8VCBleHRlbmRzIHtba2V5OiBzdHJpbmddOiBhbnl9Pih2YWx1ZXM6IFQpOiBQcm9taXNlPHZvaWQ+IHtcbiAgICByZXR1cm4gbmV3IFByb21pc2U8dm9pZD4oKHJlc29sdmUpID0+IHtcbiAgICAgICAgY2hyb21lLnN0b3JhZ2UubG9jYWwuc2V0KHZhbHVlcywgKCkgPT4ge1xuICAgICAgICAgICAgcmVzb2x2ZSgpO1xuICAgICAgICB9KTtcbiAgICB9KTtcbn1cblxuZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIHJlbW92ZVN5bmNTdG9yYWdlKGtleXM6IHN0cmluZ1tdKTogUHJvbWlzZTx2b2lkPiB7XG4gICAgcmV0dXJuIG5ldyBQcm9taXNlPHZvaWQ+KChyZXNvbHZlKSA9PiB7XG4gICAgICAgIGNocm9tZS5zdG9yYWdlLnN5bmMucmVtb3ZlKGtleXMsICgpID0+IHtcbiAgICAgICAgICAgIHJlc29sdmUoKTtcbiAgICAgICAgfSk7XG4gICAgfSk7XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiByZW1vdmVMb2NhbFN0b3JhZ2Uoa2V5czogc3RyaW5nW10pOiBQcm9taXNlPHZvaWQ+IHtcbiAgICByZXR1cm4gbmV3IFByb21pc2U8dm9pZD4oKHJlc29sdmUpID0+IHtcbiAgICAgICAgY2hyb21lLnN0b3JhZ2UubG9jYWwucmVtb3ZlKGtleXMsICgpID0+IHtcbiAgICAgICAgICAgIHJlc29sdmUoKTtcbiAgICAgICAgfSk7XG4gICAgfSk7XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiBnZXRDb21tYW5kcygpOiBQcm9taXNlPGNocm9tZS5jb21tYW5kcy5Db21tYW5kW10+IHtcbiAgICByZXR1cm4gbmV3IFByb21pc2U8Y2hyb21lLmNvbW1hbmRzLkNvbW1hbmRbXT4oKHJlc29sdmUpID0+IHtcbiAgICAgICAgaWYgKCFjaHJvbWUuY29tbWFuZHMpIHtcbiAgICAgICAgICAgIHJlc29sdmUoW10pO1xuICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICB9XG4gICAgICAgIGNocm9tZS5jb21tYW5kcy5nZXRBbGwoKGNvbW1hbmRzKSA9PiB7XG4gICAgICAgICAgICBpZiAoY29tbWFuZHMpIHtcbiAgICAgICAgICAgICAgICByZXNvbHZlKGNvbW1hbmRzKTtcbiAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgcmVzb2x2ZShbXSk7XG4gICAgICAgICAgICB9XG4gICAgICAgIH0pO1xuICAgIH0pO1xufVxuXG5leHBvcnQgZnVuY3Rpb24ga2VlcExpc3RlbmluZ1RvRXZlbnRzKCk6ICgpID0+IHZvaWQge1xuICAgIGxldCBpbnRlcnZhbElkID0gMDtcbiAgICBjb25zdCBrZWVwSG9wZUFsaXZlID0gKCkgPT4ge1xuICAgICAgICBpbnRlcnZhbElkID0gc2V0SW50ZXJ2YWwoY2hyb21lLnJ1bnRpbWUuZ2V0UGxhdGZvcm1JbmZvLCBnZXREdXJhdGlvbih7c2Vjb25kczogMTB9KSk7XG4gICAgfTtcbiAgICBjaHJvbWUucnVudGltZS5vblN0YXJ0dXAuYWRkTGlzdGVuZXIoa2VlcEhvcGVBbGl2ZSk7XG4gICAga2VlcEhvcGVBbGl2ZSgpO1xuICAgIGNvbnN0IHN0b3BMaXN0ZW5pbmcgPSAoKSA9PiB7XG4gICAgICAgIGNsZWFySW50ZXJ2YWwoaW50ZXJ2YWxJZCk7XG4gICAgICAgIGNocm9tZS5ydW50aW1lLm9uU3RhcnR1cC5yZW1vdmVMaXN0ZW5lcihrZWVwSG9wZUFsaXZlKTtcbiAgICB9O1xuICAgIHJldHVybiBzdG9wTGlzdGVuaW5nO1xufVxuIiwiaW1wb3J0IHtnZXRVSUxhbmd1YWdlfSBmcm9tICcuL2xvY2FsZXMnO1xuaW1wb3J0IHtpc0VkZ2UsIGlzTW9iaWxlfSBmcm9tICcuL3BsYXRmb3JtJztcblxuZXhwb3J0IGNvbnN0IEhPTUVQQUdFX1VSTCA9ICdodHRwczovL2RhcmtyZWFkZXIub3JnJztcbmV4cG9ydCBjb25zdCBCTE9HX1VSTCA9ICdodHRwczovL2RhcmtyZWFkZXIub3JnL2Jsb2cvJztcbmV4cG9ydCBjb25zdCBORVdTX1VSTCA9ICdodHRwczovL2RhcmtyZWFkZXIub3JnL2Jsb2cvcG9zdHMuanNvbic7XG5leHBvcnQgY29uc3QgREVWVE9PTFNfRE9DU19VUkwgPSAnaHR0cHM6Ly9naXRodWIuY29tL2RhcmtyZWFkZXIvZGFya3JlYWRlci9ibG9iL21haW4vQ09OVFJJQlVUSU5HLm1kJztcbmV4cG9ydCBjb25zdCBET05BVEVfVVJMID0gJ2h0dHBzOi8vZGFya3JlYWRlci5vcmcvc3VwcG9ydC11cy8nO1xuZXhwb3J0IGNvbnN0IEdJVEhVQl9VUkwgPSAnaHR0cHM6Ly9naXRodWIuY29tL2RhcmtyZWFkZXIvZGFya3JlYWRlcic7XG5leHBvcnQgY29uc3QgTU9CSUxFX1VSTCA9ICdodHRwczovL2RhcmtyZWFkZXIub3JnL3RpcHMvbW9iaWxlLyc7XG5leHBvcnQgY29uc3QgUFJJVkFDWV9VUkwgPSAnaHR0cHM6Ly9kYXJrcmVhZGVyLm9yZy9wcml2YWN5Lyc7XG5leHBvcnQgY29uc3QgVFdJVFRFUl9VUkwgPSAnaHR0cHM6Ly90d2l0dGVyLmNvbS9kYXJrcmVhZGVyYXBwJztcbmV4cG9ydCBjb25zdCBVTklOU1RBTExfVVJMID0gJ2h0dHBzOi8vZGFya3JlYWRlci5vcmcvZ29vZGx1Y2svJztcbmV4cG9ydCBjb25zdCBIRUxQX1VSTCA9ICdodHRwczovL2RhcmtyZWFkZXIub3JnL2hlbHAnO1xuZXhwb3J0IGNvbnN0IENPTkZJR19VUkxfQkFTRSA9ICdodHRwczovL3Jhdy5naXRodWJ1c2VyY29udGVudC5jb20vZGFya3JlYWRlci9kYXJrcmVhZGVyL21haW4vc3JjL2NvbmZpZyc7XG5cbmNvbnN0IGhlbHBMb2NhbGVzID0gW1xuICAgICdiZScsXG4gICAgJ2NzJyxcbiAgICAnZGUnLFxuICAgICdlbicsXG4gICAgJ2VzJyxcbiAgICAnZnInLFxuICAgICdpdCcsXG4gICAgJ2phJyxcbiAgICAnbmwnLFxuICAgICdwdCcsXG4gICAgJ3J1JyxcbiAgICAnc3InLFxuICAgICd0cicsXG4gICAgJ3poLUNOJyxcbiAgICAnemgtVFcnLFxuXTtcblxuZXhwb3J0IGZ1bmN0aW9uIGdldEhlbHBVUkwoKTogc3RyaW5nIHtcbiAgICBpZiAoaXNFZGdlICYmIGlzTW9iaWxlKSB7XG4gICAgICAgIHJldHVybiBgJHtIRUxQX1VSTH0vbW9iaWxlL2A7XG4gICAgfVxuICAgIGNvbnN0IGxvY2FsZSA9IGdldFVJTGFuZ3VhZ2UoKTtcbiAgICBjb25zdCBtYXRjaExvY2FsZSA9IGhlbHBMb2NhbGVzLmZpbmQoKGhsKSA9PiBobCA9PT0gbG9jYWxlKSB8fCBoZWxwTG9jYWxlcy5maW5kKChobCkgPT4gbG9jYWxlLnN0YXJ0c1dpdGgoaGwpKSB8fCAnZW4nO1xuICAgIHJldHVybiBgJHtIRUxQX1VSTH0vJHttYXRjaExvY2FsZX0vYDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGdldEJsb2dQb3N0VVJMKHBvc3RJZDogc3RyaW5nKTogc3RyaW5nIHtcbiAgICByZXR1cm4gYCR7QkxPR19VUkx9JHtwb3N0SWR9L2A7XG59XG4iLCJpbXBvcnQge2lzTWF0Y2hNZWRpYUNoYW5nZUV2ZW50TGlzdGVuZXJTdXBwb3J0ZWR9IGZyb20gJy4vcGxhdGZvcm0nO1xuXG5kZWNsYXJlIGNvbnN0IF9fVEVTVF9fOiBib29sZWFuO1xubGV0IG92ZXJyaWRlOiBib29sZWFuIHwgbnVsbCA9IG51bGw7XG5cbmxldCBxdWVyeTogTWVkaWFRdWVyeUxpc3QgfCBudWxsID0gbnVsbDtcbmNvbnN0IG9uQ2hhbmdlOiAoe21hdGNoZXN9OiB7bWF0Y2hlczogYm9vbGVhbn0pID0+IHZvaWQgPSAoe21hdGNoZXN9KSA9PiBsaXN0ZW5lcnMuZm9yRWFjaCgobGlzdGVuZXIpID0+IGxpc3RlbmVyKG1hdGNoZXMpKTtcbmNvbnN0IGxpc3RlbmVycyA9IG5ldyBTZXQ8KGlzRGFyazogYm9vbGVhbikgPT4gdm9pZD4oKTtcblxuZXhwb3J0IGZ1bmN0aW9uIHJ1bkNvbG9yU2NoZW1lQ2hhbmdlRGV0ZWN0b3IoY2FsbGJhY2s6IChpc0Rhcms6IGJvb2xlYW4pID0+IHZvaWQpOiB2b2lkIHtcbiAgICBsaXN0ZW5lcnMuYWRkKGNhbGxiYWNrKTtcbiAgICBpZiAocXVlcnkpIHtcbiAgICAgICAgcmV0dXJuO1xuICAgIH1cbiAgICBxdWVyeSA9IG1hdGNoTWVkaWEoJyhwcmVmZXJzLWNvbG9yLXNjaGVtZTogZGFyayknKTtcbiAgICBpZiAoaXNNYXRjaE1lZGlhQ2hhbmdlRXZlbnRMaXN0ZW5lclN1cHBvcnRlZCkge1xuICAgICAgICAvLyBNZWRpYVF1ZXJ5TGlzdCBjaGFuZ2UgZXZlbnQgaXMgbm90IGNhbmNlbGxhYmxlIGFuZCBkb2VzIG5vdCBidWJibGVcbiAgICAgICAgcXVlcnkuYWRkRXZlbnRMaXN0ZW5lcignY2hhbmdlJywgb25DaGFuZ2UpO1xuICAgIH0gZWxzZSB7XG4gICAgICAgIHF1ZXJ5LmFkZExpc3RlbmVyKG9uQ2hhbmdlKTtcbiAgICB9XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBzdG9wQ29sb3JTY2hlbWVDaGFuZ2VEZXRlY3RvcigpOiB2b2lkIHtcbiAgICBpZiAoIXF1ZXJ5IHx8ICFvbkNoYW5nZSkge1xuICAgICAgICByZXR1cm47XG4gICAgfVxuICAgIGlmIChpc01hdGNoTWVkaWFDaGFuZ2VFdmVudExpc3RlbmVyU3VwcG9ydGVkKSB7XG4gICAgICAgIHF1ZXJ5LnJlbW92ZUV2ZW50TGlzdGVuZXIoJ2NoYW5nZScsIG9uQ2hhbmdlKTtcbiAgICB9IGVsc2Uge1xuICAgICAgICBxdWVyeS5yZW1vdmVMaXN0ZW5lcihvbkNoYW5nZSk7XG4gICAgfVxuICAgIGxpc3RlbmVycy5jbGVhcigpO1xuICAgIHF1ZXJ5ID0gbnVsbDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGVtdWxhdGVDb2xvclNjaGVtZShjb2xvclNjaGVtZTogJ2xpZ2h0JyB8ICdkYXJrJyk6IHZvaWQge1xuICAgIGlmIChfX1RFU1RfXykge1xuICAgICAgICBjb25zdCBpc0RhcmsgPSBjb2xvclNjaGVtZSA9PT0gJ2RhcmsnO1xuICAgICAgICBvdmVycmlkZSA9IGlzRGFyaztcbiAgICAgICAgbGlzdGVuZXJzLmZvckVhY2goKGwpID0+IGwoaXNEYXJrKSk7XG4gICAgfVxufVxuXG5leHBvcnQgY29uc3QgaXNTeXN0ZW1EYXJrTW9kZUVuYWJsZWQgPSAoKTogYm9vbGVhbiA9PiAoX19URVNUX18gJiYgdHlwZW9mIG92ZXJyaWRlID09PSAnYm9vbGVhbicpID8gb3ZlcnJpZGUgOiAocXVlcnkgfHwgbWF0Y2hNZWRpYSgnKHByZWZlcnMtY29sb3Itc2NoZW1lOiBkYXJrKScpKS5tYXRjaGVzO1xuIiwiZXhwb3J0IGVudW0gTWVzc2FnZVR5cGVVSXRvQkcge1xuICAgIEdFVF9EQVRBID0gJ3VpLWJnLWdldC1kYXRhJyxcbiAgICBHRVRfREVWVE9PTFNfREFUQSA9ICd1aS1iZy1nZXQtZGV2dG9vbHMtZGF0YScsXG4gICAgU1VCU0NSSUJFX1RPX0NIQU5HRVMgPSAndWktYmctc3Vic2NyaWJlLXRvLWNoYW5nZXMnLFxuICAgIFVOU1VCU0NSSUJFX0ZST01fQ0hBTkdFUyA9ICd1aS1iZy11bnN1YnNjcmliZS1mcm9tLWNoYW5nZXMnLFxuICAgIENIQU5HRV9TRVRUSU5HUyA9ICd1aS1iZy1jaGFuZ2Utc2V0dGluZ3MnLFxuICAgIFNFVF9USEVNRSA9ICd1aS1iZy1zZXQtdGhlbWUnLFxuICAgIFRPR0dMRV9BQ1RJVkVfVEFCID0gJ3VpLWJnLXRvZ2dsZS1hY3RpdmUtdGFiJyxcbiAgICBNQVJLX05FV1NfQVNfUkVBRCA9ICd1aS1iZy1tYXJrLW5ld3MtYXMtcmVhZCcsXG4gICAgTUFSS19ORVdTX0FTX0RJU1BMQVlFRCA9ICd1aS1iZy1tYXJrLW5ld3MtYXMtZGlzcGxheWVkJyxcbiAgICBMT0FEX0NPTkZJRyA9ICd1aS1iZy1sb2FkLWNvbmZpZycsXG4gICAgQVBQTFlfREVWX0RZTkFNSUNfVEhFTUVfRklYRVMgPSAndWktYmctYXBwbHktZGV2LWR5bmFtaWMtdGhlbWUtZml4ZXMnLFxuICAgIFJFU0VUX0RFVl9EWU5BTUlDX1RIRU1FX0ZJWEVTID0gJ3VpLWJnLXJlc2V0LWRldi1keW5hbWljLXRoZW1lLWZpeGVzJyxcbiAgICBBUFBMWV9ERVZfSU5WRVJTSU9OX0ZJWEVTID0gJ3VpLWJnLWFwcGx5LWRldi1pbnZlcnNpb24tZml4ZXMnLFxuICAgIFJFU0VUX0RFVl9JTlZFUlNJT05fRklYRVMgPSAndWktYmctcmVzZXQtZGV2LWludmVyc2lvbi1maXhlcycsXG4gICAgQVBQTFlfREVWX1NUQVRJQ19USEVNRVMgPSAndWktYmctYXBwbHktZGV2LXN0YXRpYy10aGVtZXMnLFxuICAgIFJFU0VUX0RFVl9TVEFUSUNfVEhFTUVTID0gJ3VpLWJnLXJlc2V0LWRldi1zdGF0aWMtdGhlbWVzJyxcbiAgICBTVEFSVF9BQ1RJVkFUSU9OID0gJ3VpLWJnLXN0YXJ0LWFjdGl2YXRpb24nLFxuICAgIFJFU0VUX0FDVElWQVRJT04gPSAndWktYmctcmVzZXQtYWN0aXZhdGlvbicsXG4gICAgQ09MT1JfU0NIRU1FX0NIQU5HRSA9ICd1aS1iZy1jb2xvci1zY2hlbWUtY2hhbmdlJyxcbiAgICBISURFX0hJR0hMSUdIVFMgPSAndWktYmctaGlkZS1oaWdobGlnaHRzJ1xufVxuXG5leHBvcnQgZW51bSBNZXNzYWdlVHlwZUJHdG9VSSB7XG4gICAgQ0hBTkdFUyA9ICdiZy11aS1jaGFuZ2VzJ1xufVxuXG5leHBvcnQgZW51bSBEZWJ1Z01lc3NhZ2VUeXBlQkd0b1VJIHtcbiAgICBDU1NfVVBEQVRFID0gJ2RlYnVnLWJnLXVpLWNzcy11cGRhdGUnLFxuICAgIFVQREFURSA9ICdkZWJ1Zy1iZy11aS11cGRhdGUnXG59XG5cbmV4cG9ydCBlbnVtIE1lc3NhZ2VUeXBlQkd0b0NTIHtcbiAgICBBRERfQ1NTX0ZJTFRFUiA9ICdiZy1jcy1hZGQtY3NzLWZpbHRlcicsXG4gICAgQUREX0RZTkFNSUNfVEhFTUUgPSAnYmctY3MtYWRkLWR5bmFtaWMtdGhlbWUnLFxuICAgIEFERF9TVEFUSUNfVEhFTUUgPSAnYmctY3MtYWRkLXN0YXRpYy10aGVtZScsXG4gICAgQUREX1NWR19GSUxURVIgPSAnYmctY3MtYWRkLXN2Zy1maWx0ZXInLFxuICAgIENMRUFOX1VQID0gJ2JnLWNzLWNsZWFuLXVwJyxcbiAgICBGRVRDSF9SRVNQT05TRSA9ICdiZy1jcy1mZXRjaC1yZXNwb25zZScsXG4gICAgVU5TVVBQT1JURURfU0VOREVSID0gJ2JnLWNzLXVuc3VwcG9ydGVkLXNlbmRlcidcbn1cblxuZXhwb3J0IGVudW0gRGVidWdNZXNzYWdlVHlwZUJHdG9DUyB7XG4gICAgUkVMT0FEID0gJ2RlYnVnLWJnLWNzLXJlbG9hZCdcbn1cblxuZXhwb3J0IGVudW0gTWVzc2FnZVR5cGVDU3RvQkcge1xuICAgIENPTE9SX1NDSEVNRV9DSEFOR0UgPSAnY3MtYmctY29sb3Itc2NoZW1lLWNoYW5nZScsXG4gICAgREFSS19USEVNRV9ERVRFQ1RFRCA9ICdjcy1iZy1kYXJrLXRoZW1lLWRldGVjdGVkJyxcbiAgICBEQVJLX1RIRU1FX05PVF9ERVRFQ1RFRCA9ICdjcy1iZy1kYXJrLXRoZW1lLW5vdC1kZXRlY3RlZCcsXG4gICAgRkVUQ0ggPSAnY3MtYmctZmV0Y2gnLFxuICAgIERPQ1VNRU5UX0NPTk5FQ1QgPSAnY3MtYmctZG9jdW1lbnQtY29ubmVjdCcsXG4gICAgRE9DVU1FTlRfRk9SR0VUID0gJ2NzLWJnLWRvY3VtZW50LWZvcmdldCcsXG4gICAgRE9DVU1FTlRfRlJFRVpFID0gJ2NzLWJnLWRvY3VtZW50LWZyZWV6ZScsXG4gICAgRE9DVU1FTlRfUkVTVU1FID0gJ2NzLWJnLWRvY3VtZW50LXJlc3VtZSdcbn1cblxuZXhwb3J0IGVudW0gRGVidWdNZXNzYWdlVHlwZUNTdG9CRyB7XG4gICAgTE9HID0gJ2RlYnVnLWNzLWJnLWxvZydcbn1cblxuZXhwb3J0IGVudW0gTWVzc2FnZVR5cGVDU3RvVUkge1xuICAgIEVYUE9SVF9DU1NfUkVTUE9OU0UgPSAnY3MtdWktZXhwb3J0LWNzcy1yZXNwb25zZSdcbn1cblxuZXhwb3J0IGVudW0gTWVzc2FnZVR5cGVVSXRvQ1Mge1xuICAgIEVYUE9SVF9DU1MgPSAndWktY3MtZXhwb3J0LWNzcydcbn1cbiIsImV4cG9ydCBpbnRlcmZhY2UgVGV4dFJhbmdlIHtcbiAgICBzdGFydDogbnVtYmVyO1xuICAgIGVuZDogbnVtYmVyO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gZ2V0VGV4dFBvc2l0aW9uTWVzc2FnZSh0ZXh0OiBzdHJpbmcsIGluZGV4OiBudW1iZXIpOiBzdHJpbmcge1xuICAgIGlmICghaXNGaW5pdGUoaW5kZXgpKSB7XG4gICAgICAgIHRocm93IG5ldyBFcnJvcihgV3JvbmcgY2hhciBpbmRleCAke2luZGV4fWApO1xuICAgIH1cbiAgICBsZXQgbWVzc2FnZSA9ICcnO1xuICAgIGxldCBsaW5lID0gMDtcbiAgICBsZXQgcHJldkxuOiBudW1iZXI7XG4gICAgbGV0IG5leHRMbiA9IDA7XG4gICAgZG8ge1xuICAgICAgICBsaW5lKys7XG4gICAgICAgIHByZXZMbiA9IG5leHRMbjtcbiAgICAgICAgbmV4dExuID0gdGV4dC5pbmRleE9mKCdcXG4nLCBwcmV2TG4gKyAxKTtcbiAgICB9IHdoaWxlIChuZXh0TG4gPj0gMCAmJiBuZXh0TG4gPD0gaW5kZXgpO1xuICAgIGNvbnN0IGNvbHVtbiA9IGluZGV4IC0gcHJldkxuO1xuICAgIG1lc3NhZ2UgKz0gYGxpbmUgJHtsaW5lfSwgY29sdW1uICR7Y29sdW1ufWA7XG4gICAgbWVzc2FnZSArPSAnXFxuJztcbiAgICBpZiAoaW5kZXggPCB0ZXh0Lmxlbmd0aCkge1xuICAgICAgICBtZXNzYWdlICs9IHRleHQuc3Vic3RyaW5nKHByZXZMbiArIDEsIG5leHRMbik7XG4gICAgfSBlbHNlIHtcbiAgICAgICAgbWVzc2FnZSArPSB0ZXh0LnN1YnN0cmluZyh0ZXh0Lmxhc3RJbmRleE9mKCdcXG4nKSArIDEpO1xuICAgIH1cbiAgICBtZXNzYWdlICs9ICdcXG4nO1xuICAgIG1lc3NhZ2UgKz0gYCR7bmV3IEFycmF5KGNvbHVtbikuam9pbignLScpfV5gO1xuICAgIHJldHVybiBtZXNzYWdlO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gZ2V0VGV4dERpZmZJbmRleChhOiBzdHJpbmcsIGI6IHN0cmluZyk6IG51bWJlciB7XG4gICAgY29uc3Qgc2hvcnQgPSBNYXRoLm1pbihhLmxlbmd0aCwgYi5sZW5ndGgpO1xuICAgIGZvciAobGV0IGkgPSAwOyBpIDwgc2hvcnQ7IGkrKykge1xuICAgICAgICBpZiAoYVtpXSAhPT0gYltpXSkge1xuICAgICAgICAgICAgcmV0dXJuIGk7XG4gICAgICAgIH1cbiAgICB9XG4gICAgaWYgKGEubGVuZ3RoICE9PSBiLmxlbmd0aCkge1xuICAgICAgICByZXR1cm4gc2hvcnQ7XG4gICAgfVxuICAgIHJldHVybiAtMTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIHBhcnNlQXJyYXkodGV4dDogc3RyaW5nKTogc3RyaW5nW10ge1xuICAgIHJldHVybiB0ZXh0LnJlcGxhY2UoL1xcci9nLCAnJylcbiAgICAgICAgLnNwbGl0KCdcXG4nKVxuICAgICAgICAubWFwKChzKSA9PiBzLnRyaW0oKSlcbiAgICAgICAgLmZpbHRlcigocykgPT4gcyk7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBmb3JtYXRBcnJheShhcnI6IHJlYWRvbmx5IHN0cmluZ1tdKTogc3RyaW5nIHtcbiAgICByZXR1cm4gYXJyLmNvbmNhdCgnJykuam9pbignXFxuJyk7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBnZXRNYXRjaGVzKHJlZ2V4OiBSZWdFeHAsIGlucHV0OiBzdHJpbmcsIGdyb3VwID0gMCk6IHN0cmluZ1tdIHtcbiAgICBjb25zdCBtYXRjaGVzOiBzdHJpbmdbXSA9IFtdO1xuICAgIGxldCBtOiBSZWdFeHBNYXRjaEFycmF5IHwgbnVsbDtcbiAgICB3aGlsZSAoKG0gPSByZWdleC5leGVjKGlucHV0KSkpIHtcbiAgICAgICAgbWF0Y2hlcy5wdXNoKG1bZ3JvdXBdKTtcbiAgICB9XG4gICAgcmV0dXJuIG1hdGNoZXM7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBnZXRNYXRjaGVzV2l0aE9mZnNldHMocmVnZXg6IFJlZ0V4cCwgaW5wdXQ6IHN0cmluZywgZ3JvdXAgPSAwKTogQXJyYXk8e3RleHQ6IHN0cmluZzsgb2Zmc2V0OiBudW1iZXJ9PiB7XG4gICAgY29uc3QgbWF0Y2hlczogQXJyYXk8e3RleHQ6IHN0cmluZzsgb2Zmc2V0OiBudW1iZXJ9PiA9IFtdO1xuICAgIGxldCBtOiBSZWdFeHBNYXRjaEFycmF5IHwgbnVsbDtcbiAgICB3aGlsZSAoKG0gPSByZWdleC5leGVjKGlucHV0KSkpIHtcbiAgICAgICAgbWF0Y2hlcy5wdXNoKHt0ZXh0OiBtW2dyb3VwXSwgb2Zmc2V0OiBtLmluZGV4IX0pO1xuICAgIH1cbiAgICByZXR1cm4gbWF0Y2hlcztcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGdldFN0cmluZ1NpemUodmFsdWU6IHN0cmluZyk6IG51bWJlciB7XG4gICAgcmV0dXJuIHZhbHVlLmxlbmd0aCAqIDI7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBnZXRIYXNoQ29kZSh0ZXh0OiBzdHJpbmcpOiBudW1iZXIge1xuICAgIGNvbnN0IGxlbiA9IHRleHQubGVuZ3RoO1xuICAgIGxldCBoYXNoID0gMDtcbiAgICBmb3IgKGxldCBpID0gMDsgaSA8IGxlbjsgaSsrKSB7XG4gICAgICAgIGNvbnN0IGMgPSB0ZXh0LmNoYXJDb2RlQXQoaSk7XG4gICAgICAgIGhhc2ggPSAoKGhhc2ggPDwgNSkgLSBoYXNoICsgYykgJiA0Mjk0OTY3Mjk1O1xuICAgIH1cbiAgICByZXR1cm4gaGFzaDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGVzY2FwZVJlZ0V4cFNwZWNpYWxDaGFycyhpbnB1dDogc3RyaW5nKTogc3RyaW5nIHtcbiAgICByZXR1cm4gaW5wdXQucmVwbGFjZUFsbCgvW1xcXiQuKis/XFwoXFwpXFxbXFxde318XFwtXFxcXF0vZywgJ1xcXFwkJicpO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gZ2V0UGFyZW50aGVzZXNSYW5nZShpbnB1dDogc3RyaW5nLCBzZWFyY2hTdGFydEluZGV4ID0gMCk6IFRleHRSYW5nZSB8IG51bGwge1xuICAgIHJldHVybiBnZXRPcGVuQ2xvc2VSYW5nZShpbnB1dCwgc2VhcmNoU3RhcnRJbmRleCwgJygnLCAnKScsIFtdKTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGdldE9wZW5DbG9zZVJhbmdlKFxuICAgIGlucHV0OiBzdHJpbmcsXG4gICAgc2VhcmNoU3RhcnRJbmRleDogbnVtYmVyLFxuICAgIG9wZW5Ub2tlbjogc3RyaW5nLFxuICAgIGNsb3NlVG9rZW46IHN0cmluZyxcbiAgICBleGNsdWRlUmFuZ2VzOiBUZXh0UmFuZ2VbXSxcbik6IFRleHRSYW5nZSB8IG51bGwge1xuICAgIGxldCBpbmRleE9mOiAodG9rZW46IHN0cmluZywgcG9zOiBudW1iZXIpID0+IG51bWJlcjtcbiAgICBpZiAoZXhjbHVkZVJhbmdlcy5sZW5ndGggPT09IDApIHtcbiAgICAgICAgaW5kZXhPZiA9ICh0b2tlbjogc3RyaW5nLCBwb3M6IG51bWJlcikgPT4gaW5wdXQuaW5kZXhPZih0b2tlbiwgcG9zKTtcbiAgICB9IGVsc2Uge1xuICAgICAgICBpbmRleE9mID0gKHRva2VuOiBzdHJpbmcsIHBvczogbnVtYmVyKSA9PiBpbmRleE9mRXhjbHVkaW5nKGlucHV0LCB0b2tlbiwgcG9zLCBleGNsdWRlUmFuZ2VzKTtcbiAgICB9XG5cbiAgICBjb25zdCB7bGVuZ3RofSA9IGlucHV0O1xuICAgIGxldCBkZXB0aCA9IDA7XG4gICAgbGV0IGZpcnN0T3BlbkluZGV4ID0gLTE7XG4gICAgZm9yIChsZXQgaSA9IHNlYXJjaFN0YXJ0SW5kZXg7IGkgPCBsZW5ndGg7IGkrKykge1xuICAgICAgICBpZiAoZGVwdGggPT09IDApIHtcbiAgICAgICAgICAgIGNvbnN0IG9wZW5JbmRleCA9IGluZGV4T2Yob3BlblRva2VuLCBpKTtcbiAgICAgICAgICAgIGlmIChvcGVuSW5kZXggPCAwKSB7XG4gICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICBmaXJzdE9wZW5JbmRleCA9IG9wZW5JbmRleDtcbiAgICAgICAgICAgIGRlcHRoKys7XG4gICAgICAgICAgICBpID0gb3BlbkluZGV4O1xuICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgY29uc3QgY2xvc2VJbmRleCA9IGluZGV4T2YoY2xvc2VUb2tlbiwgaSk7XG4gICAgICAgICAgICBpZiAoY2xvc2VJbmRleCA8IDApIHtcbiAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGNvbnN0IG9wZW5JbmRleCA9IGluZGV4T2Yob3BlblRva2VuLCBpKTtcbiAgICAgICAgICAgIGlmIChvcGVuSW5kZXggPCAwIHx8IGNsb3NlSW5kZXggPD0gb3BlbkluZGV4KSB7XG4gICAgICAgICAgICAgICAgZGVwdGgtLTtcbiAgICAgICAgICAgICAgICBpZiAoZGVwdGggPT09IDApIHtcbiAgICAgICAgICAgICAgICAgICAgcmV0dXJuIHtzdGFydDogZmlyc3RPcGVuSW5kZXgsIGVuZDogY2xvc2VJbmRleCArIDF9O1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICBpID0gY2xvc2VJbmRleDtcbiAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgZGVwdGgrKztcbiAgICAgICAgICAgICAgICBpID0gb3BlbkluZGV4O1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG4gICAgfVxuICAgIHJldHVybiBudWxsO1xufVxuXG5mdW5jdGlvbiBpbmRleE9mRXhjbHVkaW5nKGlucHV0OiBzdHJpbmcsIHNlYXJjaDogc3RyaW5nLCBwb3NpdGlvbjogbnVtYmVyLCBleGNsdWRlUmFuZ2VzOiBUZXh0UmFuZ2VbXSkge1xuICAgIGNvbnN0IGkgPSBpbnB1dC5pbmRleE9mKHNlYXJjaCwgcG9zaXRpb24pO1xuICAgIGNvbnN0IGV4Y2x1c2lvbiA9IGV4Y2x1ZGVSYW5nZXMuZmluZCgocikgPT4gaSA+PSByLnN0YXJ0ICYmIGkgPCByLmVuZCk7XG4gICAgaWYgKGV4Y2x1c2lvbikge1xuICAgICAgICByZXR1cm4gaW5kZXhPZkV4Y2x1ZGluZyhpbnB1dCwgc2VhcmNoLCBleGNsdXNpb24uZW5kLCBleGNsdWRlUmFuZ2VzKTtcbiAgICB9XG4gICAgcmV0dXJuIGk7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBzcGxpdEV4Y2x1ZGluZyhpbnB1dDogc3RyaW5nLCBzZXBhcmF0b3I6IHN0cmluZywgZXhjbHVkZVJhbmdlczogVGV4dFJhbmdlW10pOiBzdHJpbmdbXSB7XG4gICAgY29uc3QgcGFydHM6IHN0cmluZ1tdID0gW107XG4gICAgbGV0IGNvbW1hSW5kZXggPSAtMTtcbiAgICBsZXQgY3VyckluZGV4ID0gMDtcbiAgICB3aGlsZSAoKGNvbW1hSW5kZXggPSBpbmRleE9mRXhjbHVkaW5nKGlucHV0LCBzZXBhcmF0b3IsIGN1cnJJbmRleCwgZXhjbHVkZVJhbmdlcykpID49IDApIHtcbiAgICAgICAgcGFydHMucHVzaChpbnB1dC5zdWJzdHJpbmcoY3VyckluZGV4LCBjb21tYUluZGV4KS50cmltKCkpO1xuICAgICAgICBjdXJySW5kZXggPSBjb21tYUluZGV4ICsgMTtcbiAgICB9XG4gICAgcGFydHMucHVzaChpbnB1dC5zdWJzdHJpbmcoY3VyckluZGV4KS50cmltKCkpO1xuICAgIHJldHVybiBwYXJ0cztcbn1cbiIsImltcG9ydCB0eXBlIHtUaGVtZX0gZnJvbSAnLi4vZGVmaW5pdGlvbnMnO1xuXG4vLyBFeGNsdWRlIGZvbnQgbGlicmFyaWVzIHRvIHByZXNlcnZlIGljb25zXG5jb25zdCBleGNsdWRlZFNlbGVjdG9ycyA9IFtcbiAgICAncHJlJywgJ3ByZSAqJywgJ2NvZGUnLFxuICAgICdbYXJpYS1oaWRkZW49XCJ0cnVlXCJdJyxcblxuICAgIC8vIEZvbnQgQXdlc29tZVxuICAgICdbY2xhc3MqPVwiZmEtXCJdJyxcbiAgICAnLmZhJywgJy5mYWInLCAnLmZhZCcsICcuZmFsJywgJy5mYXInLCAnLmZhcycsICcuZmFzcycsICcuZmFzcicsICcuZmF0JyxcblxuICAgIC8vIEdlbmVyaWMgbWF0Y2hlcyBmb3IgaWNvbi9zeW1ib2wgZm9udHNcbiAgICAnLmljb2ZvbnQnLCAnW3N0eWxlKj1cImZvbnQtXCJdJyxcbiAgICAnW2NsYXNzKj1cImljb25cIl0nLCAnW2NsYXNzKj1cIkljb25cIl0nLFxuICAgICdbY2xhc3MqPVwic3ltYm9sXCJdJywgJ1tjbGFzcyo9XCJTeW1ib2xcIl0nLFxuXG4gICAgLy8gR2x5cGggSWNvbnNcbiAgICAnLmdseXBoaWNvbicsXG5cbiAgICAvLyBNYXRlcmlhbCBEZXNpZ25cbiAgICAnW2NsYXNzKj1cIm1hdGVyaWFsLXN5bWJvbFwiXScsICdbY2xhc3MqPVwibWF0ZXJpYWwtaWNvblwiXScsXG5cbiAgICAvLyBNVUlcbiAgICAnbXUnLCAnW2NsYXNzKj1cIm11LVwiXScsXG5cbiAgICAvLyBUeXBpY29uc1xuICAgICcudHlwY24nLFxuXG4gICAgLy8gVmlkZW9qcyBmb250XG4gICAgJ1tjbGFzcyo9XCJ2anMtXCJdJyxcbl07XG5cbmV4cG9ydCBmdW5jdGlvbiBjcmVhdGVUZXh0U3R5bGUoY29uZmlnOiBUaGVtZSk6IHN0cmluZyB7XG4gICAgY29uc3QgbGluZXM6IHN0cmluZ1tdID0gW107XG4gICAgbGluZXMucHVzaChgKjpub3QoJHtleGNsdWRlZFNlbGVjdG9ycy5qb2luKCcsICcpfSkge2ApO1xuXG4gICAgaWYgKGNvbmZpZy51c2VGb250ICYmIGNvbmZpZy5mb250RmFtaWx5KSB7XG4gICAgICAgIGxpbmVzLnB1c2goYCAgZm9udC1mYW1pbHk6ICR7Y29uZmlnLmZvbnRGYW1pbHl9ICFpbXBvcnRhbnQ7YCk7XG4gICAgfVxuXG4gICAgaWYgKGNvbmZpZy50ZXh0U3Ryb2tlID4gMCkge1xuICAgICAgICBsaW5lcy5wdXNoKGAgIC13ZWJraXQtdGV4dC1zdHJva2U6ICR7Y29uZmlnLnRleHRTdHJva2V9cHggIWltcG9ydGFudDtgKTtcbiAgICAgICAgbGluZXMucHVzaChgICB0ZXh0LXN0cm9rZTogJHtjb25maWcudGV4dFN0cm9rZX1weCAhaW1wb3J0YW50O2ApO1xuICAgIH1cblxuICAgIGxpbmVzLnB1c2goJ30nKTtcblxuICAgIHJldHVybiBsaW5lcy5qb2luKCdcXG4nKTtcbn1cbiIsImZ1bmN0aW9uIGlzQXJyYXlMaWtlPFQ+KGl0ZW1zOiBJdGVyYWJsZTxUPiB8IEFycmF5TGlrZTxUPik6IGl0ZW1zIGlzIEFycmF5TGlrZTxUPiB7XG4gICAgcmV0dXJuIChpdGVtcyBhcyBBcnJheUxpa2U8VD4pLmxlbmd0aCAhPSBudWxsO1xufVxuXG4vLyBOT1RFOiBJdGVyYXRpbmcgQXJyYXktbGlrZSBpdGVtcyB1c2luZyBgZm9yIC4uIG9mYCBpcyAzeCBzbG93ZXIgaW4gRmlyZWZveFxuLy8gaHR0cHM6Ly9qc2Jlbi5jaC9raWRPcFxuZXhwb3J0IGZ1bmN0aW9uIGZvckVhY2g8VD4oaXRlbXM6IEl0ZXJhYmxlPFQ+IHwgQXJyYXlMaWtlPFQ+IHwgU2V0PFQ+LCBpdGVyYXRvcjogKGl0ZW06IFQpID0+IHZvaWQpOiB2b2lkIHtcbiAgICBpZiAoaXNBcnJheUxpa2UoaXRlbXMpKSB7XG4gICAgICAgIGZvciAobGV0IGkgPSAwLCBsZW4gPSBpdGVtcy5sZW5ndGg7IGkgPCBsZW47IGkrKykge1xuICAgICAgICAgICAgaXRlcmF0b3IoaXRlbXNbaV0pO1xuICAgICAgICB9XG4gICAgfSBlbHNlIHtcbiAgICAgICAgZm9yIChjb25zdCBpdGVtIG9mIGl0ZW1zKSB7XG4gICAgICAgICAgICBpdGVyYXRvcihpdGVtKTtcbiAgICAgICAgfVxuICAgIH1cbn1cblxuLy8gTk9URTogUHVzaGluZyBpdGVtcyBsaWtlIGBhcnIucHVzaCguLi5pdGVtcylgIGlzIDN4IHNsb3dlciBpbiBGaXJlZm94XG4vLyBodHRwczovL2pzYmVuLmNoL25yOU9GXG5leHBvcnQgZnVuY3Rpb24gcHVzaDxUPihhcnJheTogVFtdLCBhZGRpdGlvbjogSXRlcmFibGU8VD4gfCBBcnJheUxpa2U8VD4pOiB2b2lkIHtcbiAgICBmb3JFYWNoKGFkZGl0aW9uLCAoYSkgPT4gYXJyYXkucHVzaChhKSk7XG59XG5cbi8vIE5PVEU6IFVzaW5nIGBBcnJheS5mcm9tKClgIGlzIDJ4IChGRikg4oCUIDV4IChDaHJvbWUpIHNsb3dlciBmb3IgQXJyYXlMaWtlIChub3QgZm9yIEl0ZXJhYmxlKVxuLy8gaHR0cHM6Ly9qc2Jlbi5jaC9GSjFtT1xuLy8gaHR0cHM6Ly9qc2Jlbi5jaC9abVZpTFxuZXhwb3J0IGZ1bmN0aW9uIHRvQXJyYXk8VD4oaXRlbXM6IEFycmF5TGlrZTxUPik6IFRbXSB7XG4gICAgY29uc3QgcmVzdWx0czogVFtdID0gW107XG4gICAgZm9yIChsZXQgaSA9IDAsIGxlbiA9IGl0ZW1zLmxlbmd0aDsgaSA8IGxlbjsgaSsrKSB7XG4gICAgICAgIHJlc3VsdHMucHVzaChpdGVtc1tpXSk7XG4gICAgfVxuICAgIHJldHVybiByZXN1bHRzO1xufVxuIiwiaW1wb3J0IHtwdXNofSBmcm9tICcuLi8uLi91dGlscy9hcnJheSc7XG5cbmludGVyZmFjZSBTaXRlRml4IHtcbiAgICB1cmw6IHN0cmluZ1tdO1xuICAgIFtwcm9wOiBzdHJpbmddOiBhbnk7XG59XG5cbmludGVyZmFjZSBTaXRlc0ZpeGVzRm9ybWF0T3B0aW9ucyB7XG4gICAgcHJvcHM6IHN0cmluZ1tdO1xuICAgIGdldFByb3BDb21tYW5kTmFtZTogKHByb3A6IHN0cmluZykgPT4gc3RyaW5nO1xuICAgIGZvcm1hdFByb3BWYWx1ZTogKHByb3A6IHN0cmluZywgdmFsdWU6IHN0cmluZyB8IHN0cmluZ1tdKSA9PiBzdHJpbmc7XG4gICAgc2hvdWxkSWdub3JlUHJvcDogKHByb3A6IHN0cmluZywgdmFsdWU6IHN0cmluZyB8IHN0cmluZ1tdKSA9PiBib29sZWFuO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gZm9ybWF0U2l0ZXNGaXhlc0NvbmZpZyhmaXhlczogU2l0ZUZpeFtdLCBvcHRpb25zOiBTaXRlc0ZpeGVzRm9ybWF0T3B0aW9ucyk6IHN0cmluZyB7XG4gICAgY29uc3QgbGluZXM6IHN0cmluZ1tdID0gW107XG5cbiAgICBmaXhlcy5mb3JFYWNoKChmaXgsIGkpID0+IHtcbiAgICAgICAgcHVzaChsaW5lcywgZml4LnVybCk7XG4gICAgICAgIG9wdGlvbnMucHJvcHMuZm9yRWFjaCgocHJvcCkgPT4ge1xuICAgICAgICAgICAgY29uc3QgY29tbWFuZCA9IG9wdGlvbnMuZ2V0UHJvcENvbW1hbmROYW1lKHByb3ApO1xuICAgICAgICAgICAgY29uc3QgdmFsdWUgPSBmaXhbcHJvcF07XG4gICAgICAgICAgICBpZiAob3B0aW9ucy5zaG91bGRJZ25vcmVQcm9wKHByb3AsIHZhbHVlKSkge1xuICAgICAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGxpbmVzLnB1c2goJycpO1xuICAgICAgICAgICAgbGluZXMucHVzaChjb21tYW5kKTtcbiAgICAgICAgICAgIGNvbnN0IGZvcm1hdHRlZFZhbHVlID0gb3B0aW9ucy5mb3JtYXRQcm9wVmFsdWUocHJvcCwgdmFsdWUpO1xuICAgICAgICAgICAgaWYgKGZvcm1hdHRlZFZhbHVlKSB7XG4gICAgICAgICAgICAgICAgbGluZXMucHVzaChmb3JtYXR0ZWRWYWx1ZSk7XG4gICAgICAgICAgICB9XG4gICAgICAgIH0pO1xuICAgICAgICBpZiAoaSA8IGZpeGVzLmxlbmd0aCAtIDEpIHtcbiAgICAgICAgICAgIGxpbmVzLnB1c2goJycpO1xuICAgICAgICAgICAgbGluZXMucHVzaCgnPScucmVwZWF0KDMyKSk7XG4gICAgICAgICAgICBsaW5lcy5wdXNoKCcnKTtcbiAgICAgICAgfVxuICAgIH0pO1xuXG4gICAgbGluZXMucHVzaCgnJyk7XG4gICAgcmV0dXJuIGxpbmVzLmpvaW4oJ1xcbicpO1xufVxuIiwiZXhwb3J0IHR5cGUgTWF0cml4NXg1ID0gW1xuICAgIFtudW1iZXIsIG51bWJlciwgbnVtYmVyLCBudW1iZXIsIG51bWJlcl0sXG4gICAgW251bWJlciwgbnVtYmVyLCBudW1iZXIsIG51bWJlciwgbnVtYmVyXSxcbiAgICBbbnVtYmVyLCBudW1iZXIsIG51bWJlciwgbnVtYmVyLCBudW1iZXJdLFxuICAgIFtudW1iZXIsIG51bWJlciwgbnVtYmVyLCBudW1iZXIsIG51bWJlcl0sXG4gICAgW251bWJlciwgbnVtYmVyLCBudW1iZXIsIG51bWJlciwgbnVtYmVyXVxuXTtcblxuZXhwb3J0IHR5cGUgTWF0cml4NXgxID0gW1xuICAgIFtudW1iZXJdLFxuICAgIFtudW1iZXJdLFxuICAgIFtudW1iZXJdLFxuICAgIFtudW1iZXJdLFxuICAgIFtudW1iZXJdXG5dO1xuXG5leHBvcnQgdHlwZSBNYXRyaXggPSBNYXRyaXg1eDUgfCBNYXRyaXg1eDE7XG5cbmV4cG9ydCBmdW5jdGlvbiBzY2FsZSh4OiBudW1iZXIsIGluTG93OiBudW1iZXIsIGluSGlnaDogbnVtYmVyLCBvdXRMb3c6IG51bWJlciwgb3V0SGlnaDogbnVtYmVyKTogbnVtYmVyIHtcbiAgICByZXR1cm4gKHggLSBpbkxvdykgKiAob3V0SGlnaCAtIG91dExvdykgLyAoaW5IaWdoIC0gaW5Mb3cpICsgb3V0TG93O1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY2xhbXAoeDogbnVtYmVyLCBtaW46IG51bWJlciwgbWF4OiBudW1iZXIpOiBudW1iZXIge1xuICAgIHJldHVybiBNYXRoLm1pbihtYXgsIE1hdGgubWF4KG1pbiwgeCkpO1xufVxuXG4vLyBOb3RlOiB0aGUgY2FsbGVyIGlzIHJlc3BvbnNpYmxlIGZvciBlbnN1cmluZyB0aGF0IG1hdHJpeCBkaW1lbnNpb25zIG1ha2Ugc2Vuc2VcbmV4cG9ydCBmdW5jdGlvbiBtdWx0aXBseU1hdHJpY2VzPE0gZXh0ZW5kcyBNYXRyaXg+KG0xOiBNYXRyaXg1eDUsIG0yOiBNYXRyaXg1eDUgfCBNYXRyaXg1eDEpOiBNIHtcbiAgICBjb25zdCByZXN1bHQ6IG51bWJlcltdW10gPSBbXTtcbiAgICBmb3IgKGxldCBpID0gMCwgbGVuID0gbTEubGVuZ3RoOyBpIDwgbGVuOyBpKyspIHtcbiAgICAgICAgcmVzdWx0W2ldID0gW107XG4gICAgICAgIGZvciAobGV0IGogPSAwLCBsZW4yID0gbTJbMF0ubGVuZ3RoOyBqIDwgbGVuMjsgaisrKSB7XG4gICAgICAgICAgICBsZXQgc3VtID0gMDtcbiAgICAgICAgICAgIGZvciAobGV0IGsgPSAwLCBsZW4zID0gbTFbMF0ubGVuZ3RoOyBrIDwgbGVuMzsgaysrKSB7XG4gICAgICAgICAgICAgICAgc3VtICs9IG0xW2ldW2tdICogbTJba11bal07XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICByZXN1bHRbaV1bal0gPSBzdW07XG4gICAgICAgIH1cbiAgICB9XG4gICAgcmV0dXJuIHJlc3VsdCBhcyBNO1xufVxuIiwiaW1wb3J0IHR5cGUge1RoZW1lfSBmcm9tICcuLi8uLi9kZWZpbml0aW9ucyc7XG5pbXBvcnQge2NsYW1wLCBtdWx0aXBseU1hdHJpY2VzfSBmcm9tICcuLi8uLi91dGlscy9tYXRoJztcbmltcG9ydCB0eXBlIHtNYXRyaXg1eDEsIE1hdHJpeDV4NX0gZnJvbSAnLi4vLi4vdXRpbHMvbWF0aCc7XG5cblxuZXhwb3J0IGZ1bmN0aW9uIGNyZWF0ZUZpbHRlck1hdHJpeChjb25maWc6IFRoZW1lKTogTWF0cml4NXg1IHtcbiAgICBsZXQgbTogTWF0cml4NXg1ID0gTWF0cml4LmlkZW50aXR5KCk7XG4gICAgaWYgKGNvbmZpZy5zZXBpYSAhPT0gMCkge1xuICAgICAgICBtID0gbXVsdGlwbHlNYXRyaWNlcyhtLCBNYXRyaXguc2VwaWEoY29uZmlnLnNlcGlhIC8gMTAwKSk7XG4gICAgfVxuICAgIGlmIChjb25maWcuZ3JheXNjYWxlICE9PSAwKSB7XG4gICAgICAgIG0gPSBtdWx0aXBseU1hdHJpY2VzKG0sIE1hdHJpeC5ncmF5c2NhbGUoY29uZmlnLmdyYXlzY2FsZSAvIDEwMCkpO1xuICAgIH1cbiAgICBpZiAoY29uZmlnLmNvbnRyYXN0ICE9PSAxMDApIHtcbiAgICAgICAgbSA9IG11bHRpcGx5TWF0cmljZXMobSwgTWF0cml4LmNvbnRyYXN0KGNvbmZpZy5jb250cmFzdCAvIDEwMCkpO1xuICAgIH1cbiAgICBpZiAoY29uZmlnLmJyaWdodG5lc3MgIT09IDEwMCkge1xuICAgICAgICBtID0gbXVsdGlwbHlNYXRyaWNlcyhtLCBNYXRyaXguYnJpZ2h0bmVzcyhjb25maWcuYnJpZ2h0bmVzcyAvIDEwMCkpO1xuICAgIH1cbiAgICBpZiAoY29uZmlnLm1vZGUgPT09IDEpIHtcbiAgICAgICAgbSA9IG11bHRpcGx5TWF0cmljZXMobSwgTWF0cml4LmludmVydE5IdWUoKSk7XG4gICAgfVxuICAgIHJldHVybiBtO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gYXBwbHlDb2xvck1hdHJpeChbciwgZywgYl06IFtudW1iZXIsIG51bWJlciwgbnVtYmVyXSwgbWF0cml4OiBNYXRyaXg1eDUpOiBbbnVtYmVyLCBudW1iZXIsIG51bWJlcl0ge1xuICAgIGNvbnN0IHJnYjogTWF0cml4NXgxID0gW1tyIC8gMjU1XSwgW2cgLyAyNTVdLCBbYiAvIDI1NV0sIFsxXSwgWzFdXTtcbiAgICBjb25zdCByZXN1bHQgPSBtdWx0aXBseU1hdHJpY2VzPE1hdHJpeDV4MT4obWF0cml4LCByZ2IpO1xuICAgIHJldHVybiBbMCwgMSwgMl0ubWFwKChpKSA9PiBjbGFtcChNYXRoLnJvdW5kKHJlc3VsdFtpXVswXSAqIDI1NSksIDAsIDI1NSkpIGFzIFtudW1iZXIsIG51bWJlciwgbnVtYmVyXTtcbn1cblxuZXhwb3J0IGNvbnN0IE1hdHJpeCA9IHtcblxuICAgIGlkZW50aXR5KCk6IE1hdHJpeDV4NSB7XG4gICAgICAgIHJldHVybiBbXG4gICAgICAgICAgICBbMSwgMCwgMCwgMCwgMF0sXG4gICAgICAgICAgICBbMCwgMSwgMCwgMCwgMF0sXG4gICAgICAgICAgICBbMCwgMCwgMSwgMCwgMF0sXG4gICAgICAgICAgICBbMCwgMCwgMCwgMSwgMF0sXG4gICAgICAgICAgICBbMCwgMCwgMCwgMCwgMV0sXG4gICAgICAgIF07XG4gICAgfSxcblxuICAgIGludmVydE5IdWUoKTogTWF0cml4NXg1IHtcbiAgICAgICAgcmV0dXJuIFtcbiAgICAgICAgICAgIFswLjMzMywgLTAuNjY3LCAtMC42NjcsIDAsIDFdLFxuICAgICAgICAgICAgWy0wLjY2NywgMC4zMzMsIC0wLjY2NywgMCwgMV0sXG4gICAgICAgICAgICBbLTAuNjY3LCAtMC42NjcsIDAuMzMzLCAwLCAxXSxcbiAgICAgICAgICAgIFswLCAwLCAwLCAxLCAwXSxcbiAgICAgICAgICAgIFswLCAwLCAwLCAwLCAxXSxcbiAgICAgICAgXTtcbiAgICB9LFxuXG4gICAgYnJpZ2h0bmVzcyh2OiBudW1iZXIpOiBNYXRyaXg1eDUge1xuICAgICAgICByZXR1cm4gW1xuICAgICAgICAgICAgW3YsIDAsIDAsIDAsIDBdLFxuICAgICAgICAgICAgWzAsIHYsIDAsIDAsIDBdLFxuICAgICAgICAgICAgWzAsIDAsIHYsIDAsIDBdLFxuICAgICAgICAgICAgWzAsIDAsIDAsIDEsIDBdLFxuICAgICAgICAgICAgWzAsIDAsIDAsIDAsIDFdLFxuICAgICAgICBdO1xuICAgIH0sXG5cbiAgICBjb250cmFzdCh2OiBudW1iZXIpOiBNYXRyaXg1eDUge1xuICAgICAgICBjb25zdCB0ID0gKDEgLSB2KSAvIDI7XG4gICAgICAgIHJldHVybiBbXG4gICAgICAgICAgICBbdiwgMCwgMCwgMCwgdF0sXG4gICAgICAgICAgICBbMCwgdiwgMCwgMCwgdF0sXG4gICAgICAgICAgICBbMCwgMCwgdiwgMCwgdF0sXG4gICAgICAgICAgICBbMCwgMCwgMCwgMSwgMF0sXG4gICAgICAgICAgICBbMCwgMCwgMCwgMCwgMV0sXG4gICAgICAgIF07XG4gICAgfSxcblxuICAgIHNlcGlhKHY6IG51bWJlcik6IE1hdHJpeDV4NSB7XG4gICAgICAgIHJldHVybiBbXG4gICAgICAgICAgICBbKDAuMzkzICsgMC42MDcgKiAoMSAtIHYpKSwgKDAuNzY5IC0gMC43NjkgKiAoMSAtIHYpKSwgKDAuMTg5IC0gMC4xODkgKiAoMSAtIHYpKSwgMCwgMF0sXG4gICAgICAgICAgICBbKDAuMzQ5IC0gMC4zNDkgKiAoMSAtIHYpKSwgKDAuNjg2ICsgMC4zMTQgKiAoMSAtIHYpKSwgKDAuMTY4IC0gMC4xNjggKiAoMSAtIHYpKSwgMCwgMF0sXG4gICAgICAgICAgICBbKDAuMjcyIC0gMC4yNzIgKiAoMSAtIHYpKSwgKDAuNTM0IC0gMC41MzQgKiAoMSAtIHYpKSwgKDAuMTMxICsgMC44NjkgKiAoMSAtIHYpKSwgMCwgMF0sXG4gICAgICAgICAgICBbMCwgMCwgMCwgMSwgMF0sXG4gICAgICAgICAgICBbMCwgMCwgMCwgMCwgMV0sXG4gICAgICAgIF07XG4gICAgfSxcblxuICAgIGdyYXlzY2FsZSh2OiBudW1iZXIpOiBNYXRyaXg1eDUge1xuICAgICAgICByZXR1cm4gW1xuICAgICAgICAgICAgWygwLjIxMjYgKyAwLjc4NzQgKiAoMSAtIHYpKSwgKDAuNzE1MiAtIDAuNzE1MiAqICgxIC0gdikpLCAoMC4wNzIyIC0gMC4wNzIyICogKDEgLSB2KSksIDAsIDBdLFxuICAgICAgICAgICAgWygwLjIxMjYgLSAwLjIxMjYgKiAoMSAtIHYpKSwgKDAuNzE1MiArIDAuMjg0OCAqICgxIC0gdikpLCAoMC4wNzIyIC0gMC4wNzIyICogKDEgLSB2KSksIDAsIDBdLFxuICAgICAgICAgICAgWygwLjIxMjYgLSAwLjIxMjYgKiAoMSAtIHYpKSwgKDAuNzE1MiAtIDAuNzE1MiAqICgxIC0gdikpLCAoMC4wNzIyICsgMC45Mjc4ICogKDEgLSB2KSksIDAsIDBdLFxuICAgICAgICAgICAgWzAsIDAsIDAsIDEsIDBdLFxuICAgICAgICAgICAgWzAsIDAsIDAsIDAsIDFdLFxuICAgICAgICBdO1xuICAgIH0sXG59O1xuIiwiaW1wb3J0IHtwYXJzZUFycmF5fSBmcm9tICcuLi8uLi91dGlscy90ZXh0JztcbmltcG9ydCB7aW5kZXhVUkxUZW1wbGF0ZUxpc3QsIGdldFVSTE1hdGNoZXNGcm9tSW5kZXhlZExpc3R9IGZyb20gJy4uLy4uL3V0aWxzL3VybCc7XG5pbXBvcnQgdHlwZSB7VVJMVHJpZX0gZnJvbSAnLi4vLi4vdXRpbHMvdXJsJztcblxuaW50ZXJmYWNlIFNpdGVQcm9wcyB7XG4gICAgdXJsOiBzdHJpbmdbXTtcbn1cblxuZXhwb3J0IGludGVyZmFjZSBTaXRlTGlzdEluZGV4IHtcbiAgICB1cmxzOiByZWFkb25seSBzdHJpbmdbXTtcbiAgICBkb21haW5zOiBSZWFkb25seTx7W2RvbWFpbjogc3RyaW5nXTogbnVtYmVyW119PjtcbiAgICBkb21haW5MYWJlbHM6IFJlYWRvbmx5PHtbZG9tYWluTGFiZWw6IHN0cmluZ106IHJlYWRvbmx5IG51bWJlcltdfT47XG4gICAgbm9uc3RhbmRhcmQ6IHJlYWRvbmx5IG51bWJlcltdO1xufVxuXG5leHBvcnQgaW50ZXJmYWNlIFNpdGVzRml4ZXNQYXJzZXJPcHRpb25zPFQ+IHtcbiAgICBjb21tYW5kczogcmVhZG9ubHkgc3RyaW5nW107XG4gICAgZ2V0Q29tbWFuZFByb3BOYW1lOiAoY29tbWFuZDogc3RyaW5nKSA9PiBrZXlvZiBUO1xuICAgIHBhcnNlQ29tbWFuZFZhbHVlOiAoY29tbWFuZDogc3RyaW5nLCB2YWx1ZTogc3RyaW5nKSA9PiBhbnk7XG59XG5cbmV4cG9ydCB0eXBlIFNpdGVGaXhlc0luZGV4ID0gVVJMVHJpZTxbbnVtYmVyLCBudW1iZXJdPjtcblxuZXhwb3J0IGZ1bmN0aW9uIHBhcnNlU2l0ZXNGaXhlc0NvbmZpZzxUIGV4dGVuZHMgU2l0ZVByb3BzPih0ZXh0OiBzdHJpbmcsIG9wdGlvbnM6IFNpdGVzRml4ZXNQYXJzZXJPcHRpb25zPFQ+KTogVFtdIHtcbiAgICBjb25zdCBzaXRlczogVFtdID0gW107XG5cbiAgICBjb25zdCBibG9ja3MgPSB0ZXh0LnJlcGxhY2UoL1xcci9nLCAnJykuc3BsaXQoL15cXHMqPXsyLH1cXHMqJC9nbSk7XG4gICAgYmxvY2tzLmZvckVhY2goKGJsb2NrKSA9PiB7XG4gICAgICAgIGNvbnN0IGxpbmVzID0gYmxvY2suc3BsaXQoJ1xcbicpO1xuICAgICAgICBjb25zdCBjb21tYW5kSW5kaWNlczogbnVtYmVyW10gPSBbXTtcbiAgICAgICAgbGluZXMuZm9yRWFjaCgobG4sIGkpID0+IHtcbiAgICAgICAgICAgIGlmIChsbi5tYXRjaCgvXltBLVpdKyhcXHNbQS1aXSspezAsMn0kLykpIHtcbiAgICAgICAgICAgICAgICBjb21tYW5kSW5kaWNlcy5wdXNoKGkpO1xuICAgICAgICAgICAgfVxuICAgICAgICB9KTtcblxuICAgICAgICBpZiAoY29tbWFuZEluZGljZXMubGVuZ3RoID09PSAwKSB7XG4gICAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cblxuICAgICAgICBjb25zdCBzaXRlRml4ID0ge1xuICAgICAgICAgICAgdXJsOiBwYXJzZUFycmF5KGxpbmVzLnNsaWNlKDAsIGNvbW1hbmRJbmRpY2VzWzBdKS5qb2luKCdcXG4nKSkgYXMgcmVhZG9ubHkgc3RyaW5nW10sXG4gICAgICAgIH0gYXMgVDtcblxuICAgICAgICBjb21tYW5kSW5kaWNlcy5mb3JFYWNoKChjb21tYW5kSW5kZXgsIGkpID0+IHtcbiAgICAgICAgICAgIGNvbnN0IGNvbW1hbmQgPSBsaW5lc1tjb21tYW5kSW5kZXhdLnRyaW0oKTtcbiAgICAgICAgICAgIGNvbnN0IHZhbHVlVGV4dCA9IGxpbmVzLnNsaWNlKGNvbW1hbmRJbmRleCArIDEsIGkgPT09IGNvbW1hbmRJbmRpY2VzLmxlbmd0aCAtIDEgPyBsaW5lcy5sZW5ndGggOiBjb21tYW5kSW5kaWNlc1tpICsgMV0pLmpvaW4oJ1xcbicpO1xuICAgICAgICAgICAgY29uc3QgcHJvcCA9IG9wdGlvbnMuZ2V0Q29tbWFuZFByb3BOYW1lKGNvbW1hbmQpO1xuICAgICAgICAgICAgaWYgKCFwcm9wKSB7XG4gICAgICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgY29uc3QgdmFsdWUgPSBvcHRpb25zLnBhcnNlQ29tbWFuZFZhbHVlKGNvbW1hbmQsIHZhbHVlVGV4dCk7XG4gICAgICAgICAgICBzaXRlRml4W3Byb3BdID0gdmFsdWU7XG4gICAgICAgIH0pO1xuXG4gICAgICAgIHNpdGVzLnB1c2goc2l0ZUZpeCk7XG4gICAgfSk7XG5cbiAgICByZXR1cm4gc2l0ZXM7XG59XG5cbi8vIFVSTCBwYXR0ZXJucyBhcmUgZ3VhcmFudGVlZCB0byBub3QgaGF2ZSBwcm90b2NvbCBhbmQgbGVhZGluZyAnLydcbmV4cG9ydCBmdW5jdGlvbiBnZXREb21haW4odXJsOiBzdHJpbmcpOiBzdHJpbmcge1xuICAgIHRyeSB7XG4gICAgICAgIHJldHVybiAobmV3IFVSTCh1cmwpKS5ob3N0bmFtZS50b0xvd2VyQ2FzZSgpO1xuICAgIH0gY2F0Y2ggKGVycm9yKSB7XG4gICAgICAgIHJldHVybiB1cmwuc3BsaXQoJy8nKVswXS50b0xvd2VyQ2FzZSgpO1xuICAgIH1cbn1cblxuZnVuY3Rpb24gcHJvY2Vzc1NpdGVGaXhlc0NvbmZpZ0Jsb2NrKHRleHQ6IHN0cmluZywgb2Zmc2V0czogQXJyYXk8W251bWJlciwgbnVtYmVyXT4sIHJlY29yZFN0YXJ0OiBudW1iZXIsIHJlY29yZEVuZDogbnVtYmVyLCB1cmxzOiBBcnJheTxyZWFkb25seSBzdHJpbmdbXT4pIHtcbiAgICAvLyBUT0RPOiBtb3JlIGZvcm1hbCBkZWZpbml0aW9uIG9mIFVSTHMgYW5kIGRlbGltaXRlcnNcbiAgICBjb25zdCBibG9jayA9IHRleHQuc3Vic3RyaW5nKHJlY29yZFN0YXJ0LCByZWNvcmRFbmQpO1xuICAgIGNvbnN0IGxpbmVzID0gYmxvY2suc3BsaXQoJ1xcbicpO1xuICAgIGNvbnN0IGNvbW1hbmRJbmRpY2VzOiBudW1iZXJbXSA9IFtdO1xuICAgIGxpbmVzLmZvckVhY2goKGxuLCBpKSA9PiB7XG4gICAgICAgIGlmIChsbi5tYXRjaCgvXltBLVpdKyhcXHNbQS1aXSspezAsMn0kLykpIHtcbiAgICAgICAgICAgIGNvbW1hbmRJbmRpY2VzLnB1c2goaSk7XG4gICAgICAgIH1cbiAgICB9KTtcblxuICAgIGlmIChjb21tYW5kSW5kaWNlcy5sZW5ndGggPT09IDApIHtcbiAgICAgICAgcmV0dXJuO1xuICAgIH1cblxuICAgIG9mZnNldHMucHVzaChbcmVjb3JkU3RhcnQsIHJlY29yZEVuZCAtIHJlY29yZFN0YXJ0XSk7XG5cbiAgICBjb25zdCB1cmxzXyA9IHBhcnNlQXJyYXkobGluZXMuc2xpY2UoMCwgY29tbWFuZEluZGljZXNbMF0pLmpvaW4oJ1xcbicpKTtcbiAgICB1cmxzLnB1c2godXJsc18pO1xufVxuXG5mdW5jdGlvbiBleHRyYWN0VVJMc0Zyb21TaXRlRml4ZXNDb25maWcodGV4dDogc3RyaW5nKToge3VybHM6IHN0cmluZ1tdW107IG9mZnNldHM6IEFycmF5PFtudW1iZXIsIG51bWJlcl0+fSB7XG4gICAgY29uc3QgdXJsczogc3RyaW5nW11bXSA9IFtdO1xuICAgIC8vIEFycmF5IG9mIHR1cGxlcywgd2hlcmUgZmlyc3QgbnVtYmVyIGlzIGFuIG9mZnNldCBvZiByZWNvcmQgc3RhcnQgYW5kIHNlY29uZCBudW1iZXIgaXMgcmVjb3JkIGxlbmd0aC5cbiAgICBjb25zdCBvZmZzZXRzOiBBcnJheTxbbnVtYmVyLCBudW1iZXJdPiA9IFtdO1xuXG4gICAgbGV0IHJlY29yZFN0YXJ0ID0gMDtcbiAgICAvLyBEZWxpbWl0ZXIgYmV0d2VlbiB0d28gYmxvY2tzXG4gICAgY29uc3QgZGVsaW1pdGVyUmVnZXggPSAvXlxccyo9ezIsfVxccyokL2dtO1xuICAgIGxldCBkZWxpbWl0ZXI6IFJlZ0V4cE1hdGNoQXJyYXkgfCBudWxsO1xuICAgIHdoaWxlICgoZGVsaW1pdGVyID0gZGVsaW1pdGVyUmVnZXguZXhlYyh0ZXh0KSkpIHtcbiAgICAgICAgY29uc3QgbmV4dERlbGltaXRlclN0YXJ0ID0gZGVsaW1pdGVyLmluZGV4ITtcbiAgICAgICAgY29uc3QgbmV4dERlbGltaXRlckVuZCA9IGRlbGltaXRlci5pbmRleCEgKyBkZWxpbWl0ZXJbMF0ubGVuZ3RoO1xuICAgICAgICBwcm9jZXNzU2l0ZUZpeGVzQ29uZmlnQmxvY2sodGV4dCwgb2Zmc2V0cywgcmVjb3JkU3RhcnQsIG5leHREZWxpbWl0ZXJTdGFydCwgdXJscyk7XG4gICAgICAgIHJlY29yZFN0YXJ0ID0gbmV4dERlbGltaXRlckVuZDtcbiAgICB9XG4gICAgcHJvY2Vzc1NpdGVGaXhlc0NvbmZpZ0Jsb2NrKHRleHQsIG9mZnNldHMsIHJlY29yZFN0YXJ0LCB0ZXh0Lmxlbmd0aCwgdXJscyk7XG5cbiAgICByZXR1cm4ge3VybHMsIG9mZnNldHN9O1xufVxuXG5leHBvcnQgZnVuY3Rpb24gaW5kZXhTaXRlc0ZpeGVzQ29uZmlnKHRleHQ6IHN0cmluZyk6IFNpdGVGaXhlc0luZGV4IHtcbiAgICBjb25zdCB7dXJscywgb2Zmc2V0czogb2Zmc2V0c0dyb3VwZWR9ID0gZXh0cmFjdFVSTHNGcm9tU2l0ZUZpeGVzQ29uZmlnKHRleHQpO1xuICAgIGNvbnN0IG9mZnNldE1hcCA9IG5ldyBNYXA8c3RyaW5nLCBbbnVtYmVyLCBudW1iZXJdPigpO1xuICAgIGNvbnN0IHRlbXBsYXRlczogc3RyaW5nW10gPSBbXTtcbiAgICBjb25zdCBvZmZzZXRzOiBBcnJheTxbbnVtYmVyLCBudW1iZXJdPiA9IFtdXG4gICAgdXJscy5mb3JFYWNoKChibG9jaywgaSkgPT4ge1xuICAgICAgICBibG9jay5mb3JFYWNoKCh1KSA9PiB7XG4gICAgICAgICAgICB0ZW1wbGF0ZXMucHVzaCh1KTtcbiAgICAgICAgICAgIG9mZnNldHMucHVzaChvZmZzZXRzR3JvdXBlZFtpXSk7XG4gICAgICAgICAgICBvZmZzZXRNYXAuc2V0KHUsIG9mZnNldHNHcm91cGVkW2ldKTtcbiAgICAgICAgfSk7XG4gICAgfSk7XG4gICAgY29uc3QgaW5kZXhlZExpc3QgPSBpbmRleFVSTFRlbXBsYXRlTGlzdCh0ZW1wbGF0ZXMsIChfLCBpKSA9PiB7XG4gICAgICAgIHJldHVybiBvZmZzZXRzW2ldO1xuICAgIH0pO1xuICAgIHJldHVybiBpbmRleGVkTGlzdDtcbn1cblxuY29uc3Qgc2l0ZUZpeGVzQ2FjaGUgPSBuZXcgV2Vha01hcDxbbnVtYmVyLCBudW1iZXJdLCBhbnk+KCk7XG5cbmV4cG9ydCBmdW5jdGlvbiBnZXRTaXRlc0ZpeGVzRm9yPFQgZXh0ZW5kcyBTaXRlUHJvcHM+KHVybDogc3RyaW5nLCB0ZXh0OiBzdHJpbmcsIGluZGV4OiBTaXRlRml4ZXNJbmRleCwgcGFyc2U6ICh0ZXh0OiBzdHJpbmcpID0+IFRbXSk6IEFycmF5PFJlYWRvbmx5PFQ+PiB7XG4gICAgY29uc3QgbWF0Y2hlcyA9IGdldFVSTE1hdGNoZXNGcm9tSW5kZXhlZExpc3QodXJsLCBpbmRleCk7XG5cbiAgICBjb25zdCBmaXhlcyA9IG1hdGNoZXMubWFwKChvZmZzZXQpID0+IHtcbiAgICAgICAgY29uc3QgY2FjaGUgPSBzaXRlRml4ZXNDYWNoZS5nZXQob2Zmc2V0KTtcbiAgICAgICAgaWYgKGNhY2hlKSB7XG4gICAgICAgICAgICByZXR1cm4gY2FjaGU7XG4gICAgICAgIH1cbiAgICAgICAgY29uc3QgW3N0YXJ0LCBsZW5ndGhdID0gb2Zmc2V0O1xuICAgICAgICBjb25zdCBibG9jayA9IHRleHQuc2xpY2Uoc3RhcnQsIHN0YXJ0ICsgbGVuZ3RoKTtcbiAgICAgICAgY29uc3QgZml4ID0gcGFyc2UoYmxvY2spWzBdO1xuICAgICAgICBzaXRlRml4ZXNDYWNoZS5zZXQob2Zmc2V0LCBjYWNoZSk7XG4gICAgICAgIHJldHVybiBmaXg7XG4gICAgfSk7XG5cbiAgICByZXR1cm4gZml4ZXM7XG59XG4iLCJpbXBvcnQgdHlwZSB7VGhlbWUsIEludmVyc2lvbkZpeH0gZnJvbSAnLi4vZGVmaW5pdGlvbnMnO1xuaW1wb3J0IHtjb21wYXJlQ2hyb21lVmVyc2lvbnMsIGNocm9taXVtVmVyc2lvbiwgaXNGaXJlZm94LCBmaXJlZm94VmVyc2lvbn0gZnJvbSAnLi4vdXRpbHMvcGxhdGZvcm0nO1xuaW1wb3J0IHtwYXJzZUFycmF5LCBmb3JtYXRBcnJheX0gZnJvbSAnLi4vdXRpbHMvdGV4dCc7XG5pbXBvcnQge2NvbXBhcmVVUkxQYXR0ZXJucywgaXNVUkxJbkxpc3R9IGZyb20gJy4uL3V0aWxzL3VybCc7XG5cbmltcG9ydCB7Y3JlYXRlVGV4dFN0eWxlfSBmcm9tICcuL3RleHQtc3R5bGUnO1xuaW1wb3J0IHtmb3JtYXRTaXRlc0ZpeGVzQ29uZmlnfSBmcm9tICcuL3V0aWxzL2Zvcm1hdCc7XG5pbXBvcnQge2FwcGx5Q29sb3JNYXRyaXgsIGNyZWF0ZUZpbHRlck1hdHJpeH0gZnJvbSAnLi91dGlscy9tYXRyaXgnO1xuaW1wb3J0IHtwYXJzZVNpdGVzRml4ZXNDb25maWcsIGdldFNpdGVzRml4ZXNGb3J9IGZyb20gJy4vdXRpbHMvcGFyc2UnO1xuaW1wb3J0IHR5cGUge1NpdGVGaXhlc0luZGV4fSBmcm9tICcuL3V0aWxzL3BhcnNlJztcblxuZGVjbGFyZSBjb25zdCBfX0NIUk9NSVVNX01WMl9fOiBib29sZWFuO1xuZGVjbGFyZSBjb25zdCBfX0NIUk9NSVVNX01WM19fOiBib29sZWFuO1xuXG5leHBvcnQgZW51bSBGaWx0ZXJNb2RlIHtcbiAgICBsaWdodCA9IDAsXG4gICAgZGFyayA9IDFcbn1cblxuLyoqXG4gKiBUaGlzIGNoZWNrcyBpZiB0aGUgY3VycmVudCBjaHJvbWl1bSB2ZXJzaW9uIGhhcyB0aGUgcGF0Y2ggaW4gaXQuXG4gKiBBcyBvZiBDaHJvbWl1bSB2ODEuMC40MDM1LjAgdGhpcyBoYXMgYmVlbiB0aGUgc2l0dWF0aW9uXG4gKlxuICogQnVnIHJlcG9ydDogaHR0cHM6Ly9idWdzLmNocm9taXVtLm9yZy9wL2Nocm9taXVtL2lzc3Vlcy9kZXRhaWw/aWQ9NTAxNTgyXG4gKiBQYXRjaDogaHR0cHM6Ly9jaHJvbWl1bS1yZXZpZXcuZ29vZ2xlc291cmNlLmNvbS9jL2Nocm9taXVtL3NyYy8rLzE5NzkyNThcbiAqL1xuZXhwb3J0IGZ1bmN0aW9uIGhhc1BhdGNoRm9yQ2hyb21pdW1Jc3N1ZTUwMTU4MigpOiBib29sZWFuIHtcbiAgICByZXR1cm4gX19DSFJPTUlVTV9NVjNfXyB8fCBCb29sZWFuKFxuICAgICAgICBfX0NIUk9NSVVNX01WMl9fICYmXG4gICAgICAgIGNvbXBhcmVDaHJvbWVWZXJzaW9ucyhjaHJvbWl1bVZlcnNpb24sICc4MS4wLjQwMzUuMCcpID49IDBcbiAgICApO1xufVxuXG4vKipcbiAqIFNpbmNlIEZpcmVmb3ggdjEwMi4wLCB0aGV5IGhhdmUgY2hhbmdlZCB0byB0aGUgbmV3IHJvb3QgYmVoYXZpb3IuXG4gKiBUaGlzIHdhcyBhbHJlYWR5IHRoZSBjYXNlIGZvciBDaHJvbWl1bSB2ODEuMC40MDM1LjAgYW5kIEZpcmVmb3ggbm93XG4gKiBzd2l0Y2hlZCBvdmVyIGFzIHdlbGwuXG4gKi9cbmV4cG9ydCBmdW5jdGlvbiBoYXNGaXJlZm94TmV3Um9vdEJlaGF2aW9yKCk6IGJvb2xlYW4ge1xuICAgIHJldHVybiBCb29sZWFuKFxuICAgICAgICBpc0ZpcmVmb3ggJiZcbiAgICAgICAgY29tcGFyZUNocm9tZVZlcnNpb25zKGZpcmVmb3hWZXJzaW9uLCAnMTAyLjAnKSA+PSAwXG4gICAgKTtcbn1cblxuZXhwb3J0IGRlZmF1bHQgZnVuY3Rpb24gY3JlYXRlQ1NTRmlsdGVyU3R5bGVTaGVldChjb25maWc6IFRoZW1lLCB1cmw6IHN0cmluZywgaXNUb3BGcmFtZTogYm9vbGVhbiwgZml4ZXM6IHN0cmluZywgaW5kZXg6IFNpdGVGaXhlc0luZGV4KTogc3RyaW5nIHtcbiAgICBjb25zdCBmaWx0ZXJWYWx1ZSA9IGdldENTU0ZpbHRlclZhbHVlKGNvbmZpZykhO1xuICAgIGNvbnN0IHJldmVyc2VGaWx0ZXJWYWx1ZSA9ICdpbnZlcnQoMTAwJSkgaHVlLXJvdGF0ZSgxODBkZWcpJztcbiAgICByZXR1cm4gY3NzRmlsdGVyU3R5bGVTaGVldFRlbXBsYXRlKCdodG1sJywgZmlsdGVyVmFsdWUsIHJldmVyc2VGaWx0ZXJWYWx1ZSwgY29uZmlnLCB1cmwsIGlzVG9wRnJhbWUsIGZpeGVzLCBpbmRleCk7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBjc3NGaWx0ZXJTdHlsZVNoZWV0VGVtcGxhdGUoZmlsdGVyUm9vdDogc3RyaW5nLCBmaWx0ZXJWYWx1ZTogc3RyaW5nLCByZXZlcnNlRmlsdGVyVmFsdWU6IHN0cmluZywgY29uZmlnOiBUaGVtZSwgdXJsOiBzdHJpbmcsIGlzVG9wRnJhbWU6IGJvb2xlYW4sIGZpeGVzOiBzdHJpbmcsIGluZGV4OiBTaXRlRml4ZXNJbmRleCk6IHN0cmluZyB7XG4gICAgY29uc3QgZml4ID0gZ2V0SW52ZXJzaW9uRml4ZXNGb3IodXJsLCBmaXhlcywgaW5kZXgpO1xuXG4gICAgY29uc3QgbGluZXM6IHN0cmluZ1tdID0gW107XG5cbiAgICBsaW5lcy5wdXNoKCdAbWVkaWEgc2NyZWVuIHsnKTtcblxuICAgIC8vIEFkZCBsZWFkaW5nIHJ1bGVcbiAgICBpZiAoZmlsdGVyVmFsdWUgJiYgaXNUb3BGcmFtZSkge1xuICAgICAgICBsaW5lcy5wdXNoKCcnKTtcbiAgICAgICAgbGluZXMucHVzaCgnLyogTGVhZGluZyBydWxlICovJyk7XG4gICAgICAgIGxpbmVzLnB1c2goY3JlYXRlTGVhZGluZ1J1bGUoZmlsdGVyUm9vdCwgZmlsdGVyVmFsdWUpKTtcbiAgICB9XG5cbiAgICBpZiAoY29uZmlnLm1vZGUgPT09IEZpbHRlck1vZGUuZGFyaykge1xuICAgICAgICAvLyBBZGQgcmV2ZXJzZSBydWxlXG4gICAgICAgIGxpbmVzLnB1c2goJycpO1xuICAgICAgICBsaW5lcy5wdXNoKCcvKiBSZXZlcnNlIHJ1bGUgKi8nKTtcbiAgICAgICAgbGluZXMucHVzaChjcmVhdGVSZXZlcnNlUnVsZShyZXZlcnNlRmlsdGVyVmFsdWUsIGZpeCkpO1xuICAgIH1cblxuICAgIGlmIChjb25maWcudXNlRm9udCB8fCBjb25maWcudGV4dFN0cm9rZSA+IDApIHtcbiAgICAgICAgLy8gQWRkIHRleHQgcnVsZVxuICAgICAgICBsaW5lcy5wdXNoKCcnKTtcbiAgICAgICAgbGluZXMucHVzaCgnLyogRm9udCAqLycpO1xuICAgICAgICBsaW5lcy5wdXNoKGNyZWF0ZVRleHRTdHlsZShjb25maWcpKTtcbiAgICB9XG5cbiAgICAvLyBGaXggYmFkIGZvbnQgaGludGluZyBhZnRlciBpbnZlcnNpb25cbiAgICBsaW5lcy5wdXNoKCcnKTtcbiAgICBsaW5lcy5wdXNoKCcvKiBUZXh0IGNvbnRyYXN0ICovJyk7XG4gICAgbGluZXMucHVzaCgnaHRtbCB7Jyk7XG4gICAgbGluZXMucHVzaCgnICB0ZXh0LXNoYWRvdzogMCAwIDAgIWltcG9ydGFudDsnKTtcbiAgICBsaW5lcy5wdXNoKCd9Jyk7XG5cbiAgICAvLyBGdWxsIHNjcmVlbiBmaXhcbiAgICBsaW5lcy5wdXNoKCcnKTtcbiAgICBsaW5lcy5wdXNoKCcvKiBGdWxsIHNjcmVlbiAqLycpO1xuICAgIFsnOi13ZWJraXQtZnVsbC1zY3JlZW4nLCAnOi1tb3otZnVsbC1zY3JlZW4nLCAnOmZ1bGxzY3JlZW4nXS5mb3JFYWNoKChmdWxsU2NyZWVuKSA9PiB7XG4gICAgICAgIGxpbmVzLnB1c2goYCR7ZnVsbFNjcmVlbn0sICR7ZnVsbFNjcmVlbn0gKiB7YCk7XG4gICAgICAgIGxpbmVzLnB1c2goJyAgLXdlYmtpdC1maWx0ZXI6IG5vbmUgIWltcG9ydGFudDsnKTtcbiAgICAgICAgbGluZXMucHVzaCgnICBmaWx0ZXI6IG5vbmUgIWltcG9ydGFudDsnKTtcbiAgICAgICAgbGluZXMucHVzaCgnfScpO1xuICAgIH0pO1xuXG4gICAgaWYgKGlzVG9wRnJhbWUpIHtcbiAgICAgICAgY29uc3QgbGlnaHQ6IFtudW1iZXIsIG51bWJlciwgbnVtYmVyXSA9IFsyNTUsIDI1NSwgMjU1XTtcbiAgICAgICAgLy8gSWYgYnJvd3NlciBhZmZlY3RlZCBieSBDaHJvbWl1bSBJc3N1ZSA1MDE1ODIsIHNldCBkYXJrIGJhY2tncm91bmQgb24gaHRtbFxuICAgICAgICAvLyBPciBpZiBicm93c2VyIGlzIEZpcmVmb3ggdjEwMitcbiAgICAgICAgY29uc3QgYmdDb2xvciA9ICghaGFzUGF0Y2hGb3JDaHJvbWl1bUlzc3VlNTAxNTgyKCkgJiYgIWhhc0ZpcmVmb3hOZXdSb290QmVoYXZpb3IoKSkgJiYgY29uZmlnLm1vZGUgPT09IEZpbHRlck1vZGUuZGFyayA/XG4gICAgICAgICAgICBhcHBseUNvbG9yTWF0cml4KGxpZ2h0LCBjcmVhdGVGaWx0ZXJNYXRyaXgoY29uZmlnKSkubWFwKE1hdGgucm91bmQpIDpcbiAgICAgICAgICAgIGxpZ2h0O1xuICAgICAgICBsaW5lcy5wdXNoKCcnKTtcbiAgICAgICAgbGluZXMucHVzaCgnLyogUGFnZSBiYWNrZ3JvdW5kICovJyk7XG4gICAgICAgIGxpbmVzLnB1c2goJ2h0bWwgeycpO1xuICAgICAgICBsaW5lcy5wdXNoKGAgIGJhY2tncm91bmQ6IHJnYigke2JnQ29sb3Iuam9pbignLCcpfSkgIWltcG9ydGFudDtgKTtcbiAgICAgICAgbGluZXMucHVzaCgnfScpO1xuICAgIH1cblxuICAgIGlmIChmaXguY3NzICYmIGZpeC5jc3MubGVuZ3RoID4gMCAmJiBjb25maWcubW9kZSA9PT0gRmlsdGVyTW9kZS5kYXJrKSB7XG4gICAgICAgIGxpbmVzLnB1c2goJycpO1xuICAgICAgICBsaW5lcy5wdXNoKCcvKiBDdXN0b20gcnVsZXMgKi8nKTtcbiAgICAgICAgbGluZXMucHVzaChmaXguY3NzKTtcbiAgICB9XG5cbiAgICBsaW5lcy5wdXNoKCcnKTtcbiAgICBsaW5lcy5wdXNoKCd9Jyk7XG5cbiAgICByZXR1cm4gbGluZXMuam9pbignXFxuJyk7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBnZXRDU1NGaWx0ZXJWYWx1ZShjb25maWc6IFRoZW1lKTogc3RyaW5nIHwgbnVsbCB7XG4gICAgY29uc3QgZmlsdGVyczogc3RyaW5nW10gPSBbXTtcblxuICAgIGlmIChjb25maWcubW9kZSA9PT0gRmlsdGVyTW9kZS5kYXJrKSB7XG4gICAgICAgIGZpbHRlcnMucHVzaCgnaW52ZXJ0KDEwMCUpIGh1ZS1yb3RhdGUoMTgwZGVnKScpO1xuICAgIH1cbiAgICBpZiAoY29uZmlnLmJyaWdodG5lc3MgIT09IDEwMCkge1xuICAgICAgICBmaWx0ZXJzLnB1c2goYGJyaWdodG5lc3MoJHtjb25maWcuYnJpZ2h0bmVzc30lKWApO1xuICAgIH1cbiAgICBpZiAoY29uZmlnLmNvbnRyYXN0ICE9PSAxMDApIHtcbiAgICAgICAgZmlsdGVycy5wdXNoKGBjb250cmFzdCgke2NvbmZpZy5jb250cmFzdH0lKWApO1xuICAgIH1cbiAgICBpZiAoY29uZmlnLmdyYXlzY2FsZSAhPT0gMCkge1xuICAgICAgICBmaWx0ZXJzLnB1c2goYGdyYXlzY2FsZSgke2NvbmZpZy5ncmF5c2NhbGV9JSlgKTtcbiAgICB9XG4gICAgaWYgKGNvbmZpZy5zZXBpYSAhPT0gMCkge1xuICAgICAgICBmaWx0ZXJzLnB1c2goYHNlcGlhKCR7Y29uZmlnLnNlcGlhfSUpYCk7XG4gICAgfVxuXG4gICAgaWYgKGZpbHRlcnMubGVuZ3RoID09PSAwKSB7XG4gICAgICAgIHJldHVybiBudWxsO1xuICAgIH1cblxuICAgIHJldHVybiBmaWx0ZXJzLmpvaW4oJyAnKTtcbn1cblxuZnVuY3Rpb24gY3JlYXRlTGVhZGluZ1J1bGUoZmlsdGVyUm9vdDogc3RyaW5nLCBmaWx0ZXJWYWx1ZTogc3RyaW5nKTogc3RyaW5nIHtcbiAgICByZXR1cm4gW1xuICAgICAgICBgJHtmaWx0ZXJSb290fSB7YCxcbiAgICAgICAgYCAgLXdlYmtpdC1maWx0ZXI6ICR7ZmlsdGVyVmFsdWV9ICFpbXBvcnRhbnQ7YCxcbiAgICAgICAgYCAgZmlsdGVyOiAke2ZpbHRlclZhbHVlfSAhaW1wb3J0YW50O2AsXG4gICAgICAgICd9JyxcbiAgICBdLmpvaW4oJ1xcbicpO1xufVxuXG5mdW5jdGlvbiBqb2luU2VsZWN0b3JzKHNlbGVjdG9yczogc3RyaW5nW10pOiBzdHJpbmcge1xuICAgIHJldHVybiBzZWxlY3RvcnMubWFwKChzKSA9PiBzLnJlcGxhY2UoL1xcLCQvLCAnJykpLmpvaW4oJyxcXG4nKTtcbn1cblxuZnVuY3Rpb24gY3JlYXRlUmV2ZXJzZVJ1bGUocmV2ZXJzZUZpbHRlclZhbHVlOiBzdHJpbmcsIGZpeDogSW52ZXJzaW9uRml4KTogc3RyaW5nIHtcbiAgICBjb25zdCBsaW5lczogc3RyaW5nW10gPSBbXTtcblxuICAgIGlmIChmaXguaW52ZXJ0Lmxlbmd0aCA+IDApIHtcbiAgICAgICAgbGluZXMucHVzaChgJHtqb2luU2VsZWN0b3JzKGZpeC5pbnZlcnQpfSB7YCk7XG4gICAgICAgIGxpbmVzLnB1c2goYCAgLXdlYmtpdC1maWx0ZXI6ICR7cmV2ZXJzZUZpbHRlclZhbHVlfSAhaW1wb3J0YW50O2ApO1xuICAgICAgICBsaW5lcy5wdXNoKGAgIGZpbHRlcjogJHtyZXZlcnNlRmlsdGVyVmFsdWV9ICFpbXBvcnRhbnQ7YCk7XG4gICAgICAgIGxpbmVzLnB1c2goJ30nKTtcbiAgICB9XG5cbiAgICBpZiAoZml4Lm5vaW52ZXJ0Lmxlbmd0aCA+IDApIHtcbiAgICAgICAgbGluZXMucHVzaChgJHtqb2luU2VsZWN0b3JzKGZpeC5ub2ludmVydCl9IHtgKTtcbiAgICAgICAgbGluZXMucHVzaCgnICAtd2Via2l0LWZpbHRlcjogbm9uZSAhaW1wb3J0YW50OycpO1xuICAgICAgICBsaW5lcy5wdXNoKCcgIGZpbHRlcjogbm9uZSAhaW1wb3J0YW50OycpO1xuICAgICAgICBsaW5lcy5wdXNoKCd9Jyk7XG4gICAgfVxuXG4gICAgaWYgKGZpeC5yZW1vdmViZy5sZW5ndGggPiAwKSB7XG4gICAgICAgIGxpbmVzLnB1c2goYCR7am9pblNlbGVjdG9ycyhmaXgucmVtb3ZlYmcpfSB7YCk7XG4gICAgICAgIGxpbmVzLnB1c2goJyAgYmFja2dyb3VuZDogd2hpdGUgIWltcG9ydGFudDsnKTtcbiAgICAgICAgbGluZXMucHVzaCgnfScpO1xuICAgIH1cblxuICAgIHJldHVybiBsaW5lcy5qb2luKCdcXG4nKTtcbn1cblxuLyoqXG4qIFJldHVybnMgZml4ZXMgZm9yIGEgZ2l2ZW4gVVJMLlxuKiBJZiBubyBtYXRjaGVzIGZvdW5kLCBjb21tb24gZml4ZXMgd2lsbCBiZSByZXR1cm5lZC5cbiogQHBhcmFtIHVybCBTaXRlIFVSTC5cbiogQHBhcmFtIGludmVyc2lvbkZpeGVzIExpc3Qgb2YgaW52ZXJzaW9uIGZpeGVzLlxuKi9cbmV4cG9ydCBmdW5jdGlvbiBnZXRJbnZlcnNpb25GaXhlc0Zvcih1cmw6IHN0cmluZywgZml4ZXM6IHN0cmluZywgaW5kZXg6IFNpdGVGaXhlc0luZGV4KTogSW52ZXJzaW9uRml4IHtcbiAgICBjb25zdCBpbnZlcnNpb25GaXhlcyA9IGdldFNpdGVzRml4ZXNGb3IodXJsLCBmaXhlcywgaW5kZXgsIHBhcnNlSW52ZXJzaW9uRml4ZXMpO1xuXG4gICAgY29uc3QgY29tbW9uID0ge1xuICAgICAgICB1cmw6IGludmVyc2lvbkZpeGVzWzBdLnVybCxcbiAgICAgICAgaW52ZXJ0OiBpbnZlcnNpb25GaXhlc1swXS5pbnZlcnQgfHwgW10sXG4gICAgICAgIG5vaW52ZXJ0OiBpbnZlcnNpb25GaXhlc1swXS5ub2ludmVydCB8fCBbXSxcbiAgICAgICAgcmVtb3ZlYmc6IGludmVyc2lvbkZpeGVzWzBdLnJlbW92ZWJnIHx8IFtdLFxuICAgICAgICBjc3M6IGludmVyc2lvbkZpeGVzWzBdLmNzcyB8fCAnJyxcbiAgICB9O1xuXG4gICAgaWYgKHVybCkge1xuICAgICAgICAvLyBTZWFyY2ggZm9yIG1hdGNoIHdpdGggZ2l2ZW4gVVJMXG4gICAgICAgIGNvbnN0IG1hdGNoZXMgPSBpbnZlcnNpb25GaXhlc1xuICAgICAgICAgICAgLnNsaWNlKDEpXG4gICAgICAgICAgICAuZmlsdGVyKChzKSA9PiBpc1VSTEluTGlzdCh1cmwsIHMudXJsKSlcbiAgICAgICAgICAgIC5zb3J0KChhLCBiKSA9PiBiLnVybFswXS5sZW5ndGggLSBhLnVybFswXS5sZW5ndGgpO1xuICAgICAgICBpZiAobWF0Y2hlcy5sZW5ndGggPiAwKSB7XG4gICAgICAgICAgICBjb25zdCBmb3VuZCA9IG1hdGNoZXNbMF07XG4gICAgICAgICAgICByZXR1cm4ge1xuICAgICAgICAgICAgICAgIHVybDogZm91bmQudXJsLFxuICAgICAgICAgICAgICAgIGludmVydDogY29tbW9uLmludmVydC5jb25jYXQoZm91bmQuaW52ZXJ0IHx8IFtdKSxcbiAgICAgICAgICAgICAgICBub2ludmVydDogY29tbW9uLm5vaW52ZXJ0LmNvbmNhdChmb3VuZC5ub2ludmVydCB8fCBbXSksXG4gICAgICAgICAgICAgICAgcmVtb3ZlYmc6IGNvbW1vbi5yZW1vdmViZy5jb25jYXQoZm91bmQucmVtb3ZlYmcgfHwgW10pLFxuICAgICAgICAgICAgICAgIGNzczogW2NvbW1vbi5jc3MsIGZvdW5kLmNzc10uZmlsdGVyKChzKSA9PiBzKS5qb2luKCdcXG4nKSxcbiAgICAgICAgICAgIH07XG4gICAgICAgIH1cbiAgICB9XG4gICAgcmV0dXJuIGNvbW1vbjtcbn1cblxuY29uc3QgaW52ZXJzaW9uRml4ZXNDb21tYW5kczogeyBba2V5OiBzdHJpbmddOiBrZXlvZiBJbnZlcnNpb25GaXggfSA9IHtcbiAgICAnSU5WRVJUJzogJ2ludmVydCcsXG4gICAgJ05PIElOVkVSVCc6ICdub2ludmVydCcsXG4gICAgJ1JFTU9WRSBCRyc6ICdyZW1vdmViZycsXG4gICAgJ0NTUyc6ICdjc3MnLFxufTtcblxuZXhwb3J0IGZ1bmN0aW9uIHBhcnNlSW52ZXJzaW9uRml4ZXModGV4dDogc3RyaW5nKTogSW52ZXJzaW9uRml4W10ge1xuICAgIHJldHVybiBwYXJzZVNpdGVzRml4ZXNDb25maWc8SW52ZXJzaW9uRml4Pih0ZXh0LCB7XG4gICAgICAgIGNvbW1hbmRzOiBPYmplY3Qua2V5cyhpbnZlcnNpb25GaXhlc0NvbW1hbmRzKSxcbiAgICAgICAgZ2V0Q29tbWFuZFByb3BOYW1lOiAoY29tbWFuZCkgPT4gaW52ZXJzaW9uRml4ZXNDb21tYW5kc1tjb21tYW5kXSxcbiAgICAgICAgcGFyc2VDb21tYW5kVmFsdWU6IChjb21tYW5kLCB2YWx1ZSkgPT4ge1xuICAgICAgICAgICAgaWYgKGNvbW1hbmQgPT09ICdDU1MnKSB7XG4gICAgICAgICAgICAgICAgcmV0dXJuIHZhbHVlLnRyaW0oKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIHJldHVybiBwYXJzZUFycmF5KHZhbHVlKTtcbiAgICAgICAgfSxcbiAgICB9KTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGZvcm1hdEludmVyc2lvbkZpeGVzKGludmVyc2lvbkZpeGVzOiBJbnZlcnNpb25GaXhbXSk6IHN0cmluZyB7XG4gICAgY29uc3QgZml4ZXMgPSBpbnZlcnNpb25GaXhlcy5zbGljZSgpLnNvcnQoKGEsIGIpID0+IGNvbXBhcmVVUkxQYXR0ZXJucyhhLnVybFswXSwgYi51cmxbMF0pKTtcblxuICAgIHJldHVybiBmb3JtYXRTaXRlc0ZpeGVzQ29uZmlnKGZpeGVzLCB7XG4gICAgICAgIHByb3BzOiBPYmplY3QudmFsdWVzKGludmVyc2lvbkZpeGVzQ29tbWFuZHMpLFxuICAgICAgICBnZXRQcm9wQ29tbWFuZE5hbWU6IChwcm9wKSA9PiBPYmplY3QuZW50cmllcyhpbnZlcnNpb25GaXhlc0NvbW1hbmRzKS5maW5kKChbLCBwXSkgPT4gcCA9PT0gcHJvcCkhWzBdLFxuICAgICAgICBmb3JtYXRQcm9wVmFsdWU6IChwcm9wLCB2YWx1ZSkgPT4ge1xuICAgICAgICAgICAgaWYgKHByb3AgPT09ICdjc3MnKSB7XG4gICAgICAgICAgICAgICAgcmV0dXJuICh2YWx1ZSBhcyBzdHJpbmcpLnRyaW0oKS5yZXBsYWNlKC9cXG4rL2csICdcXG4nKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIHJldHVybiBmb3JtYXRBcnJheSh2YWx1ZSBhcyBzdHJpbmdbXSkudHJpbSgpO1xuICAgICAgICB9LFxuICAgICAgICBzaG91bGRJZ25vcmVQcm9wOiAocHJvcCwgdmFsdWUpID0+IHtcbiAgICAgICAgICAgIGlmIChwcm9wID09PSAnY3NzJykge1xuICAgICAgICAgICAgICAgIHJldHVybiAhdmFsdWU7XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICByZXR1cm4gIShBcnJheS5pc0FycmF5KHZhbHVlKSAmJiB2YWx1ZS5sZW5ndGggPiAwKTtcbiAgICAgICAgfSxcbiAgICB9KTtcbn1cbiIsImltcG9ydCB0eXBlIHtEZXRlY3RvckhpbnR9IGZyb20gJy4uL2RlZmluaXRpb25zJztcbmltcG9ydCB7cGFyc2VBcnJheSwgZm9ybWF0QXJyYXl9IGZyb20gJy4uL3V0aWxzL3RleHQnO1xuaW1wb3J0IHtjb21wYXJlVVJMUGF0dGVybnN9IGZyb20gJy4uL3V0aWxzL3VybCc7XG5cbmltcG9ydCB7Zm9ybWF0U2l0ZXNGaXhlc0NvbmZpZ30gZnJvbSAnLi91dGlscy9mb3JtYXQnO1xuaW1wb3J0IHtwYXJzZVNpdGVzRml4ZXNDb25maWcsIGdldFNpdGVzRml4ZXNGb3J9IGZyb20gJy4vdXRpbHMvcGFyc2UnO1xuaW1wb3J0IHR5cGUge1NpdGVGaXhlc0luZGV4LCBTaXRlc0ZpeGVzUGFyc2VyT3B0aW9uc30gZnJvbSAnLi91dGlscy9wYXJzZSc7XG5cbmNvbnN0IGRldGVjdG9ySGludHNDb21tYW5kczogeyBba2V5OiBzdHJpbmddOiBrZXlvZiBEZXRlY3RvckhpbnQgfSA9IHtcbiAgICAnVEFSR0VUJzogJ3RhcmdldCcsXG4gICAgJ01BVENIJzogJ21hdGNoJyxcbiAgICAnTk8gREFSSyBUSEVNRSc6ICdub0RhcmtUaGVtZScsXG4gICAgJ1NZU1RFTSBUSEVNRSc6ICdzeXN0ZW1UaGVtZScsXG4gICAgJ0lGUkFNRSc6ICdpZnJhbWUnLFxufTtcblxuY29uc3QgZGV0ZWN0b3JQYXJzZXJPcHRpb25zOiBTaXRlc0ZpeGVzUGFyc2VyT3B0aW9uczxEZXRlY3RvckhpbnQ+ID0ge1xuICAgIGNvbW1hbmRzOiBPYmplY3Qua2V5cyhkZXRlY3RvckhpbnRzQ29tbWFuZHMpLFxuICAgIGdldENvbW1hbmRQcm9wTmFtZTogKGNvbW1hbmQpID0+IGRldGVjdG9ySGludHNDb21tYW5kc1tjb21tYW5kXSxcbiAgICBwYXJzZUNvbW1hbmRWYWx1ZTogKGNvbW1hbmQsIHZhbHVlKSA9PiB7XG4gICAgICAgIGlmIChjb21tYW5kID09PSAnVEFSR0VUJykge1xuICAgICAgICAgICAgcmV0dXJuIHZhbHVlLnRyaW0oKTtcbiAgICAgICAgfVxuICAgICAgICBpZiAoY29tbWFuZCA9PT0gJ05PIERBUksgVEhFTUUnIHx8IGNvbW1hbmQgPT09ICdTWVNURU0gVEhFTUUnKSB7XG4gICAgICAgICAgICByZXR1cm4gdHJ1ZTtcbiAgICAgICAgfVxuICAgICAgICByZXR1cm4gcGFyc2VBcnJheSh2YWx1ZSk7XG4gICAgfSxcbn07XG5cbmV4cG9ydCBmdW5jdGlvbiBwYXJzZURldGVjdG9ySGludHModGV4dDogc3RyaW5nKTogRGV0ZWN0b3JIaW50W10ge1xuICAgIHJldHVybiBwYXJzZVNpdGVzRml4ZXNDb25maWc8RGV0ZWN0b3JIaW50Pih0ZXh0LCBkZXRlY3RvclBhcnNlck9wdGlvbnMpO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gZm9ybWF0RGV0ZWN0b3JIaW50cyhkZXRlY3RvckhpbnRzOiBEZXRlY3RvckhpbnRbXSk6IHN0cmluZyB7XG4gICAgY29uc3QgZml4ZXMgPSBkZXRlY3RvckhpbnRzLnNsaWNlKCkuc29ydCgoYSwgYikgPT4gY29tcGFyZVVSTFBhdHRlcm5zKGEudXJsWzBdLCBiLnVybFswXSkpO1xuXG4gICAgcmV0dXJuIGZvcm1hdFNpdGVzRml4ZXNDb25maWcoZml4ZXMsIHtcbiAgICAgICAgcHJvcHM6IE9iamVjdC52YWx1ZXMoZGV0ZWN0b3JIaW50c0NvbW1hbmRzKSxcbiAgICAgICAgZ2V0UHJvcENvbW1hbmROYW1lOiAocHJvcCkgPT4gT2JqZWN0LmVudHJpZXMoZGV0ZWN0b3JIaW50c0NvbW1hbmRzKS5maW5kKChbLCBwXSkgPT4gcCA9PT0gcHJvcCkhWzBdLFxuICAgICAgICBmb3JtYXRQcm9wVmFsdWU6IChwcm9wOiBrZXlvZiBEZXRlY3RvckhpbnQsIHZhbHVlKSA9PiB7XG4gICAgICAgICAgICBpZiAoQXJyYXkuaXNBcnJheSh2YWx1ZSkpIHtcbiAgICAgICAgICAgICAgICByZXR1cm4gZm9ybWF0QXJyYXkodmFsdWUpLnRyaW0oKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGlmIChwcm9wID09PSAnbm9EYXJrVGhlbWUnIHx8IHByb3AgPT09ICdzeXN0ZW1UaGVtZScpIHtcbiAgICAgICAgICAgICAgICByZXR1cm4gJyc7XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICByZXR1cm4gU3RyaW5nKHZhbHVlKS50cmltKCk7XG4gICAgICAgIH0sXG4gICAgICAgIHNob3VsZElnbm9yZVByb3A6IChfcHJvcCwgdmFsdWUpID0+IHtcbiAgICAgICAgICAgIHJldHVybiAhdmFsdWU7XG4gICAgICAgIH0sXG4gICAgfSk7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBnZXREZXRlY3RvckhpbnRzRm9yKHVybDogc3RyaW5nLCB0ZXh0OiBzdHJpbmcsIGluZGV4OiBTaXRlRml4ZXNJbmRleCk6IERldGVjdG9ySGludFtdIHwgbnVsbCB7XG4gICAgY29uc3QgZml4ZXMgPSBnZXRTaXRlc0ZpeGVzRm9yKHVybCwgdGV4dCwgaW5kZXgsIHBhcnNlRGV0ZWN0b3JIaW50cyk7XG5cbiAgICBpZiAoZml4ZXMubGVuZ3RoID09PSAwKSB7XG4gICAgICAgIHJldHVybiBudWxsO1xuICAgIH1cblxuICAgIHJldHVybiBmaXhlcztcbn1cbiIsImNvbnN0IGNzc0NvbW1lbnRzUmVnZXggPSAvXFwvXFwqW1xcc1xcU10qP1xcKlxcLy9nO1xuXG5leHBvcnQgZnVuY3Rpb24gcmVtb3ZlQ1NTQ29tbWVudHMoY3NzVGV4dDogc3RyaW5nKTogc3RyaW5nIHtcbiAgICByZXR1cm4gY3NzVGV4dC5yZXBsYWNlKGNzc0NvbW1lbnRzUmVnZXgsICcnKTtcbn1cbiIsImltcG9ydCB7Z2V0T3BlbkNsb3NlUmFuZ2UsIHNwbGl0RXhjbHVkaW5nfSBmcm9tICcuLi90ZXh0JztcbmltcG9ydCB0eXBlIHtUZXh0UmFuZ2V9IGZyb20gJy4uL3RleHQnO1xuXG5pbXBvcnQge3JlbW92ZUNTU0NvbW1lbnRzfSBmcm9tICcuL2Nzcy10ZXh0JztcblxuZXhwb3J0IGludGVyZmFjZSBQYXJzZWREZWNsYXJhdGlvbiB7XG4gICAgcHJvcGVydHk6IHN0cmluZztcbiAgICB2YWx1ZTogc3RyaW5nO1xuICAgIGltcG9ydGFudDogYm9vbGVhbjtcbn1cblxuZXhwb3J0IGludGVyZmFjZSBQYXJzZWRTdHlsZVJ1bGUge1xuICAgIHNlbGVjdG9yczogc3RyaW5nW107XG4gICAgZGVjbGFyYXRpb25zOiBQYXJzZWREZWNsYXJhdGlvbltdO1xufVxuXG5leHBvcnQgaW50ZXJmYWNlIFBhcnNlZEF0UnVsZSB7XG4gICAgdHlwZTogc3RyaW5nO1xuICAgIHF1ZXJ5OiBzdHJpbmc7XG4gICAgcnVsZXM6IEFycmF5PFBhcnNlZEF0UnVsZSB8IFBhcnNlZFN0eWxlUnVsZT47XG59XG5cbmV4cG9ydCB0eXBlIFBhcnNlZENTUyA9IEFycmF5PFBhcnNlZEF0UnVsZSB8IFBhcnNlZFN0eWxlUnVsZT47XG5cbmV4cG9ydCBmdW5jdGlvbiBwYXJzZUNTUyhjc3NUZXh0OiBzdHJpbmcpOiBQYXJzZWRDU1Mge1xuICAgIGNzc1RleHQgPSByZW1vdmVDU1NDb21tZW50cyhjc3NUZXh0KTtcbiAgICBjc3NUZXh0ID0gY3NzVGV4dC50cmltKCk7XG4gICAgaWYgKCFjc3NUZXh0KSB7XG4gICAgICAgIHJldHVybiBbXTtcbiAgICB9XG5cbiAgICBjb25zdCBydWxlczogUGFyc2VkQ1NTID0gW107XG5cbiAgICAvLyBGaW5kIHsuLi59IHJhbmdlcyBleGNsdWRpbmcgaW5zaWRlIG9mIFwiLi4uXCIsIFsuLi5dIGV0Yy5cbiAgICBjb25zdCBleGNsdWRlUmFuZ2VzID0gZ2V0VG9rZW5FeGNsdXNpb25SYW5nZXMoY3NzVGV4dCk7XG4gICAgY29uc3QgYnJhY2tldFJhbmdlcyA9IGdldEFsbE9wZW5DbG9zZVJhbmdlcyhjc3NUZXh0LCAneycsICd9JywgZXhjbHVkZVJhbmdlcyk7XG5cbiAgICBsZXQgcnVsZVN0YXJ0ID0gMDtcbiAgICBicmFja2V0UmFuZ2VzLmZvckVhY2goKGJyYWNrZXRzKSA9PiB7XG4gICAgICAgIGNvbnN0IGtleSA9IGNzc1RleHQuc3Vic3RyaW5nKHJ1bGVTdGFydCwgYnJhY2tldHMuc3RhcnQpLnRyaW0oKTtcbiAgICAgICAgY29uc3QgY29udGVudCA9IGNzc1RleHQuc3Vic3RyaW5nKGJyYWNrZXRzLnN0YXJ0ICsgMSwgYnJhY2tldHMuZW5kIC0gMSk7XG5cbiAgICAgICAgaWYgKGtleS5zdGFydHNXaXRoKCdAJykpIHtcbiAgICAgICAgICAgIGNvbnN0IHR5cGVFbmRJbmRleCA9IGtleS5zZWFyY2goL1tcXHNcXChdLyk7XG4gICAgICAgICAgICBjb25zdCBydWxlOiBQYXJzZWRBdFJ1bGUgPSB7XG4gICAgICAgICAgICAgICAgdHlwZTogdHlwZUVuZEluZGV4IDwgMCA/IGtleSA6IGtleS5zdWJzdHJpbmcoMCwgdHlwZUVuZEluZGV4KSxcbiAgICAgICAgICAgICAgICBxdWVyeTogdHlwZUVuZEluZGV4IDwgMCA/ICcnIDoga2V5LnN1YnN0cmluZyh0eXBlRW5kSW5kZXgpLnRyaW0oKSxcbiAgICAgICAgICAgICAgICBydWxlczogcGFyc2VDU1MoY29udGVudCksXG4gICAgICAgICAgICB9O1xuICAgICAgICAgICAgcnVsZXMucHVzaChydWxlKTtcbiAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgIGNvbnN0IHJ1bGU6IFBhcnNlZFN0eWxlUnVsZSA9IHtcbiAgICAgICAgICAgICAgICBzZWxlY3RvcnM6IHBhcnNlU2VsZWN0b3JzKGtleSksXG4gICAgICAgICAgICAgICAgZGVjbGFyYXRpb25zOiBwYXJzZURlY2xhcmF0aW9ucyhjb250ZW50KSxcbiAgICAgICAgICAgIH07XG4gICAgICAgICAgICBydWxlcy5wdXNoKHJ1bGUpO1xuICAgICAgICB9XG5cbiAgICAgICAgcnVsZVN0YXJ0ID0gYnJhY2tldHMuZW5kO1xuICAgIH0pO1xuXG4gICAgcmV0dXJuIHJ1bGVzO1xufVxuXG5mdW5jdGlvbiBnZXRBbGxPcGVuQ2xvc2VSYW5nZXMoXG4gICAgaW5wdXQ6IHN0cmluZyxcbiAgICBvcGVuVG9rZW46IHN0cmluZyxcbiAgICBjbG9zZVRva2VuOiBzdHJpbmcsXG4gICAgZXhjbHVkZVJhbmdlczogVGV4dFJhbmdlW10gPSBbXSxcbikge1xuICAgIGNvbnN0IHJhbmdlczogVGV4dFJhbmdlW10gPSBbXTtcbiAgICBsZXQgaSA9IDA7XG4gICAgbGV0IHJhbmdlOiBUZXh0UmFuZ2UgfCBudWxsO1xuICAgIHdoaWxlICgocmFuZ2UgPSBnZXRPcGVuQ2xvc2VSYW5nZShpbnB1dCwgaSwgb3BlblRva2VuLCBjbG9zZVRva2VuLCBleGNsdWRlUmFuZ2VzKSkpIHtcbiAgICAgICAgcmFuZ2VzLnB1c2gocmFuZ2UpO1xuICAgICAgICBpID0gcmFuZ2UuZW5kO1xuICAgIH1cbiAgICByZXR1cm4gcmFuZ2VzO1xufVxuXG5mdW5jdGlvbiBnZXRUb2tlbkV4Y2x1c2lvblJhbmdlcyhjc3NUZXh0OiBzdHJpbmcpIHtcbiAgICBjb25zdCBzaW5nbGVRdW90ZUdvZXNGaXJzdCA9IGNzc1RleHQuaW5kZXhPZihcIidcIikgPCBjc3NUZXh0LmluZGV4T2YoJ1wiJyk7XG4gICAgY29uc3QgZmlyc3RRdW90ZSA9IHNpbmdsZVF1b3RlR29lc0ZpcnN0ID8gXCInXCIgOiAnXCInO1xuICAgIGNvbnN0IHNlY29uZFF1b3RlID0gc2luZ2xlUXVvdGVHb2VzRmlyc3QgPyAnXCInIDogXCInXCI7XG4gICAgY29uc3QgZXhjbHVkZVJhbmdlczogVGV4dFJhbmdlW10gPSBnZXRBbGxPcGVuQ2xvc2VSYW5nZXMoY3NzVGV4dCwgZmlyc3RRdW90ZSwgZmlyc3RRdW90ZSk7XG4gICAgZXhjbHVkZVJhbmdlcy5wdXNoKC4uLmdldEFsbE9wZW5DbG9zZVJhbmdlcyhjc3NUZXh0LCBzZWNvbmRRdW90ZSwgc2Vjb25kUXVvdGUsIGV4Y2x1ZGVSYW5nZXMpKTtcbiAgICBleGNsdWRlUmFuZ2VzLnB1c2goLi4uZ2V0QWxsT3BlbkNsb3NlUmFuZ2VzKGNzc1RleHQsICdbJywgJ10nLCBleGNsdWRlUmFuZ2VzKSk7XG4gICAgZXhjbHVkZVJhbmdlcy5wdXNoKC4uLmdldEFsbE9wZW5DbG9zZVJhbmdlcyhjc3NUZXh0LCAnKCcsICcpJywgZXhjbHVkZVJhbmdlcykpO1xuICAgIHJldHVybiBleGNsdWRlUmFuZ2VzO1xufVxuXG5mdW5jdGlvbiBwYXJzZVNlbGVjdG9ycyhzZWxlY3RvclRleHQ6IHN0cmluZykge1xuICAgIGNvbnN0IGV4Y2x1ZGVSYW5nZXMgPSBnZXRUb2tlbkV4Y2x1c2lvblJhbmdlcyhzZWxlY3RvclRleHQpO1xuICAgIHJldHVybiBzcGxpdEV4Y2x1ZGluZyhzZWxlY3RvclRleHQsICcsJywgZXhjbHVkZVJhbmdlcyk7XG59XG5cbmZ1bmN0aW9uIHBhcnNlRGVjbGFyYXRpb25zKGNzc0RlY2xhcmF0aW9uc1RleHQ6IHN0cmluZykge1xuICAgIGNvbnN0IGRlY2xhcmF0aW9uczogUGFyc2VkRGVjbGFyYXRpb25bXSA9IFtdO1xuICAgIGNvbnN0IGV4Y2x1ZGVSYW5nZXMgPSBnZXRUb2tlbkV4Y2x1c2lvblJhbmdlcyhjc3NEZWNsYXJhdGlvbnNUZXh0KTtcbiAgICBzcGxpdEV4Y2x1ZGluZyhjc3NEZWNsYXJhdGlvbnNUZXh0LCAnOycsIGV4Y2x1ZGVSYW5nZXMpLmZvckVhY2goKHBhcnQpID0+IHtcbiAgICAgICAgY29uc3QgY29sb25JbmRleCA9IHBhcnQuaW5kZXhPZignOicpO1xuICAgICAgICBpZiAoY29sb25JbmRleCA+IDApIHtcbiAgICAgICAgICAgIGNvbnN0IGltcG9ydGFudEluZGV4ID0gcGFydC5pbmRleE9mKCchaW1wb3J0YW50Jyk7XG4gICAgICAgICAgICBkZWNsYXJhdGlvbnMucHVzaCh7XG4gICAgICAgICAgICAgICAgcHJvcGVydHk6IHBhcnQuc3Vic3RyaW5nKDAsIGNvbG9uSW5kZXgpLnRyaW0oKSxcbiAgICAgICAgICAgICAgICB2YWx1ZTogcGFydC5zdWJzdHJpbmcoY29sb25JbmRleCArIDEsIGltcG9ydGFudEluZGV4ID4gMCA/IGltcG9ydGFudEluZGV4IDogcGFydC5sZW5ndGgpLnRyaW0oKSxcbiAgICAgICAgICAgICAgICBpbXBvcnRhbnQ6IGltcG9ydGFudEluZGV4ID4gMCxcbiAgICAgICAgICAgIH0pO1xuICAgICAgICB9XG4gICAgfSk7XG4gICAgcmV0dXJuIGRlY2xhcmF0aW9ucztcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGlzUGFyc2VkU3R5bGVSdWxlKHJ1bGU6IFBhcnNlZEF0UnVsZSB8IFBhcnNlZFN0eWxlUnVsZSk6IHJ1bGUgaXMgUGFyc2VkU3R5bGVSdWxlIHtcbiAgICByZXR1cm4gJ3NlbGVjdG9ycycgaW4gcnVsZTtcbn1cbiIsImltcG9ydCB7aXNQYXJzZWRTdHlsZVJ1bGUsIHBhcnNlQ1NTfSBmcm9tICcuLi9jc3MtdGV4dC9wYXJzZS1jc3MnO1xuaW1wb3J0IHR5cGUge1BhcnNlZEF0UnVsZSwgUGFyc2VkQ1NTLCBQYXJzZWREZWNsYXJhdGlvbiwgUGFyc2VkU3R5bGVSdWxlfSBmcm9tICcuLi9jc3MtdGV4dC9wYXJzZS1jc3MnO1xuXG5leHBvcnQgZnVuY3Rpb24gZm9ybWF0Q1NTKGNzc1RleHQ6IHN0cmluZyk6IHN0cmluZyB7XG4gICAgY29uc3QgcGFyc2VkID0gcGFyc2VDU1MoY3NzVGV4dCk7XG4gICAgcmV0dXJuIGZvcm1hdFBhcnNlZENTUyhwYXJzZWQpO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gZm9ybWF0UGFyc2VkQ1NTKHBhcnNlZDogUGFyc2VkQ1NTKTogc3RyaW5nIHtcbiAgICBjb25zdCBsaW5lczogc3RyaW5nW10gPSBbXTtcbiAgICBjb25zdCB0YWIgPSAnICAgICc7XG5cbiAgICBmdW5jdGlvbiBmb3JtYXRSdWxlKHJ1bGU6IFBhcnNlZEF0UnVsZSB8IFBhcnNlZFN0eWxlUnVsZSwgaW5kZW50OiBzdHJpbmcpIHtcbiAgICAgICAgaWYgKGlzUGFyc2VkU3R5bGVSdWxlKHJ1bGUpKSB7XG4gICAgICAgICAgICBmb3JtYXRTdHlsZVJ1bGUocnVsZSBhcyBQYXJzZWRTdHlsZVJ1bGUsIGluZGVudCk7XG4gICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICBmb3JtYXRBdFJ1bGUocnVsZSwgaW5kZW50KTtcbiAgICAgICAgfVxuICAgIH1cblxuICAgIGZ1bmN0aW9uIGZvcm1hdEF0UnVsZSh7dHlwZSwgcXVlcnksIHJ1bGVzfTogUGFyc2VkQXRSdWxlLCBpbmRlbnQ6IHN0cmluZykge1xuICAgICAgICBsaW5lcy5wdXNoKGAke2luZGVudH0ke3R5cGV9ICR7cXVlcnl9IHtgKTtcbiAgICAgICAgcnVsZXMuZm9yRWFjaCgoY2hpbGQpID0+IGZvcm1hdFJ1bGUoY2hpbGQsIGAke2luZGVudH0ke3RhYn1gKSk7XG4gICAgICAgIGxpbmVzLnB1c2goYCR7aW5kZW50fX1gKTtcbiAgICB9XG5cbiAgICBmdW5jdGlvbiBmb3JtYXRTdHlsZVJ1bGUoe3NlbGVjdG9ycywgZGVjbGFyYXRpb25zfTogUGFyc2VkU3R5bGVSdWxlLCBpbmRlbnQ6IHN0cmluZykge1xuICAgICAgICBjb25zdCBsYXN0U2VsZWN0b3JJbmRleCA9IHNlbGVjdG9ycy5sZW5ndGggLSAxO1xuICAgICAgICBzZWxlY3RvcnMuZm9yRWFjaCgoc2VsZWN0b3IsIGkpID0+IHtcbiAgICAgICAgICAgIGxpbmVzLnB1c2goYCR7aW5kZW50fSR7c2VsZWN0b3J9JHtpIDwgbGFzdFNlbGVjdG9ySW5kZXggPyAnLCcgOiAnIHsnfWApO1xuICAgICAgICB9KTtcbiAgICAgICAgY29uc3Qgc29ydGVkID0gc29ydERlY2xhcmF0aW9ucyhkZWNsYXJhdGlvbnMpO1xuICAgICAgICBzb3J0ZWQuZm9yRWFjaCgoe3Byb3BlcnR5LCB2YWx1ZSwgaW1wb3J0YW50fSkgPT4ge1xuICAgICAgICAgICAgbGluZXMucHVzaChgJHtpbmRlbnR9JHt0YWJ9JHtwcm9wZXJ0eX06ICR7dmFsdWV9JHtpbXBvcnRhbnQgPyAnICFpbXBvcnRhbnQnIDogJyd9O2ApO1xuICAgICAgICB9KTtcbiAgICAgICAgbGluZXMucHVzaChgJHtpbmRlbnR9fWApO1xuICAgIH1cblxuICAgIGNsZWFyRW1wdHlSdWxlcyhwYXJzZWQpO1xuICAgIHBhcnNlZC5mb3JFYWNoKChydWxlKSA9PiBmb3JtYXRSdWxlKHJ1bGUsICcnKSk7XG4gICAgcmV0dXJuIGxpbmVzLmpvaW4oJ1xcbicpO1xufVxuXG5mdW5jdGlvbiBzb3J0RGVjbGFyYXRpb25zKGRlY2xhcmF0aW9uczogUGFyc2VkRGVjbGFyYXRpb25bXSkge1xuICAgIGNvbnN0IHByZWZpeFJlZ2V4ID0gL14tW2Etel0tLztcbiAgICByZXR1cm4gWy4uLmRlY2xhcmF0aW9uc10uc29ydCgoYSwgYikgPT4ge1xuICAgICAgICBjb25zdCBhUHJvcCA9IGEucHJvcGVydHk7XG4gICAgICAgIGNvbnN0IGJQcm9wID0gYi5wcm9wZXJ0eTtcbiAgICAgICAgY29uc3QgYVByZWZpeCA9IGFQcm9wLm1hdGNoKHByZWZpeFJlZ2V4KT8uWzBdID8/ICcnO1xuICAgICAgICBjb25zdCBiUHJlZml4ID0gYlByb3AubWF0Y2gocHJlZml4UmVnZXgpPy5bMF0gPz8gJyc7XG4gICAgICAgIGNvbnN0IGFOb3JtID0gYVByZWZpeCA/IGFQcm9wLnJlcGxhY2UocHJlZml4UmVnZXgsICcnKSA6IGFQcm9wO1xuICAgICAgICBjb25zdCBiTm9ybSA9IGJQcmVmaXggPyBiUHJvcC5yZXBsYWNlKHByZWZpeFJlZ2V4LCAnJykgOiBiUHJvcDtcbiAgICAgICAgaWYgKGFOb3JtID09PSBiTm9ybSkge1xuICAgICAgICAgICAgcmV0dXJuIGFQcmVmaXgubG9jYWxlQ29tcGFyZShiUHJlZml4KTtcbiAgICAgICAgfVxuICAgICAgICByZXR1cm4gYU5vcm0ubG9jYWxlQ29tcGFyZShiTm9ybSk7XG4gICAgfSk7XG59XG5cbmZ1bmN0aW9uIGNsZWFyRW1wdHlSdWxlcyhydWxlczogQXJyYXk8UGFyc2VkQXRSdWxlIHwgUGFyc2VkU3R5bGVSdWxlPikge1xuICAgIGZvciAobGV0IGkgPSBydWxlcy5sZW5ndGggLSAxOyBpID49IDA7IGktLSkge1xuICAgICAgICBjb25zdCBydWxlID0gcnVsZXNbaV07XG4gICAgICAgIGlmIChpc1BhcnNlZFN0eWxlUnVsZShydWxlKSkge1xuICAgICAgICAgICAgaWYgKHJ1bGUuZGVjbGFyYXRpb25zLmxlbmd0aCA9PT0gMCkge1xuICAgICAgICAgICAgICAgIHJ1bGVzLnNwbGljZShpLCAxKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgIGNsZWFyRW1wdHlSdWxlcyhydWxlLnJ1bGVzKTtcbiAgICAgICAgICAgIGlmIChydWxlLnJ1bGVzLmxlbmd0aCA9PT0gMCkge1xuICAgICAgICAgICAgICAgIHJ1bGVzLnNwbGljZShpLCAxKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgIH1cbn1cbiIsImltcG9ydCB0eXBlIHtEeW5hbWljVGhlbWVGaXh9IGZyb20gJy4uL2RlZmluaXRpb25zJztcbmltcG9ydCB7Zm9ybWF0Q1NTfSBmcm9tICcuLi91dGlscy9jc3MtdGV4dC9mb3JtYXQtY3NzJztcbmltcG9ydCB7cGFyc2VBcnJheSwgZm9ybWF0QXJyYXl9IGZyb20gJy4uL3V0aWxzL3RleHQnO1xuaW1wb3J0IHtjb21wYXJlVVJMUGF0dGVybnN9IGZyb20gJy4uL3V0aWxzL3VybCc7XG5cbmltcG9ydCB7Zm9ybWF0U2l0ZXNGaXhlc0NvbmZpZ30gZnJvbSAnLi91dGlscy9mb3JtYXQnO1xuaW1wb3J0IHtwYXJzZVNpdGVzRml4ZXNDb25maWcsIGdldFNpdGVzRml4ZXNGb3IsIGdldERvbWFpbn0gZnJvbSAnLi91dGlscy9wYXJzZSc7XG5pbXBvcnQgdHlwZSB7U2l0ZUZpeGVzSW5kZXh9IGZyb20gJy4vdXRpbHMvcGFyc2UnO1xuXG5kZWNsYXJlIGNvbnN0IF9fQ0hST01JVU1fTVYyX186IGJvb2xlYW47XG5kZWNsYXJlIGNvbnN0IF9fQ0hST01JVU1fTVYzX186IGJvb2xlYW47XG5cbmNvbnN0IGR5bmFtaWNUaGVtZUZpeGVzQ29tbWFuZHM6IHsgW2tleTogc3RyaW5nXToga2V5b2YgRHluYW1pY1RoZW1lRml4IH0gPSB7XG4gICAgJ0lOVkVSVCc6ICdpbnZlcnQnLFxuICAgICdDU1MnOiAnY3NzJyxcbiAgICAnSUdOT1JFIElOTElORSBTVFlMRSc6ICdpZ25vcmVJbmxpbmVTdHlsZScsXG4gICAgJ0lHTk9SRSBJTUFHRSBBTkFMWVNJUyc6ICdpZ25vcmVJbWFnZUFuYWx5c2lzJyxcbiAgICAnSUdOT1JFIENTUyBVUkwnOiAnaWdub3JlQ1NTVXJsJyxcbn07XG5cbmV4cG9ydCBmdW5jdGlvbiBwYXJzZUR5bmFtaWNUaGVtZUZpeGVzKHRleHQ6IHN0cmluZyk6IER5bmFtaWNUaGVtZUZpeFtdIHtcbiAgICByZXR1cm4gcGFyc2VTaXRlc0ZpeGVzQ29uZmlnPER5bmFtaWNUaGVtZUZpeD4odGV4dCwge1xuICAgICAgICBjb21tYW5kczogT2JqZWN0LmtleXMoZHluYW1pY1RoZW1lRml4ZXNDb21tYW5kcyksXG4gICAgICAgIGdldENvbW1hbmRQcm9wTmFtZTogKGNvbW1hbmQpID0+IGR5bmFtaWNUaGVtZUZpeGVzQ29tbWFuZHNbY29tbWFuZF0sXG4gICAgICAgIHBhcnNlQ29tbWFuZFZhbHVlOiAoY29tbWFuZCwgdmFsdWUpID0+IHtcbiAgICAgICAgICAgIGlmIChjb21tYW5kID09PSAnQ1NTJykge1xuICAgICAgICAgICAgICAgIHJldHVybiB2YWx1ZS50cmltKCk7XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICByZXR1cm4gcGFyc2VBcnJheSh2YWx1ZSk7XG4gICAgICAgIH0sXG4gICAgfSk7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBmb3JtYXREeW5hbWljVGhlbWVGaXhlcyhkeW5hbWljVGhlbWVGaXhlczogRHluYW1pY1RoZW1lRml4W10pOiBzdHJpbmcge1xuICAgIGNvbnN0IGZpeGVzID0gZHluYW1pY1RoZW1lRml4ZXMuc2xpY2UoKS5zb3J0KChhLCBiKSA9PiBjb21wYXJlVVJMUGF0dGVybnMoYS51cmxbMF0sIGIudXJsWzBdKSk7XG5cbiAgICByZXR1cm4gZm9ybWF0U2l0ZXNGaXhlc0NvbmZpZyhmaXhlcywge1xuICAgICAgICBwcm9wczogT2JqZWN0LnZhbHVlcyhkeW5hbWljVGhlbWVGaXhlc0NvbW1hbmRzKSxcbiAgICAgICAgZ2V0UHJvcENvbW1hbmROYW1lOiAocHJvcCkgPT4gT2JqZWN0LmVudHJpZXMoZHluYW1pY1RoZW1lRml4ZXNDb21tYW5kcykuZmluZCgoWywgcF0pID0+IHAgPT09IHByb3ApIVswXSxcbiAgICAgICAgZm9ybWF0UHJvcFZhbHVlOiAocHJvcCwgdmFsdWUpID0+IHtcbiAgICAgICAgICAgIGlmIChwcm9wID09PSAnY3NzJykge1xuICAgICAgICAgICAgICAgIHJldHVybiBmb3JtYXRDU1ModmFsdWUgYXMgc3RyaW5nKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIHJldHVybiBmb3JtYXRBcnJheSh2YWx1ZSBhcyBzdHJpbmdbXSkudHJpbSgpO1xuICAgICAgICB9LFxuICAgICAgICBzaG91bGRJZ25vcmVQcm9wOiAocHJvcCwgdmFsdWUpID0+IHtcbiAgICAgICAgICAgIGlmIChwcm9wID09PSAnY3NzJykge1xuICAgICAgICAgICAgICAgIHJldHVybiAhdmFsdWU7XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICByZXR1cm4gIShBcnJheS5pc0FycmF5KHZhbHVlKSAmJiB2YWx1ZS5sZW5ndGggPiAwKTtcbiAgICAgICAgfSxcbiAgICB9KTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGdldER5bmFtaWNUaGVtZUZpeGVzRm9yKHVybDogc3RyaW5nLCBpc1RvcEZyYW1lOiBib29sZWFuLCB0ZXh0OiBzdHJpbmcsIGluZGV4OiBTaXRlRml4ZXNJbmRleCwgZW5hYmxlZEZvclBERjogYm9vbGVhbik6IER5bmFtaWNUaGVtZUZpeFtdIHwgbnVsbCB7XG4gICAgY29uc3QgZml4ZXMgPSBnZXRTaXRlc0ZpeGVzRm9yKHVybCwgdGV4dCwgaW5kZXgsIHBhcnNlRHluYW1pY1RoZW1lRml4ZXMpO1xuXG4gICAgaWYgKGZpeGVzLmxlbmd0aCA9PT0gMCB8fCBmaXhlc1swXS51cmxbMF0gIT09ICcqJykge1xuICAgICAgICByZXR1cm4gbnVsbDtcbiAgICB9XG5cbiAgICBpZiAoZW5hYmxlZEZvclBERikge1xuICAgICAgICAvLyBDb3B5IHBhcnQgb2YgZml4ZXMgd2hpY2ggd2lsbCBiZSBtdXRhdGVkXG4gICAgICAgIGNvbnN0IGNvbW1vbkZpeCA9IHsuLi5maXhlc1swXX07XG4gICAgICAgIGNvbnN0IHBkZkZpeGVzOiBEeW5hbWljVGhlbWVGaXhbXSA9IFtcbiAgICAgICAgICAgIGNvbW1vbkZpeCxcbiAgICAgICAgICAgIC4uLmZpeGVzLnNsaWNlKDEpLFxuICAgICAgICBdO1xuXG4gICAgICAgIGNvbnN0IGludmVyc2lvbkZpeCA9IF9fQ0hST01JVU1fTVYyX18gfHwgX19DSFJPTUlVTV9NVjNfXyA/XG4gICAgICAgICAgICAnXFxuZW1iZWRbdHlwZT1cImFwcGxpY2F0aW9uL3BkZlwiXVtzcmM9XCJhYm91dDpibGFua1wiXSB7IGZpbHRlcjogaW52ZXJ0KDEwMCUpIGNvbnRyYXN0KDkwJSk7IH0nIDpcbiAgICAgICAgICAgICdcXG5lbWJlZFt0eXBlPVwiYXBwbGljYXRpb24vcGRmXCJdIHsgZmlsdGVyOiBpbnZlcnQoMTAwJSkgY29udHJhc3QoOTAlKTsgfSc7XG4gICAgICAgIGlmICghY29tbW9uRml4LmNzcy5lbmRzV2l0aChpbnZlcnNpb25GaXgpKSB7XG4gICAgICAgICAgICBjb21tb25GaXguY3NzICs9IGludmVyc2lvbkZpeDtcbiAgICAgICAgfVxuXG4gICAgICAgIGlmIChbJ2RyaXZlLmdvb2dsZS5jb20nLCAnbWFpbC5nb29nbGUuY29tJ10uaW5jbHVkZXMoZ2V0RG9tYWluKHVybCkpKSB7XG4gICAgICAgICAgICBjb25zdCBuZXN0ZWRJbnZlcnNpb25GaXggPSAnZGl2W3JvbGU9XCJkaWFsb2dcIl0gZGl2W3JvbGU9XCJkb2N1bWVudFwiXSc7XG4gICAgICAgICAgICBpZiAoY29tbW9uRml4LmludmVydC5hdCgtMSkgIT09IG5lc3RlZEludmVyc2lvbkZpeCkge1xuICAgICAgICAgICAgICAgIGNvbW1vbkZpeC5pbnZlcnQucHVzaChuZXN0ZWRJbnZlcnNpb25GaXgpO1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG5cbiAgICAgICAgcmV0dXJuIHBkZkZpeGVzO1xuICAgIH1cblxuICAgIHJldHVybiBmaXhlcztcbn1cbiIsImltcG9ydCB0eXBlIHtUaGVtZSwgU3RhdGljVGhlbWV9IGZyb20gJy4uL2RlZmluaXRpb25zJztcbmltcG9ydCB7cGFyc2VBcnJheSwgZm9ybWF0QXJyYXl9IGZyb20gJy4uL3V0aWxzL3RleHQnO1xuaW1wb3J0IHtjb21wYXJlVVJMUGF0dGVybnN9IGZyb20gJy4uL3V0aWxzL3VybCc7XG5cbmltcG9ydCB7Y3JlYXRlVGV4dFN0eWxlfSBmcm9tICcuL3RleHQtc3R5bGUnO1xuaW1wb3J0IHtmb3JtYXRTaXRlc0ZpeGVzQ29uZmlnfSBmcm9tICcuL3V0aWxzL2Zvcm1hdCc7XG5pbXBvcnQge2FwcGx5Q29sb3JNYXRyaXgsIGNyZWF0ZUZpbHRlck1hdHJpeH0gZnJvbSAnLi91dGlscy9tYXRyaXgnO1xuaW1wb3J0IHtwYXJzZVNpdGVzRml4ZXNDb25maWcsIGdldFNpdGVzRml4ZXNGb3J9IGZyb20gJy4vdXRpbHMvcGFyc2UnO1xuaW1wb3J0IHR5cGUge1NpdGVGaXhlc0luZGV4fSBmcm9tICcuL3V0aWxzL3BhcnNlJztcblxuaW50ZXJmYWNlIFRoZW1lQ29sb3JzIHtcbiAgICBbcHJvcDogc3RyaW5nXTogbnVtYmVyW107XG4gICAgbmV1dHJhbEJnOiBudW1iZXJbXTtcbiAgICBuZXV0cmFsVGV4dDogbnVtYmVyW107XG4gICAgcmVkQmc6IG51bWJlcltdO1xuICAgIHJlZFRleHQ6IG51bWJlcltdO1xuICAgIGdyZWVuQmc6IG51bWJlcltdO1xuICAgIGdyZWVuVGV4dDogbnVtYmVyW107XG4gICAgYmx1ZUJnOiBudW1iZXJbXTtcbiAgICBibHVlVGV4dDogbnVtYmVyW107XG4gICAgZmFkZUJnOiBudW1iZXJbXTtcbiAgICBmYWRlVGV4dDogbnVtYmVyW107XG59XG5cbmNvbnN0IGRhcmtUaGVtZTogVGhlbWVDb2xvcnMgPSB7XG4gICAgbmV1dHJhbEJnOiBbMTYsIDIwLCAyM10sXG4gICAgbmV1dHJhbFRleHQ6IFsxNjcsIDE1OCwgMTM5XSxcbiAgICByZWRCZzogWzY0LCAxMiwgMzJdLFxuICAgIHJlZFRleHQ6IFsyNDcsIDE0MiwgMTAyXSxcbiAgICBncmVlbkJnOiBbMzIsIDY0LCA0OF0sXG4gICAgZ3JlZW5UZXh0OiBbMTI4LCAyMDQsIDE0OF0sXG4gICAgYmx1ZUJnOiBbMzIsIDQ4LCA2NF0sXG4gICAgYmx1ZVRleHQ6IFsxMjgsIDE4MiwgMjA0XSxcbiAgICBmYWRlQmc6IFsxNiwgMjAsIDIzLCAwLjVdLFxuICAgIGZhZGVUZXh0OiBbMTY3LCAxNTgsIDEzOSwgMC41XSxcbn07XG5cbmNvbnN0IGxpZ2h0VGhlbWU6IFRoZW1lQ29sb3JzID0ge1xuICAgIG5ldXRyYWxCZzogWzI1NSwgMjQyLCAyMjhdLFxuICAgIG5ldXRyYWxUZXh0OiBbMCwgMCwgMF0sXG4gICAgcmVkQmc6IFsyNTUsIDg1LCAxNzBdLFxuICAgIHJlZFRleHQ6IFsxNDAsIDE0LCA0OF0sXG4gICAgZ3JlZW5CZzogWzE5MiwgMjU1LCAxNzBdLFxuICAgIGdyZWVuVGV4dDogWzAsIDEyOCwgMF0sXG4gICAgYmx1ZUJnOiBbMTczLCAyMTUsIDIyOV0sXG4gICAgYmx1ZVRleHQ6IFsyOCwgMTYsIDE3MV0sXG4gICAgZmFkZUJnOiBbMCwgMCwgMCwgMC41XSxcbiAgICBmYWRlVGV4dDogWzAsIDAsIDAsIDAuNV0sXG59O1xuXG5mdW5jdGlvbiByZ2IoW3IsIGcsIGIsIGFdOiBudW1iZXJbXSk6IHN0cmluZyB7XG4gICAgaWYgKHR5cGVvZiBhID09PSAnbnVtYmVyJykge1xuICAgICAgICByZXR1cm4gYHJnYmEoJHtyfSwgJHtnfSwgJHtifSwgJHthfSlgO1xuICAgIH1cbiAgICByZXR1cm4gYHJnYigke3J9LCAke2d9LCAke2J9KWA7XG59XG5cbmZ1bmN0aW9uIG1peChjb2xvcjE6IG51bWJlcltdLCBjb2xvcjI6IG51bWJlcltdLCB0OiBudW1iZXIpOiBudW1iZXJbXSB7XG4gICAgcmV0dXJuIGNvbG9yMS5tYXAoKGMsIGkpID0+IE1hdGgucm91bmQoYyAqICgxIC0gdCkgKyBjb2xvcjJbaV0gKiB0KSk7XG59XG5cbmV4cG9ydCBkZWZhdWx0IGZ1bmN0aW9uIGNyZWF0ZVN0YXRpY1N0eWxlc2hlZXQoY29uZmlnOiBUaGVtZSwgdXJsOiBzdHJpbmcsIGlzVG9wRnJhbWU6IGJvb2xlYW4sIHN0YXRpY1RoZW1lczogc3RyaW5nLCBzdGF0aWNUaGVtZXNJbmRleDogU2l0ZUZpeGVzSW5kZXgpOiBzdHJpbmcge1xuICAgIGNvbnN0IHNyY1RoZW1lID0gY29uZmlnLm1vZGUgPT09IDEgPyBkYXJrVGhlbWUgOiBsaWdodFRoZW1lO1xuICAgIGNvbnN0IHRoZW1lID0gT2JqZWN0LmVudHJpZXMoc3JjVGhlbWUpLnJlZHVjZSgodCwgW3Byb3AsIGNvbG9yXSkgPT4ge1xuICAgICAgICBjb25zdCBbciwgZywgYiwgYV0gPSBjb2xvcjtcbiAgICAgICAgdFtwcm9wXSA9IGFwcGx5Q29sb3JNYXRyaXgoW3IsIGcsIGJdLCBjcmVhdGVGaWx0ZXJNYXRyaXgoey4uLmNvbmZpZywgbW9kZTogMH0pKTtcbiAgICAgICAgaWYgKGEgIT09IHVuZGVmaW5lZCkge1xuICAgICAgICAgICAgdFtwcm9wXS5wdXNoKGEpO1xuICAgICAgICB9XG4gICAgICAgIHJldHVybiB0O1xuICAgIH0sIHt9IGFzIFRoZW1lQ29sb3JzKTtcblxuICAgIGNvbnN0IHRoZW1lcyA9IGdldFNpdGVzRml4ZXNGb3IodXJsLCBzdGF0aWNUaGVtZXMsIHN0YXRpY1RoZW1lc0luZGV4LCBwYXJzZVN0YXRpY1RoZW1lcyk7XG5cbiAgICBjb25zdCBjb21tb25UaGVtZSA9IHRoZW1lcy5maW5kKCh0KSA9PiB0LnVybFswXSA9PT0gJyonKTtcbiAgICBjb25zdCBzaXRlVGhlbWUgPSB0aGVtZXMuZmluZCgodCkgPT4gdC51cmxbMF0gIT09ICcqJyk7XG5cbiAgICBpZiAoIWNvbW1vblRoZW1lKSB7XG4gICAgICAgIHJldHVybiAnJztcbiAgICB9XG5cbiAgICBjb25zdCBsaW5lczogc3RyaW5nW10gPSBbXTtcblxuICAgIGlmICghc2l0ZVRoZW1lIHx8ICFzaXRlVGhlbWUubm9Db21tb24pIHtcbiAgICAgICAgbGluZXMucHVzaCgnLyogQ29tbW9uIHRoZW1lICovJyk7XG4gICAgICAgIGxpbmVzLnB1c2goLi4ucnVsZUdlbmVyYXRvcnMubWFwKChnZW4pID0+IGdlbihjb21tb25UaGVtZSwgdGhlbWUpISkpO1xuICAgIH1cblxuICAgIGlmIChzaXRlVGhlbWUpIHtcbiAgICAgICAgbGluZXMucHVzaChgLyogVGhlbWUgZm9yICR7c2l0ZVRoZW1lLnVybC5qb2luKCcgJyl9ICovYCk7XG4gICAgICAgIGxpbmVzLnB1c2goLi4ucnVsZUdlbmVyYXRvcnMubWFwKChnZW4pID0+IGdlbihzaXRlVGhlbWUsIHRoZW1lKSEpKTtcbiAgICB9XG5cbiAgICBpZiAoY29uZmlnLnVzZUZvbnQgfHwgY29uZmlnLnRleHRTdHJva2UgPiAwKSB7XG4gICAgICAgIGxpbmVzLnB1c2goJy8qIEZvbnQgKi8nKTtcbiAgICAgICAgbGluZXMucHVzaChjcmVhdGVUZXh0U3R5bGUoY29uZmlnKSk7XG4gICAgfVxuXG4gICAgcmV0dXJuIGxpbmVzXG4gICAgICAgIC5maWx0ZXIoKGxuKSA9PiBsbilcbiAgICAgICAgLmpvaW4oJ1xcbicpO1xufVxuXG5mdW5jdGlvbiBjcmVhdGVSdWxlR2VuKGdldFNlbGVjdG9yczogKHNpdGVUaGVtZTogU3RhdGljVGhlbWUpID0+IHN0cmluZ1tdIHwgdW5kZWZpbmVkLCBnZW5lcmF0ZURlY2xhcmF0aW9uczogKHRoZW1lOiBUaGVtZUNvbG9ycykgPT4gc3RyaW5nW10sIG1vZGlmeVNlbGVjdG9yOiAoKHM6IHN0cmluZykgPT4gc3RyaW5nKSA9IChzKSA9PiBzKSB7XG4gICAgcmV0dXJuIChzaXRlVGhlbWU6IFN0YXRpY1RoZW1lLCB0aGVtZUNvbG9yczogVGhlbWVDb2xvcnMpID0+IHtcbiAgICAgICAgY29uc3Qgc2VsZWN0b3JzID0gZ2V0U2VsZWN0b3JzKHNpdGVUaGVtZSk7XG4gICAgICAgIGlmIChzZWxlY3RvcnMgPT0gbnVsbCB8fCBzZWxlY3RvcnMubGVuZ3RoID09PSAwKSB7XG4gICAgICAgICAgICByZXR1cm4gbnVsbDtcbiAgICAgICAgfVxuICAgICAgICBjb25zdCBsaW5lczogc3RyaW5nW10gPSBbXTtcbiAgICAgICAgc2VsZWN0b3JzLmZvckVhY2goKHMsIGkpID0+IHtcbiAgICAgICAgICAgIGxldCBsbiA9IG1vZGlmeVNlbGVjdG9yKHMpO1xuICAgICAgICAgICAgaWYgKGkgPCBzZWxlY3RvcnMubGVuZ3RoIC0gMSkge1xuICAgICAgICAgICAgICAgIGxuICs9ICcsJztcbiAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgbG4gKz0gJyB7JztcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGxpbmVzLnB1c2gobG4pO1xuICAgICAgICB9KTtcbiAgICAgICAgY29uc3QgZGVjbGFyYXRpb25zID0gZ2VuZXJhdGVEZWNsYXJhdGlvbnModGhlbWVDb2xvcnMpO1xuICAgICAgICBkZWNsYXJhdGlvbnMuZm9yRWFjaCgoZCkgPT4gbGluZXMucHVzaChgICAgICR7ZH0gIWltcG9ydGFudDtgKSk7XG4gICAgICAgIGxpbmVzLnB1c2goJ30nKTtcbiAgICAgICAgcmV0dXJuIGxpbmVzLmpvaW4oJ1xcbicpO1xuICAgIH07XG59XG5cbmNvbnN0IG14ID0ge1xuICAgIGJnOiB7XG4gICAgICAgIGhvdmVyOiAwLjA3NSxcbiAgICAgICAgYWN0aXZlOiAwLjEsXG4gICAgfSxcbiAgICBmZzoge1xuICAgICAgICBob3ZlcjogMC4yNSxcbiAgICAgICAgYWN0aXZlOiAwLjUsXG4gICAgfSxcbiAgICBib3JkZXI6IDAuNSxcbn07XG5cbmNvbnN0IHJ1bGVHZW5lcmF0b3JzID0gW1xuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQubmV1dHJhbEJnLCAodCkgPT4gW2BiYWNrZ3JvdW5kLWNvbG9yOiAke3JnYih0Lm5ldXRyYWxCZyl9YF0pLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQubmV1dHJhbEJnQWN0aXZlLCAodCkgPT4gW2BiYWNrZ3JvdW5kLWNvbG9yOiAke3JnYih0Lm5ldXRyYWxCZyl9YF0pLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQubmV1dHJhbEJnQWN0aXZlLCAodCkgPT4gW2BiYWNrZ3JvdW5kLWNvbG9yOiAke3JnYihtaXgodC5uZXV0cmFsQmcsIFsyNTUsIDI1NSwgMjU1XSwgbXguYmcuaG92ZXIpKX1gXSwgKHMpID0+IGAke3N9OmhvdmVyYCksXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC5uZXV0cmFsQmdBY3RpdmUsICh0KSA9PiBbYGJhY2tncm91bmQtY29sb3I6ICR7cmdiKG1peCh0Lm5ldXRyYWxCZywgWzI1NSwgMjU1LCAyNTVdLCBteC5iZy5hY3RpdmUpKX1gXSwgKHMpID0+IGAke3N9OmFjdGl2ZSwgJHtzfTpmb2N1c2ApLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQubmV1dHJhbFRleHQsICh0KSA9PiBbYGNvbG9yOiAke3JnYih0Lm5ldXRyYWxUZXh0KX1gXSksXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC5uZXV0cmFsVGV4dEFjdGl2ZSwgKHQpID0+IFtgY29sb3I6ICR7cmdiKHQubmV1dHJhbFRleHQpfWBdKSxcbiAgICBjcmVhdGVSdWxlR2VuKCh0KSA9PiB0Lm5ldXRyYWxUZXh0QWN0aXZlLCAodCkgPT4gW2Bjb2xvcjogJHtyZ2IobWl4KHQubmV1dHJhbFRleHQsIFsyNTUsIDI1NSwgMjU1XSwgbXguZmcuaG92ZXIpKX1gXSwgKHMpID0+IGAke3N9OmhvdmVyYCksXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC5uZXV0cmFsVGV4dEFjdGl2ZSwgKHQpID0+IFtgY29sb3I6ICR7cmdiKG1peCh0Lm5ldXRyYWxUZXh0LCBbMjU1LCAyNTUsIDI1NV0sIG14LmZnLmFjdGl2ZSkpfWBdLCAocykgPT4gYCR7c306YWN0aXZlLCAke3N9OmZvY3VzYCksXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC5uZXV0cmFsQm9yZGVyLCAodCkgPT4gW2Bib3JkZXItY29sb3I6ICR7cmdiKG1peCh0Lm5ldXRyYWxCZywgdC5uZXV0cmFsVGV4dCwgbXguYm9yZGVyKSl9YF0pLFxuXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC5yZWRCZywgKHQpID0+IFtgYmFja2dyb3VuZC1jb2xvcjogJHtyZ2IodC5yZWRCZyl9YF0pLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQucmVkQmdBY3RpdmUsICh0KSA9PiBbYGJhY2tncm91bmQtY29sb3I6ICR7cmdiKHQucmVkQmcpfWBdKSxcbiAgICBjcmVhdGVSdWxlR2VuKCh0KSA9PiB0LnJlZEJnQWN0aXZlLCAodCkgPT4gW2BiYWNrZ3JvdW5kLWNvbG9yOiAke3JnYihtaXgodC5yZWRCZywgWzI1NSwgMCwgNjRdLCBteC5iZy5ob3ZlcikpfWBdLCAocykgPT4gYCR7c306aG92ZXJgKSxcbiAgICBjcmVhdGVSdWxlR2VuKCh0KSA9PiB0LnJlZEJnQWN0aXZlLCAodCkgPT4gW2BiYWNrZ3JvdW5kLWNvbG9yOiAke3JnYihtaXgodC5yZWRCZywgWzI1NSwgMCwgNjRdLCBteC5iZy5hY3RpdmUpKX1gXSwgKHMpID0+IGAke3N9OmFjdGl2ZSwgJHtzfTpmb2N1c2ApLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQucmVkVGV4dCwgKHQpID0+IFtgY29sb3I6ICR7cmdiKHQucmVkVGV4dCl9YF0pLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQucmVkVGV4dEFjdGl2ZSwgKHQpID0+IFtgY29sb3I6ICR7cmdiKHQucmVkVGV4dCl9YF0pLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQucmVkVGV4dEFjdGl2ZSwgKHQpID0+IFtgY29sb3I6ICR7cmdiKG1peCh0LnJlZFRleHQsIFsyNTUsIDI1NSwgMF0sIG14LmZnLmhvdmVyKSl9YF0sIChzKSA9PiBgJHtzfTpob3ZlcmApLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQucmVkVGV4dEFjdGl2ZSwgKHQpID0+IFtgY29sb3I6ICR7cmdiKG1peCh0LnJlZFRleHQsIFsyNTUsIDI1NSwgMF0sIG14LmZnLmFjdGl2ZSkpfWBdLCAocykgPT4gYCR7c306YWN0aXZlLCAke3N9OmZvY3VzYCksXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC5yZWRCb3JkZXIsICh0KSA9PiBbYGJvcmRlci1jb2xvcjogJHtyZ2IobWl4KHQucmVkQmcsIHQucmVkVGV4dCwgbXguYm9yZGVyKSl9YF0pLFxuXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC5ncmVlbkJnLCAodCkgPT4gW2BiYWNrZ3JvdW5kLWNvbG9yOiAke3JnYih0LmdyZWVuQmcpfWBdKSxcbiAgICBjcmVhdGVSdWxlR2VuKCh0KSA9PiB0LmdyZWVuQmdBY3RpdmUsICh0KSA9PiBbYGJhY2tncm91bmQtY29sb3I6ICR7cmdiKHQuZ3JlZW5CZyl9YF0pLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQuZ3JlZW5CZ0FjdGl2ZSwgKHQpID0+IFtgYmFja2dyb3VuZC1jb2xvcjogJHtyZ2IobWl4KHQuZ3JlZW5CZywgWzEyOCwgMjU1LCAxODJdLCBteC5iZy5ob3ZlcikpfWBdLCAocykgPT4gYCR7c306aG92ZXJgKSxcbiAgICBjcmVhdGVSdWxlR2VuKCh0KSA9PiB0LmdyZWVuQmdBY3RpdmUsICh0KSA9PiBbYGJhY2tncm91bmQtY29sb3I6ICR7cmdiKG1peCh0LmdyZWVuQmcsIFsxMjgsIDI1NSwgMTgyXSwgbXguYmcuYWN0aXZlKSl9YF0sIChzKSA9PiBgJHtzfTphY3RpdmUsICR7c306Zm9jdXNgKSxcbiAgICBjcmVhdGVSdWxlR2VuKCh0KSA9PiB0LmdyZWVuVGV4dCwgKHQpID0+IFtgY29sb3I6ICR7cmdiKHQuZ3JlZW5UZXh0KX1gXSksXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC5ncmVlblRleHRBY3RpdmUsICh0KSA9PiBbYGNvbG9yOiAke3JnYih0LmdyZWVuVGV4dCl9YF0pLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQuZ3JlZW5UZXh0QWN0aXZlLCAodCkgPT4gW2Bjb2xvcjogJHtyZ2IobWl4KHQuZ3JlZW5UZXh0LCBbMTgyLCAyNTUsIDIyNF0sIG14LmZnLmhvdmVyKSl9YF0sIChzKSA9PiBgJHtzfTpob3ZlcmApLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQuZ3JlZW5UZXh0QWN0aXZlLCAodCkgPT4gW2Bjb2xvcjogJHtyZ2IobWl4KHQuZ3JlZW5UZXh0LCBbMTgyLCAyNTUsIDIyNF0sIG14LmZnLmFjdGl2ZSkpfWBdLCAocykgPT4gYCR7c306YWN0aXZlLCAke3N9OmZvY3VzYCksXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC5ncmVlbkJvcmRlciwgKHQpID0+IFtgYm9yZGVyLWNvbG9yOiAke3JnYihtaXgodC5ncmVlbkJnLCB0LmdyZWVuVGV4dCwgbXguYm9yZGVyKSl9YF0pLFxuXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC5ibHVlQmcsICh0KSA9PiBbYGJhY2tncm91bmQtY29sb3I6ICR7cmdiKHQuYmx1ZUJnKX1gXSksXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC5ibHVlQmdBY3RpdmUsICh0KSA9PiBbYGJhY2tncm91bmQtY29sb3I6ICR7cmdiKHQuYmx1ZUJnKX1gXSksXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC5ibHVlQmdBY3RpdmUsICh0KSA9PiBbYGJhY2tncm91bmQtY29sb3I6ICR7cmdiKG1peCh0LmJsdWVCZywgWzAsIDEyOCwgMjU1XSwgbXguYmcuaG92ZXIpKX1gXSwgKHMpID0+IGAke3N9OmhvdmVyYCksXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC5ibHVlQmdBY3RpdmUsICh0KSA9PiBbYGJhY2tncm91bmQtY29sb3I6ICR7cmdiKG1peCh0LmJsdWVCZywgWzAsIDEyOCwgMjU1XSwgbXguYmcuYWN0aXZlKSl9YF0sIChzKSA9PiBgJHtzfTphY3RpdmUsICR7c306Zm9jdXNgKSxcbiAgICBjcmVhdGVSdWxlR2VuKCh0KSA9PiB0LmJsdWVUZXh0LCAodCkgPT4gW2Bjb2xvcjogJHtyZ2IodC5ibHVlVGV4dCl9YF0pLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQuYmx1ZVRleHRBY3RpdmUsICh0KSA9PiBbYGNvbG9yOiAke3JnYih0LmJsdWVUZXh0KX1gXSksXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC5ibHVlVGV4dEFjdGl2ZSwgKHQpID0+IFtgY29sb3I6ICR7cmdiKG1peCh0LmJsdWVUZXh0LCBbMTgyLCAyMjQsIDI1NV0sIG14LmZnLmhvdmVyKSl9YF0sIChzKSA9PiBgJHtzfTpob3ZlcmApLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQuYmx1ZVRleHRBY3RpdmUsICh0KSA9PiBbYGNvbG9yOiAke3JnYihtaXgodC5ibHVlVGV4dCwgWzE4MiwgMjI0LCAyNTVdLCBteC5mZy5hY3RpdmUpKX1gXSwgKHMpID0+IGAke3N9OmFjdGl2ZSwgJHtzfTpmb2N1c2ApLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQuYmx1ZUJvcmRlciwgKHQpID0+IFtgYm9yZGVyLWNvbG9yOiAke3JnYihtaXgodC5ibHVlQmcsIHQuYmx1ZVRleHQsIG14LmJvcmRlcikpfWBdKSxcblxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQuZmFkZUJnLCAodCkgPT4gW2BiYWNrZ3JvdW5kLWNvbG9yOiAke3JnYih0LmZhZGVCZyl9YF0pLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQuZmFkZVRleHQsICh0KSA9PiBbYGNvbG9yOiAke3JnYih0LmZhZGVUZXh0KX1gXSksXG4gICAgY3JlYXRlUnVsZUdlbigodCkgPT4gdC50cmFuc3BhcmVudEJnLCAoKSA9PiBbJ2JhY2tncm91bmQtY29sb3I6IHRyYW5zcGFyZW50J10pLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQubm9JbWFnZSwgKCkgPT4gWydiYWNrZ3JvdW5kLWltYWdlOiBub25lJ10pLFxuICAgIGNyZWF0ZVJ1bGVHZW4oKHQpID0+IHQuaW52ZXJ0LCAoKSA9PiBbJ2ZpbHRlcjogaW52ZXJ0KDEwMCUpIGh1ZS1yb3RhdGUoMTgwZGVnKSddKSxcbl07XG5cbmNvbnN0IHN0YXRpY1RoZW1lQ29tbWFuZHM6IHsgW2tleTogc3RyaW5nXToga2V5b2YgU3RhdGljVGhlbWUgfSA9IHtcbiAgICAnTk8gQ09NTU9OJzogJ25vQ29tbW9uJyxcblxuICAgICdORVVUUkFMIEJHJzogJ25ldXRyYWxCZycsXG4gICAgJ05FVVRSQUwgQkcgQUNUSVZFJzogJ25ldXRyYWxCZ0FjdGl2ZScsXG4gICAgJ05FVVRSQUwgVEVYVCc6ICduZXV0cmFsVGV4dCcsXG4gICAgJ05FVVRSQUwgVEVYVCBBQ1RJVkUnOiAnbmV1dHJhbFRleHRBY3RpdmUnLFxuICAgICdORVVUUkFMIEJPUkRFUic6ICduZXV0cmFsQm9yZGVyJyxcblxuICAgICdSRUQgQkcnOiAncmVkQmcnLFxuICAgICdSRUQgQkcgQUNUSVZFJzogJ3JlZEJnQWN0aXZlJyxcbiAgICAnUkVEIFRFWFQnOiAncmVkVGV4dCcsXG4gICAgJ1JFRCBURVhUIEFDVElWRSc6ICdyZWRUZXh0QWN0aXZlJyxcbiAgICAnUkVEIEJPUkRFUic6ICdyZWRCb3JkZXInLFxuXG4gICAgJ0dSRUVOIEJHJzogJ2dyZWVuQmcnLFxuICAgICdHUkVFTiBCRyBBQ1RJVkUnOiAnZ3JlZW5CZ0FjdGl2ZScsXG4gICAgJ0dSRUVOIFRFWFQnOiAnZ3JlZW5UZXh0JyxcbiAgICAnR1JFRU4gVEVYVCBBQ1RJVkUnOiAnZ3JlZW5UZXh0QWN0aXZlJyxcbiAgICAnR1JFRU4gQk9SREVSJzogJ2dyZWVuQm9yZGVyJyxcblxuICAgICdCTFVFIEJHJzogJ2JsdWVCZycsXG4gICAgJ0JMVUUgQkcgQUNUSVZFJzogJ2JsdWVCZ0FjdGl2ZScsXG4gICAgJ0JMVUUgVEVYVCc6ICdibHVlVGV4dCcsXG4gICAgJ0JMVUUgVEVYVCBBQ1RJVkUnOiAnYmx1ZVRleHRBY3RpdmUnLFxuICAgICdCTFVFIEJPUkRFUic6ICdibHVlQm9yZGVyJyxcblxuICAgICdGQURFIEJHJzogJ2ZhZGVCZycsXG4gICAgJ0ZBREUgVEVYVCc6ICdmYWRlVGV4dCcsXG4gICAgJ1RSQU5TUEFSRU5UIEJHJzogJ3RyYW5zcGFyZW50QmcnLFxuXG4gICAgJ05PIElNQUdFJzogJ25vSW1hZ2UnLFxuICAgICdJTlZFUlQnOiAnaW52ZXJ0Jyxcbn07XG5cbmV4cG9ydCBmdW5jdGlvbiBwYXJzZVN0YXRpY1RoZW1lcygkdGhlbWVzOiBzdHJpbmcpOiBTdGF0aWNUaGVtZVtdIHtcbiAgICByZXR1cm4gcGFyc2VTaXRlc0ZpeGVzQ29uZmlnPFN0YXRpY1RoZW1lPigkdGhlbWVzLCB7XG4gICAgICAgIGNvbW1hbmRzOiBPYmplY3Qua2V5cyhzdGF0aWNUaGVtZUNvbW1hbmRzKSxcbiAgICAgICAgZ2V0Q29tbWFuZFByb3BOYW1lOiAoY29tbWFuZCkgPT4gc3RhdGljVGhlbWVDb21tYW5kc1tjb21tYW5kXSxcbiAgICAgICAgcGFyc2VDb21tYW5kVmFsdWU6IChjb21tYW5kLCB2YWx1ZSkgPT4ge1xuICAgICAgICAgICAgaWYgKGNvbW1hbmQgPT09ICdOTyBDT01NT04nKSB7XG4gICAgICAgICAgICAgICAgcmV0dXJuIHRydWU7XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICByZXR1cm4gcGFyc2VBcnJheSh2YWx1ZSk7XG4gICAgICAgIH0sXG4gICAgfSk7XG59XG5cbmZ1bmN0aW9uIGNhbWVsQ2FzZVRvVXBwZXJDYXNlKHRleHQ6IHN0cmluZyk6IHN0cmluZyB7XG4gICAgcmV0dXJuIHRleHQucmVwbGFjZSgvKFthLXpdKShbQS1aXSkvZywgJyQxICQyJykudG9VcHBlckNhc2UoKTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGZvcm1hdFN0YXRpY1RoZW1lcyhzdGF0aWNUaGVtZXM6IFN0YXRpY1RoZW1lW10pOiBzdHJpbmcge1xuICAgIGNvbnN0IHRoZW1lcyA9IHN0YXRpY1RoZW1lcy5zbGljZSgpLnNvcnQoKGEsIGIpID0+IGNvbXBhcmVVUkxQYXR0ZXJucyhhLnVybFswXSwgYi51cmxbMF0pKTtcblxuICAgIHJldHVybiBmb3JtYXRTaXRlc0ZpeGVzQ29uZmlnKHRoZW1lcywge1xuICAgICAgICBwcm9wczogT2JqZWN0LnZhbHVlcyhzdGF0aWNUaGVtZUNvbW1hbmRzKSxcbiAgICAgICAgZ2V0UHJvcENvbW1hbmROYW1lOiBjYW1lbENhc2VUb1VwcGVyQ2FzZSxcbiAgICAgICAgZm9ybWF0UHJvcFZhbHVlOiAocHJvcCwgdmFsdWUpID0+IHtcbiAgICAgICAgICAgIGlmIChwcm9wID09PSAnbm9Db21tb24nKSB7XG4gICAgICAgICAgICAgICAgcmV0dXJuICcnO1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgcmV0dXJuIGZvcm1hdEFycmF5KHZhbHVlIGFzIHN0cmluZ1tdKS50cmltKCk7XG4gICAgICAgIH0sXG4gICAgICAgIHNob3VsZElnbm9yZVByb3A6IChwcm9wLCB2YWx1ZSkgPT4ge1xuICAgICAgICAgICAgaWYgKHByb3AgPT09ICdub0NvbW1vbicpIHtcbiAgICAgICAgICAgICAgICByZXR1cm4gIXZhbHVlO1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgcmV0dXJuICEoQXJyYXkuaXNBcnJheSh2YWx1ZSkgJiYgdmFsdWUubGVuZ3RoID4gMCk7XG4gICAgICAgIH0sXG4gICAgfSk7XG59XG4iLCJpbXBvcnQgdHlwZSB7VGhlbWV9IGZyb20gJy4uL2RlZmluaXRpb25zJztcbmltcG9ydCB7aXNGaXJlZm94fSBmcm9tICcuLi91dGlscy9wbGF0Zm9ybSc7XG5cbmltcG9ydCB7Y3NzRmlsdGVyU3R5bGVTaGVldFRlbXBsYXRlfSBmcm9tICcuL2Nzcy1maWx0ZXInO1xuaW1wb3J0IHtjcmVhdGVGaWx0ZXJNYXRyaXgsIE1hdHJpeH0gZnJvbSAnLi91dGlscy9tYXRyaXgnO1xuaW1wb3J0IHR5cGUge1NpdGVGaXhlc0luZGV4fSBmcm9tICcuL3V0aWxzL3BhcnNlJztcblxuZXhwb3J0IGZ1bmN0aW9uIGNyZWF0ZVNWR0ZpbHRlclN0eWxlc2hlZXQoY29uZmlnOiBUaGVtZSwgdXJsOiBzdHJpbmcsIGlzVG9wRnJhbWU6IGJvb2xlYW4sIGZpeGVzOiBzdHJpbmcsIGluZGV4OiBTaXRlRml4ZXNJbmRleCk6IHN0cmluZyB7XG4gICAgbGV0IGZpbHRlclZhbHVlOiBzdHJpbmc7XG4gICAgbGV0IHJldmVyc2VGaWx0ZXJWYWx1ZTogc3RyaW5nO1xuICAgIGlmIChpc0ZpcmVmb3gpIHtcbiAgICAgICAgZmlsdGVyVmFsdWUgPSBnZXRFbWJlZGRlZFNWR0ZpbHRlclZhbHVlKGdldFNWR0ZpbHRlck1hdHJpeFZhbHVlKGNvbmZpZykpO1xuICAgICAgICByZXZlcnNlRmlsdGVyVmFsdWUgPSBnZXRFbWJlZGRlZFNWR0ZpbHRlclZhbHVlKGdldFNWR1JldmVyc2VGaWx0ZXJNYXRyaXhWYWx1ZSgpKTtcbiAgICB9IGVsc2Uge1xuICAgICAgICAvLyBDaHJvbWUgZmFpbHMgd2l0aCBcIlVuc2FmZSBhdHRlbXB0IHRvIGxvYWQgVVJMIC4uLiBEb21haW5zLCBwcm90b2NvbHMgYW5kIHBvcnRzIG11c3QgbWF0Y2guXG4gICAgICAgIGZpbHRlclZhbHVlID0gJ3VybCgjZGFyay1yZWFkZXItZmlsdGVyKSc7XG4gICAgICAgIHJldmVyc2VGaWx0ZXJWYWx1ZSA9ICd1cmwoI2RhcmstcmVhZGVyLXJldmVyc2UtZmlsdGVyKSc7XG4gICAgfVxuICAgIGNvbnN0IGZpbHRlclJvb3QgPSBpc0ZpcmVmb3ggPyAnYm9keScgOiAnaHRtbCc7XG4gICAgcmV0dXJuIGNzc0ZpbHRlclN0eWxlU2hlZXRUZW1wbGF0ZShmaWx0ZXJSb290LCBmaWx0ZXJWYWx1ZSwgcmV2ZXJzZUZpbHRlclZhbHVlLCBjb25maWcsIHVybCwgaXNUb3BGcmFtZSwgZml4ZXMsIGluZGV4KTtcbn1cblxuZnVuY3Rpb24gZ2V0RW1iZWRkZWRTVkdGaWx0ZXJWYWx1ZShtYXRyaXhWYWx1ZTogc3RyaW5nKTogc3RyaW5nIHtcbiAgICBjb25zdCBpZCA9ICdkYXJrLXJlYWRlci1maWx0ZXInO1xuICAgIGNvbnN0IHN2ZyA9IFtcbiAgICAgICAgJzxzdmcgeG1sbnM9XCJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Z1wiPicsXG4gICAgICAgIGA8ZmlsdGVyIGlkPVwiJHtpZH1cIiBzdHlsZT1cImNvbG9yLWludGVycG9sYXRpb24tZmlsdGVyczogc1JHQjtcIj5gLFxuICAgICAgICBgPGZlQ29sb3JNYXRyaXggdHlwZT1cIm1hdHJpeFwiIHZhbHVlcz1cIiR7bWF0cml4VmFsdWV9XCIgLz5gLFxuICAgICAgICAnPC9maWx0ZXI+JyxcbiAgICAgICAgJzwvc3ZnPicsXG4gICAgXS5qb2luKCcnKTtcbiAgICByZXR1cm4gYHVybChkYXRhOmltYWdlL3N2Zyt4bWw7YmFzZTY0LCR7YnRvYShzdmcpfSMke2lkfSlgO1xufVxuXG5mdW5jdGlvbiB0b1NWR01hdHJpeChtYXRyaXg6IG51bWJlcltdW10pOiBzdHJpbmcge1xuICAgIHJldHVybiBtYXRyaXguc2xpY2UoMCwgNCkubWFwKChtKSA9PiBtLm1hcCgobSkgPT4gbS50b0ZpeGVkKDMpKS5qb2luKCcgJykpLmpvaW4oJyAnKTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGdldFNWR0ZpbHRlck1hdHJpeFZhbHVlKGNvbmZpZzogVGhlbWUpOiBzdHJpbmcge1xuICAgIHJldHVybiB0b1NWR01hdHJpeChjcmVhdGVGaWx0ZXJNYXRyaXgoY29uZmlnKSk7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBnZXRTVkdSZXZlcnNlRmlsdGVyTWF0cml4VmFsdWUoKTogc3RyaW5nIHtcbiAgICByZXR1cm4gdG9TVkdNYXRyaXgoTWF0cml4LmludmVydE5IdWUoKSk7XG59XG4iLCJleHBvcnQgZW51bSBUaGVtZUVuZ2luZSB7XG4gICAgY3NzRmlsdGVyID0gJ2Nzc0ZpbHRlcicsXG4gICAgc3ZnRmlsdGVyID0gJ3N2Z0ZpbHRlcicsXG4gICAgc3RhdGljVGhlbWUgPSAnc3RhdGljVGhlbWUnLFxuICAgIGR5bmFtaWNUaGVtZSA9ICdkeW5hbWljVGhlbWUnXG59XG4iLCJleHBvcnQgZW51bSBBdXRvbWF0aW9uTW9kZSB7XG4gICAgTk9ORSA9ICcnLFxuICAgIFRJTUUgPSAndGltZScsXG4gICAgU1lTVEVNID0gJ3N5c3RlbScsXG4gICAgTE9DQVRJT04gPSAnbG9jYXRpb24nXG59XG4iLCJ0eXBlIEFueUZuID0gKC4uLmFyZ3M6IGFueVtdKSA9PiB2b2lkO1xuXG5leHBvcnQgZnVuY3Rpb24gZGVib3VuY2U8RiBleHRlbmRzIEFueUZuPihkZWxheTogbnVtYmVyLCBmbjogRik6IEYge1xuICAgIGxldCB0aW1lb3V0SWQ6IFJldHVyblR5cGU8dHlwZW9mIHNldFRpbWVvdXQ+IHwgbnVsbCA9IG51bGw7XG4gICAgcmV0dXJuICgoLi4uYXJnczogYW55W10pID0+IHtcbiAgICAgICAgaWYgKHRpbWVvdXRJZCkge1xuICAgICAgICAgICAgY2xlYXJUaW1lb3V0KHRpbWVvdXRJZCk7XG4gICAgICAgIH1cbiAgICAgICAgdGltZW91dElkID0gc2V0VGltZW91dCgoKSA9PiB7XG4gICAgICAgICAgICB0aW1lb3V0SWQgPSBudWxsO1xuICAgICAgICAgICAgZm4oLi4uYXJncyk7XG4gICAgICAgIH0sIGRlbGF5KTtcbiAgICB9KSBhcyBGO1xufVxuIiwiZXhwb3J0IGNsYXNzIFByb21pc2VCYXJyaWVyPFJFU09MVlVUSU9OLCBSRUpFQ1RJT04+IHtcbiAgICBwcml2YXRlIHJlc29sdmVzOiBBcnJheTwodmFsdWU6IFJFU09MVlVUSU9OKSA9PiB2b2lkPiA9IFtdO1xuICAgIHByaXZhdGUgcmVqZWN0czogQXJyYXk8KHJlYXNvbjogUkVKRUNUSU9OKSA9PiB2b2lkPiA9IFtdO1xuICAgIHByaXZhdGUgd2FzUmVzb2x2ZWQgPSBmYWxzZTtcbiAgICBwcml2YXRlIHdhc1JlamVjdGVkID0gZmFsc2U7XG4gICAgcHJpdmF0ZSByZXNvbHV0aW9uOiBSRVNPTFZVVElPTjtcbiAgICBwcml2YXRlIHJlYXNvbjogUkVKRUNUSU9OO1xuXG4gICAgYXN5bmMgZW50cnkoKTogUHJvbWlzZTxSRVNPTFZVVElPTj57XG4gICAgICAgIGlmICh0aGlzLndhc1Jlc29sdmVkKSB7XG4gICAgICAgICAgICByZXR1cm4gUHJvbWlzZS5yZXNvbHZlKHRoaXMucmVzb2x1dGlvbik7XG4gICAgICAgIH1cbiAgICAgICAgaWYgKHRoaXMud2FzUmVqZWN0ZWQpIHtcbiAgICAgICAgICAgIHJldHVybiBQcm9taXNlLnJlamVjdCh0aGlzLnJlYXNvbik7XG4gICAgICAgIH1cbiAgICAgICAgcmV0dXJuIG5ldyBQcm9taXNlKChyZXNvbHZlLCByZWplY3QpID0+IHtcbiAgICAgICAgICAgIHRoaXMucmVzb2x2ZXMucHVzaChyZXNvbHZlKTtcbiAgICAgICAgICAgIHRoaXMucmVqZWN0cy5wdXNoKHJlamVjdCk7XG4gICAgICAgIH0pO1xuICAgIH1cblxuICAgIGFzeW5jIHJlc29sdmUodmFsdWU6IFJFU09MVlVUSU9OKTogUHJvbWlzZTx2b2lkPiB7XG4gICAgICAgIGlmICh0aGlzLndhc1JlamVjdGVkIHx8IHRoaXMud2FzUmVzb2x2ZWQpIHtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuICAgICAgICB0aGlzLndhc1Jlc29sdmVkID0gdHJ1ZTtcbiAgICAgICAgdGhpcy5yZXNvbHV0aW9uID0gdmFsdWU7XG4gICAgICAgIHRoaXMucmVzb2x2ZXMuZm9yRWFjaCgocmVzb2x2ZSkgPT4gcmVzb2x2ZSh2YWx1ZSkpO1xuICAgICAgICB0aGlzLnJlc29sdmVzID0gW107XG4gICAgICAgIHRoaXMucmVqZWN0cyA9IFtdO1xuICAgICAgICByZXR1cm4gbmV3IFByb21pc2U8dm9pZD4oKHJlc29sdmUpID0+IHNldFRpbWVvdXQoKCkgPT4gcmVzb2x2ZSgpKSk7XG4gICAgfVxuXG4gICAgYXN5bmMgcmVqZWN0KHJlYXNvbjogUkVKRUNUSU9OKTogUHJvbWlzZTx2b2lkPiB7XG4gICAgICAgIGlmICh0aGlzLndhc1JlamVjdGVkIHx8IHRoaXMud2FzUmVzb2x2ZWQpIHtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuICAgICAgICB0aGlzLndhc1JlamVjdGVkID0gdHJ1ZTtcbiAgICAgICAgdGhpcy5yZWFzb24gPSByZWFzb247XG4gICAgICAgIHRoaXMucmVqZWN0cy5mb3JFYWNoKChyZWplY3QpID0+IHJlamVjdChyZWFzb24pKTtcbiAgICAgICAgdGhpcy5yZXNvbHZlcyA9IFtdO1xuICAgICAgICB0aGlzLnJlamVjdHMgPSBbXTtcbiAgICAgICAgcmV0dXJuIG5ldyBQcm9taXNlPHZvaWQ+KChyZXNvbHZlKSA9PiBzZXRUaW1lb3V0KCgpID0+IHJlc29sdmUoKSkpO1xuICAgIH1cblxuICAgIGlzUGVuZGluZygpOiBib29sZWFuIHtcbiAgICAgICAgcmV0dXJuICF0aGlzLndhc1Jlc29sdmVkICYmICF0aGlzLndhc1JlamVjdGVkO1xuICAgIH1cblxuICAgIGlzRnVsZmlsbGVkKCk6IGJvb2xlYW4ge1xuICAgICAgICByZXR1cm4gdGhpcy53YXNSZXNvbHZlZDtcbiAgICB9XG5cbiAgICBpc1JlamVjdGVkKCk6IGJvb2xlYW4ge1xuICAgICAgICByZXR1cm4gdGhpcy53YXNSZWplY3RlZDtcbiAgICB9XG59XG4iLCJpbXBvcnQge1Byb21pc2VCYXJyaWVyfSBmcm9tICcuL3Byb21pc2UtYmFycmllcic7XG5cbi8qXG4gKiBUaGlzIGNsYXNzIHN5bmNocm9uaXplcyBzb21lIEpTIG9iamVjdCdzIGF0dHJpYnV0ZXMgYW5kIGRhdGEgc3RvcmVkIGluXG4gKiBjaHJvbWUuc3RvcmFnZS5sb2NhbCwgd2l0aCBtaW5pbWFsIGRlbGF5LiBJdCBmb2xsb3dzIHRoZXNlIHByaW5jaXBsZXM6XG4gKiAgLSBubyBkZWJvdW5jaW5nLCBkYXRhIGlzIHNhdmVkIGFzIHNvb24gYXMgc2F2ZVN0YXRlKCkgaXMgY2FsbGVkXG4gKiAgLSBubyBjb25jdXJyZW50IHdyaXRlcyAoY2FsbHMgdG8gcy5jLmwuc2V0KCkpOiBpZiBzYXZlU3RhdGUoKSBpcyBjYWxsZWRcbiAqICAgIHJlcGVhdGVkbHkgYmVmb3JlIHByZXZpb3VzIGNhbGwgaXMgY29tcGxldGUsIHRoaXMgY2xhc3Mgd2lsbCB3YWl0IGZvclxuICogICAgYWN0aXZlIHdyaXRlIHRvIGNvbXBsZXRlIGFuZCB3aWxsIHNhdmUgbmV3IGRhdGEuXG4gKiAgLSBubyBjb25jdXJyZW50IHJlYWRzIChjYWxscyB0byBzLmMubC5nZXQoKSk6IGlmIGxvYWRTdGF0ZSgpIGlzIGNhbGxlZFxuICogICAgcmVwZWF0ZWRseSBiZWZvcmUgcHJldmlvdXMgY2FsbCBpcyBjb21wbGV0ZSwgdGhpcyBjbGFzcyB3aWxsIHdhaXQgZm9yXG4gKiAgICBhY3RpdmUgcmVhZCB0byBjb21wbGV0ZSBhbmQgd2lsbCByZXNvbHZlIGFsbCBsb2FkU3RhdGUoKSBjYWxscyBhdCBvbmNlLlxuICogIC0gYWxsIHNpbXVsdGFuZW91c2x5IGFjdGl2ZSBjYWxscyB0byBzYXZlU3RhdGUoKSBhbmQgbG9hZFN0YXRlKCkgd2FpdCBmb3JcbiAqICAgIGRhdGEgdG8gc2V0dGxlIGFuZCByZXNvbHZlIG9ubHkgYWZ0ZXIgZGF0YSBpcyBndWFyYW50ZWVkIHRvIGJlIGNvaGVyZW50LlxuICogIC0gZGF0YSBzYXZlZCB3aXRoIHRoZSBicm93c2VyIGFsd2F5cyB3aW5zIChiZWNhdXNlIEpTIHR5cGljYWxseSBoYXMgb25seVxuICogICAgZGVmYXVsdCB2YWx1ZXMgYW5kIHRvIGVuc3VyZSB0aGF0IGlmIHRoZSBzYW1lIGNsYXNzIGV4aXN0cyBpbiBtdWx0aXBsZVxuICogICAgY29udGV4dHMgZXZlcnkgaW5zdGFuY2Ugb2YgdGhpcyBjbGFzcyBoYXMgdGhlIHNhbWUgdmFsdWVzKVxuICogSW4gcHJhY3RpY2UsIHRoZXNlIHByaW5jaXBsZXMgaW1wbHkgdGhhdCBhdCBhbnkgZ2l2ZW4gbW9tZW50IHRoZXJlIGlzIGVpdGhlclxuICogbm8gYWN0aXZlIHJlYWQgYW5kIHdyaXRlIG9wZXJhdGlvbnMgb3IgdGhpcyBjbGFzcyBpcyBwZXJmb3JtaW5nIGV4YWN0bHkgb25lXG4gKiByZWFkIG9yIGV4YWN0bHkgb25lIHdyaXRlIG9wZXJhdGlvbi5cbiAqXG4gKiBTdGF0ZSBtYW5hZ2VyIGlzIGEgc3RhdGUgbWFjaGluZSB3aGljaCB3b3JrcyBhcyBmb2xsb3dzOlxuICogICAgICAgKy0tLS0tLS0tLS0tK1xuICogICAgICAgfCAgSW5pdGlhbCAgfFxuICogICAgICAgKy0tLS0tLS0tLS0tK1xuICogICAgICAgICAgICAgIHxcbiAqICAgICAgICAgICAgICB8IFN0YXRlTWFuYWdlckltcGwubG9hZFN0YXRlKCkgaXMgY2FsbGVkLFxuICogICAgICAgICAgICAgIHwgU3RhdGVNYW5hZ2VySW1wbCB3aWxsIGNhbGwgY2hyb21lLnN0b3JhZ2UubG9jYWwuZ2V0KClcbiAqICAgICAgICAgICAgICB8XG4gKiAgICAgICAgICAgICAgdlxuICogICAgICAgKy0tLS0tLS0tLS0tLStcbiAqICstLS0tLXwgIExvYWRpbmcgUiB8XG4gKiB8ICAgICArLS0tLS0tLS0tLS0tK1xuICogfCAgICAgICAgICAgIHxcbiAqIHwgICAgICAgICAgICB8IGNocm9tZS5zdG9yYWdlLmxvY2FsLmdldCgpIGNhbGxiYWNrIGlzIGNhbGxlZCxcbiAqIHwgWzFdICAgICAgICB8IFN0YXRlTWFuYWdlckltcGwgaGFzIGxvYWRlZCB0aGUgZGF0YS5cbiAqIHwgICAgICAgICAgICB8XG4gKiB8ICAgICAgICAgICAgdlxuICogfCAgICAgICstLS0tLS0tLS0tKzwtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tK1xuICogfCAgICAgIHwgIFJlYWR5ICAgfCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfFxuICogfCAgICAgICstLS0tLS0tLS0tKzwtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tKyAgICAgfFxuICogfCAgICAgICAgICAgIHwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfCAgICAgfFxuICogfCAgICAgICAgICAgIHwgU3RhdGVNYW5hZ2VySW1wbC5zYXZlU3RhdGUoKSBpcyBjYWxsZWQsICAgfCAgICAgfFxuICogfCAgICAgICAgICAgIHwgU3RhdGVNYW5hZ2VySW1wbCB3aWxsIGNhbGxlY3QgZGF0YSBhbmQgICAgfCAgICAgfFxuICogfCAgICAgICAgICAgIHwgY2FsbCBjaHJvbWUuc3RvcmFnZS5sb2NhbC5zZXQoKSAgICAgICAgICAgfCAgICAgfFxuICogfCAgICAgICAgICAgIHYgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfCAgICAgfFxuICogfCAgICAgKy0tLS0tLS0tLS0tKy0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tKyAgICAgfFxuICogfCAgKy0tfCAgU2F2aW5nIFcgfCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfFxuICogfCAgfCAgKy0tLS0tLS0tLS0tKzwtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tKyAgICAgfFxuICogfCAgfCAgICAgICAgIHwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfCAgICAgfFxuICogfCAgfCAgICAgICAgIHwgU3RhdGVNYW5hZ2VySW1wbC5zYXZlU3RhdGUoKSBpcyBjYWxsZWQgICAgfCAgICAgfFxuICogfCAgfCAgICAgICAgIHwgYmVmb3JlIG9uZ29pbmcgd3JpdGUgb3BlcmF0aW9uIGVuZHMuICAgICAgfCAgICAgfFxuICogfCAgfCAgICAgICAgIHwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfCAgICAgfFxuICogfCAgfCAgICAgICAgIHYgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfCAgICAgfFxuICogfCAgfCAgKy0tLS0tLS0tLS0tLS0tLS0tLS0rICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfCAgICAgfFxuICogfCAgfCAgfCBTYXZpbmcgT3ZlcnJpZGUgVyB8LS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tKyAgICAgfFxuICogfCAgfCAgKy0tLS0tLS0tLS0tLS0tLS0tLS0rICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfFxuICogfCAgfCAgICAgICAgIHwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfFxuICogfCAgfCAgICAgICAgIHwgICAgIG9uQ2hhbmdlIGhhbmRsZXIgaXMgY2FsbGVkIGR1cmluZyBhbiBhY3RpdmUgfFxuICogfCAgfCBbMV0gICAgIHwgWzFdIHJlYWQvd3JpdGUgb3BlcmF0aW9uICAgICAgICAgICAgICAgICAgICAgICAgfFxuICogfCAgfCAgICAgICAgIHwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfFxuICogfCAgfCAgICAgICAgIHYgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfFxuICogfCAgKy0+Ky0tLS0tLS0tLS0tLS0tLS0tLS0rICAgICAgICstLS0tLS0tLS0tLS0rICAgICAgICAgICAgICAgfFxuICogfCAgICAgfCBPbkNoYW5nZSBSYWNlIFIvVyB8LS0tLS0tPnwgUmVjb3ZlcnkgUiB8LS0tLS0tLS0tLS0tLS0tK1xuICogKy0tLS0+Ky0tLS0tLS0tLS0tLS0tLS0tLS0rICAgICAgICstLS0tLS0tLS0tLS0rXG4gKiAgICAgICAgICAgICAgICAgXiAgICAgICAgICAgICAgICAgICAgICAgfFxuICogICAgICAgICAgICAgICAgICstLS0tLS0tLS0tLS0tLS0tLS0tLS0tICtcbiAqICAgICAgICAgICAgICAgICAgICAgICAgICAgICBbMV1cbiAqXG4gKiBSIGFuZCBXIGluZGljYXRlIGFjdGl2ZSByZWFkIChnZXQpIGFuZCB3cml0ZSAoc2V0KSBvcGVyYXRpb25zLlxuICpcbiAqIEluaXRpYWwgLSBPbmx5IGNvbnN0cnVjdG9yIHdhcyBjYWxsZWQuXG4gKiBMb2FkaW5nIC0gbG9hZFN0YXRlKCkgaXMgY2FsbGVkXG4gKiBSZWFkeSAtIGRhdGEgd2FzIHJldHJlaXZlZCBmcm9tIHN0b3JhZ2UuXG4gKiBTYXZpbmcgLSBzYXZlU3RhdGUoKSBpcyBjYWxsZWQgYW5kIHRoZXJlIGlzIG5vIGNocm9tZS5zdG9yYWdlLmxvY2FsLnNldCgpXG4gKiAgIG9wZXJhdGlvbiBpbiBwcm9ncmVzcy4gV2UganVzdCBuZWVkIHRvIGNvbGxlY3QgYW5kIHNhdmUgdGhlIGRhdGEuXG4gKiBTYXZpbmcgT3ZlcnJpZGUgLSBzYXZlU3RhdGUoKSBpcyBjYWxsZWQgYmVmb3JlIHRoZSBsYXN0IHdyaXRlIG9wZXJhdGlvblxuICogICB3YXMgY29tcGxldGUgKGRhdGEgYmVjYW1lIG9ic29sZXRlIGV2ZW4gYmVmb3JlIGl0IHdhcyB3cml0dGVuIHRvIHN0b3JhZ2UpLlxuICogICBXZSB3YWl0IGZvciBvbmdvaW5nIHdyaXRlIG9wZXJhdGlvbiB0byBlbmQgYW5kIG9ubHkgdGhlbiBzdGFydCBhIG5ldyBvbmUuXG4gKiBPbkNoYW5nZSBSYWNlIC0gY2hyb21lLnN0b3JhZ2Uub25DaGFuZ2VkIGxpc3RlbmVyIHdhcyBjYWxsZWQgZHVyaW5nIGFuIGFjdGl2ZVxuICogICByZWFkL3dyaXRlIG9wZXJhdGlvbi4gU3RhdGVNYW5hZ2VyIG5lZWRzIHRvIHdhaXQgZm9yIHRoYXQgb3BlcmF0aW9uIHRvIGVuZFxuICogICBhbmQgcmUtcmVxdWVzdCBkYXRhIGFnYWluLlxuICogUmVjb3ZlcnkgLSBzdGF0ZSBtYW5hZ2VyIGRldGVjdGVkIGEgcmFjZSBjb25kaXRpb24sIHByb2JhYmx5IGNhdXNlZCBieSBhblxuICogICBvbkNoYW5nZWQgZXZlbnQgZHVyaW5nIGRhdGEgbG9hZGluZyBvciBzYXZpbmcuIFN0YXRlIE1hbmFnZXIgd2lsbCBsb2FkIGRhdGFcbiAqICAgZnJvbSBicm93c2VyIHRvIGVuc3VyZSBkYXRhIGNvaGVyZW5jZS5cbiAqL1xuXG5kZWNsYXJlIGNvbnN0IF9fVEVTVF9fOiBib29sZWFuO1xuXG5lbnVtIFN0YXRlTWFuYWdlckltcGxTdGF0ZSB7XG4gICAgSU5JVElBTCA9IDAsXG4gICAgTE9BRElORyA9IDEsXG4gICAgUkVBRFkgPSAyLFxuICAgIFNBVklORyA9IDMsXG4gICAgU0FWSU5HX09WRVJSSURFID0gNCxcbiAgICBPTkNIQU5HRV9SQUNFID0gNSxcbiAgICBSRUNPVkVSWSA9IDZcbn1cblxuZXhwb3J0IGNsYXNzIFN0YXRlTWFuYWdlckltcGw8VCBleHRlbmRzIFJlY29yZDxzdHJpbmcsIHVua25vd24+PiB7XG4gICAgcHJpdmF0ZSBsb2NhbFN0b3JhZ2VLZXk6IHN0cmluZztcbiAgICBwcml2YXRlIHBhcmVudDtcbiAgICBwcml2YXRlIGRlZmF1bHRzOiBUO1xuICAgIHByaXZhdGUgbG9nV2FybjogKGxvZzogc3RyaW5nKSA9PiB2b2lkO1xuXG4gICAgcHJpdmF0ZSBtZXRhOiBTdGF0ZU1hbmFnZXJJbXBsU3RhdGU7XG4gICAgcHJpdmF0ZSBiYXJyaWVyOiBQcm9taXNlQmFycmllcjx2b2lkLCB2b2lkPiB8IG51bGwgPSBudWxsO1xuXG4gICAgcHJpdmF0ZSBzdG9yYWdlOiB7XG4gICAgICAgIGdldDogKHN0b3JhZ2VLZXk6IHN0cmluZywgY2FsbGJhY2s6IChpdGVtczogeyBba2V5OiBzdHJpbmddOiBhbnkgfSkgPT4gdm9pZCkgPT4gdm9pZDtcbiAgICAgICAgc2V0OiAoaXRlbXM6IHsgW2tleTogc3RyaW5nXTogYW55IH0sIGNhbGxiYWNrOiAoKSA9PiB2b2lkKSA9PiB2b2lkO1xuICAgIH07XG5cbiAgICBwcml2YXRlIGxpc3RlbmVyczogU2V0PCgpID0+IHZvaWQ+O1xuXG4gICAgY29uc3RydWN0b3IobG9jYWxTdG9yYWdlS2V5OiBzdHJpbmcsIHBhcmVudDogYW55LCBkZWZhdWx0czogVCwgc3RvcmFnZToge2dldDogKHN0b3JhZ2VLZXk6IHN0cmluZywgY2FsbGJhY2s6IChpdGVtczogeyBba2V5OiBzdHJpbmddOiBhbnkgfSkgPT4gdm9pZCkgPT4gdm9pZDsgc2V0OiAoaXRlbXM6IHsgW2tleTogc3RyaW5nXTogYW55IH0sIGNhbGxiYWNrOiAoKSA9PiB2b2lkKSA9PiB2b2lkfSwgYWRkTGlzdGVuZXI6IChsaXN0ZW5lcjogKGRhdGE6IFQpID0+IHZvaWQpID0+IHZvaWQsIGxvZ1dhcm46IChsb2c6IHN0cmluZykgPT4gdm9pZCl7XG4gICAgICAgIHRoaXMubG9jYWxTdG9yYWdlS2V5ID0gbG9jYWxTdG9yYWdlS2V5O1xuICAgICAgICB0aGlzLnBhcmVudCA9IHBhcmVudDtcbiAgICAgICAgdGhpcy5kZWZhdWx0cyA9IGRlZmF1bHRzO1xuICAgICAgICB0aGlzLnN0b3JhZ2UgPSBzdG9yYWdlO1xuICAgICAgICBhZGRMaXN0ZW5lcigoY2hhbmdlKSA9PiB0aGlzLm9uQ2hhbmdlKGNoYW5nZSkpO1xuICAgICAgICB0aGlzLmxvZ1dhcm4gPSBsb2dXYXJuO1xuXG4gICAgICAgIHRoaXMubWV0YSA9IFN0YXRlTWFuYWdlckltcGxTdGF0ZS5JTklUSUFMO1xuICAgICAgICB0aGlzLmJhcnJpZXIgPSBuZXcgUHJvbWlzZUJhcnJpZXIoKTtcbiAgICAgICAgdGhpcy5saXN0ZW5lcnMgPSBuZXcgU2V0KCk7XG5cbiAgICAgICAgLy8gVE9ETyhBbnRvbik6IGNvbnNpZGVyIGNhbGxpbmcgdGhpcy5sb2FkU3RhdGUoKSB0byBwcmVsb2FkIGRhdGEsXG4gICAgICAgIC8vIGFuZCByZW1vdmUgU3RhdGVNYW5hZ2VySW1wbFN0YXRlLklOSVRJQUwuXG4gICAgfVxuXG4gICAgcHJpdmF0ZSBjb2xsZWN0U3RhdGUoKSB7XG4gICAgICAgIGNvbnN0IHN0YXRlID0ge30gYXMgVDtcbiAgICAgICAgZm9yIChjb25zdCBrZXkgb2YgT2JqZWN0LmtleXModGhpcy5kZWZhdWx0cykgYXMgQXJyYXk8a2V5b2YgVD4pIHtcbiAgICAgICAgICAgIHN0YXRlW2tleV0gPSB0aGlzLnBhcmVudFtrZXldIHx8IHRoaXMuZGVmYXVsdHNba2V5XTtcbiAgICAgICAgfVxuICAgICAgICByZXR1cm4gc3RhdGU7XG4gICAgfVxuXG4gICAgcHJpdmF0ZSBhcHBseVN0YXRlKHN0b3JhZ2U6IFQpIHtcbiAgICAgICAgT2JqZWN0LmFzc2lnbih0aGlzLnBhcmVudCwgdGhpcy5kZWZhdWx0cywgc3RvcmFnZSk7XG4gICAgfVxuXG4gICAgcHJpdmF0ZSByZWxlYXNlQmFycmllcigpIHtcbiAgICAgICAgY29uc3QgYmFycmllciA9IHRoaXMuYmFycmllcjtcbiAgICAgICAgdGhpcy5iYXJyaWVyID0gbmV3IFByb21pc2VCYXJyaWVyKCk7XG4gICAgICAgIGJhcnJpZXIhLnJlc29sdmUoKTtcbiAgICB9XG5cbiAgICBwcml2YXRlIG5vdGlmeUxpc3RlbmVycygpIHtcbiAgICAgICAgdGhpcy5saXN0ZW5lcnMuZm9yRWFjaCgobGlzdGVuZXIpID0+IGxpc3RlbmVyKCkpO1xuICAgIH1cblxuICAgIHByaXZhdGUgb25DaGFuZ2Uoc3RhdGU6IFQpIHtcbiAgICAgICAgc3dpdGNoICh0aGlzLm1ldGEpIHtcbiAgICAgICAgICAgIGNhc2UgU3RhdGVNYW5hZ2VySW1wbFN0YXRlLklOSVRJQUw6XG4gICAgICAgICAgICAgICAgdGhpcy5tZXRhID0gU3RhdGVNYW5hZ2VySW1wbFN0YXRlLlJFQURZO1xuICAgICAgICAgICAgICAgIC8vIGZhbGx0aHJvdWdoXG4gICAgICAgICAgICBjYXNlIFN0YXRlTWFuYWdlckltcGxTdGF0ZS5SRUFEWTpcbiAgICAgICAgICAgICAgICB0aGlzLmFwcGx5U3RhdGUoc3RhdGUpO1xuICAgICAgICAgICAgICAgIHRoaXMubm90aWZ5TGlzdGVuZXJzKCk7XG4gICAgICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuTE9BRElORzpcbiAgICAgICAgICAgICAgICB0aGlzLm1ldGEgPSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuT05DSEFOR0VfUkFDRTtcbiAgICAgICAgICAgICAgICByZXR1cm47XG4gICAgICAgICAgICBjYXNlIFN0YXRlTWFuYWdlckltcGxTdGF0ZS5TQVZJTkc6XG4gICAgICAgICAgICAgICAgdGhpcy5tZXRhID0gU3RhdGVNYW5hZ2VySW1wbFN0YXRlLk9OQ0hBTkdFX1JBQ0U7XG4gICAgICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuU0FWSU5HX09WRVJSSURFOlxuICAgICAgICAgICAgICAgIHRoaXMubWV0YSA9IFN0YXRlTWFuYWdlckltcGxTdGF0ZS5PTkNIQU5HRV9SQUNFO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuT05DSEFOR0VfUkFDRTpcbiAgICAgICAgICAgICAgICAvLyBXZSBhcmUgYWxyZWFkeSB3YWl0aW5nIGZvciBhbiBhY3RpdmUgcmVhZC93cml0ZSBvcGVyYXRpb24gdG8gZW5kXG4gICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICBjYXNlIFN0YXRlTWFuYWdlckltcGxTdGF0ZS5SRUNPVkVSWTpcbiAgICAgICAgICAgICAgICB0aGlzLm1ldGEgPSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuT05DSEFOR0VfUkFDRTtcbiAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgfVxuICAgIH1cblxuICAgIHByaXZhdGUgc2F2ZVN0YXRlSW50ZXJuYWwoKSB7XG4gICAgICAgIHRoaXMuc3RvcmFnZS5zZXQoe1t0aGlzLmxvY2FsU3RvcmFnZUtleV06IHRoaXMuY29sbGVjdFN0YXRlKCl9LCAoKSA9PiB7XG4gICAgICAgICAgICBzd2l0Y2ggKHRoaXMubWV0YSkge1xuICAgICAgICAgICAgICAgIGNhc2UgU3RhdGVNYW5hZ2VySW1wbFN0YXRlLklOSVRJQUw6XG4gICAgICAgICAgICAgICAgICAgIC8vIGZhbGx0aHJvdWdoXG4gICAgICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuTE9BRElORzpcbiAgICAgICAgICAgICAgICAgICAgLy8gZmFsbHRocm91Z2hcbiAgICAgICAgICAgICAgICBjYXNlIFN0YXRlTWFuYWdlckltcGxTdGF0ZS5SRUFEWTpcbiAgICAgICAgICAgICAgICAgICAgLy8gZmFsbHRocm91Z2hcbiAgICAgICAgICAgICAgICBjYXNlIFN0YXRlTWFuYWdlckltcGxTdGF0ZS5SRUNPVkVSWTpcbiAgICAgICAgICAgICAgICAgICAgdGhpcy5sb2dXYXJuKCdVbmV4cGVjdGVkIHN0YXRlLiBQb3NzaWJsZSBkYXRhIHJhY2UhJyk7XG4gICAgICAgICAgICAgICAgICAgIHRoaXMubWV0YSA9IFN0YXRlTWFuYWdlckltcGxTdGF0ZS5PTkNIQU5HRV9SQUNFO1xuICAgICAgICAgICAgICAgICAgICB0aGlzLmxvYWRTdGF0ZUludGVybmFsKCk7XG4gICAgICAgICAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgICAgICAgICBjYXNlIFN0YXRlTWFuYWdlckltcGxTdGF0ZS5TQVZJTkc6XG4gICAgICAgICAgICAgICAgICAgIHRoaXMubWV0YSA9IFN0YXRlTWFuYWdlckltcGxTdGF0ZS5SRUFEWTtcbiAgICAgICAgICAgICAgICAgICAgdGhpcy5yZWxlYXNlQmFycmllcigpO1xuICAgICAgICAgICAgICAgICAgICByZXR1cm47XG4gICAgICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuU0FWSU5HX09WRVJSSURFOlxuICAgICAgICAgICAgICAgICAgICB0aGlzLm1ldGEgPSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuU0FWSU5HO1xuICAgICAgICAgICAgICAgICAgICB0aGlzLnNhdmVTdGF0ZUludGVybmFsKCk7XG4gICAgICAgICAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgICAgICAgICBjYXNlIFN0YXRlTWFuYWdlckltcGxTdGF0ZS5PTkNIQU5HRV9SQUNFOlxuICAgICAgICAgICAgICAgICAgICB0aGlzLm1ldGEgPSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuUkVDT1ZFUlk7XG4gICAgICAgICAgICAgICAgICAgIHRoaXMubG9hZFN0YXRlSW50ZXJuYWwoKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfSk7XG4gICAgfVxuXG4gICAgLy8gVGhpcyBmdW5jdGlvbiBpcyBub3QgZ3VhcmFudGVlZCB0byBzYXZlIHN0YXRlIGJlZm9yZSByZXR1cm5pbmdcbiAgICBhc3luYyBzYXZlU3RhdGUoKTogUHJvbWlzZTx2b2lkPiB7XG4gICAgICAgIHN3aXRjaCAodGhpcy5tZXRhKSB7XG4gICAgICAgICAgICBjYXNlIFN0YXRlTWFuYWdlckltcGxTdGF0ZS5JTklUSUFMOlxuICAgICAgICAgICAgICAgIC8vIE1ha2Ugc3VyZSBub3QgdG8gb3ZlcndyaXRlIGRhdGEgYmVmb3JlIGl0IGlzIGxvYWRlZFxuICAgICAgICAgICAgICAgIHRoaXMubG9nV2FybignU3RhdGVNYW5hZ2VyLnNhdmVTdGF0ZSB3YXMgY2FsbGVkIGJlZm9yZSBTdGF0ZU1hbmFnZXIubG9hZFN0YXRlKCkuIFBvc3NpYmxlIGRhdGEgcmFjZSEgTG9hZGluZyBkYXRhIGluc3RlYWQuJyk7XG4gICAgICAgICAgICAgICAgcmV0dXJuIHRoaXMubG9hZFN0YXRlKCk7XG4gICAgICAgICAgICBjYXNlIFN0YXRlTWFuYWdlckltcGxTdGF0ZS5MT0FESU5HOlxuICAgICAgICAgICAgICAgIC8vIE5lZWQgdG8gd2FpdCBmb3IgYWN0aXZlIHJlYWQgb3BlcmF0aW9uIHRvIGVuZFxuICAgICAgICAgICAgICAgIHRoaXMubG9nV2FybignU3RhdGVNYW5hZ2VyLnNhdmVTdGF0ZSB3YXMgY2FsbGVkIGJlZm9yZSBTdGF0ZU1hbmFnZXIubG9hZFN0YXRlKCkgcmVzb2x2ZWQuIFBvc3NpYmxlIGRhdGEgcmFjZSEgTG9hZGluZyBkYXRhIGluc3RlYWQuJyk7XG4gICAgICAgICAgICAgICAgcmV0dXJuIHRoaXMuYmFycmllciEuZW50cnkoKTtcbiAgICAgICAgICAgIGNhc2UgU3RhdGVNYW5hZ2VySW1wbFN0YXRlLlJFQURZOiB7XG4gICAgICAgICAgICAgICAgdGhpcy5tZXRhID0gU3RhdGVNYW5hZ2VySW1wbFN0YXRlLlNBVklORztcbiAgICAgICAgICAgICAgICBjb25zdCBlbnRyeSA9IHRoaXMuYmFycmllciEuZW50cnkoKTtcbiAgICAgICAgICAgICAgICB0aGlzLnNhdmVTdGF0ZUludGVybmFsKCk7XG4gICAgICAgICAgICAgICAgcmV0dXJuIGVudHJ5O1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuU0FWSU5HOlxuICAgICAgICAgICAgICAgIC8vIEFub3RoZXIgc2F2ZSBpcyBpbiBwcm9ncmVzc1xuICAgICAgICAgICAgICAgIHRoaXMubWV0YSA9IFN0YXRlTWFuYWdlckltcGxTdGF0ZS5TQVZJTkdfT1ZFUlJJREU7XG4gICAgICAgICAgICAgICAgcmV0dXJuIHRoaXMuYmFycmllciEuZW50cnkoKTtcbiAgICAgICAgICAgIGNhc2UgU3RhdGVNYW5hZ2VySW1wbFN0YXRlLlNBVklOR19PVkVSUklERTpcbiAgICAgICAgICAgICAgICByZXR1cm4gdGhpcy5iYXJyaWVyIS5lbnRyeSgpO1xuICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuT05DSEFOR0VfUkFDRTpcbiAgICAgICAgICAgICAgICB0aGlzLmxvZ1dhcm4oJ1N0YXRlTWFuYWdlci5zYXZlU3RhdGUgd2FzIGNhbGxlZCBkdXJpbmcgYWN0aXZlIHJlYWQvd3JpdGUgb3BlcmF0aW9uLiBQb3NzaWJsZSBkYXRhIHJhY2UhIExvYWRpbmcgZGF0YSBpbnN0ZWFkLicpO1xuICAgICAgICAgICAgICAgIHJldHVybiB0aGlzLmJhcnJpZXIhLmVudHJ5KCk7XG4gICAgICAgICAgICBjYXNlIFN0YXRlTWFuYWdlckltcGxTdGF0ZS5SRUNPVkVSWTpcbiAgICAgICAgICAgICAgICB0aGlzLmxvZ1dhcm4oJ1N0YXRlTWFuYWdlci5zYXZlU3RhdGUgd2FzIGNhbGxlZCBkdXJpbmcgYWN0aXZlIHJlYWQgb3BlcmF0aW9uLiBQb3NzaWJsZSBkYXRhIHJhY2UhIFdhaXRpbmcgZm9yIGRhdGEgbG9hZCBpbnN0ZWFkLicpO1xuICAgICAgICAgICAgICAgIHJldHVybiB0aGlzLmJhcnJpZXIhLmVudHJ5KCk7XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBwcml2YXRlIGxvYWRTdGF0ZUludGVybmFsKCkge1xuICAgICAgICB0aGlzLnN0b3JhZ2UuZ2V0KHRoaXMubG9jYWxTdG9yYWdlS2V5LCAoZGF0YTogYW55KSA9PiB7XG4gICAgICAgICAgICBzd2l0Y2ggKHRoaXMubWV0YSkge1xuICAgICAgICAgICAgICAgIGNhc2UgU3RhdGVNYW5hZ2VySW1wbFN0YXRlLklOSVRJQUw6XG4gICAgICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuUkVBRFk6XG4gICAgICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuU0FWSU5HOlxuICAgICAgICAgICAgICAgIGNhc2UgU3RhdGVNYW5hZ2VySW1wbFN0YXRlLlNBVklOR19PVkVSUklERTpcbiAgICAgICAgICAgICAgICAgICAgdGhpcy5sb2dXYXJuKCdVbmV4cGVjdGVkIHN0YXRlLiBQb3NzaWJsZSBkYXRhIHJhY2UhJyk7XG4gICAgICAgICAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgICAgICAgICBjYXNlIFN0YXRlTWFuYWdlckltcGxTdGF0ZS5MT0FESU5HOlxuICAgICAgICAgICAgICAgICAgICB0aGlzLm1ldGEgPSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuUkVBRFk7XG4gICAgICAgICAgICAgICAgICAgIHRoaXMuYXBwbHlTdGF0ZShkYXRhW3RoaXMubG9jYWxTdG9yYWdlS2V5XSk7XG4gICAgICAgICAgICAgICAgICAgIHRoaXMucmVsZWFzZUJhcnJpZXIoKTtcbiAgICAgICAgICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICAgICAgICAgIGNhc2UgU3RhdGVNYW5hZ2VySW1wbFN0YXRlLk9OQ0hBTkdFX1JBQ0U6XG4gICAgICAgICAgICAgICAgICAgIHRoaXMubWV0YSA9IFN0YXRlTWFuYWdlckltcGxTdGF0ZS5SRUNPVkVSWTtcbiAgICAgICAgICAgICAgICAgICAgdGhpcy5sb2FkU3RhdGVJbnRlcm5hbCgpO1xuICAgICAgICAgICAgICAgIC8vIGVzbGludC1kaXNhYmxlLW5leHQtbGluZSBuby1mYWxsdGhyb3VnaFxuICAgICAgICAgICAgICAgIGNhc2UgU3RhdGVNYW5hZ2VySW1wbFN0YXRlLlJFQ09WRVJZOlxuICAgICAgICAgICAgICAgICAgICB0aGlzLm1ldGEgPSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuUkVBRFk7XG4gICAgICAgICAgICAgICAgICAgIHRoaXMuYXBwbHlTdGF0ZShkYXRhW3RoaXMubG9jYWxTdG9yYWdlS2V5XSk7XG4gICAgICAgICAgICAgICAgICAgIHRoaXMucmVsZWFzZUJhcnJpZXIoKTtcbiAgICAgICAgICAgICAgICAgICAgdGhpcy5ub3RpZnlMaXN0ZW5lcnMoKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfSk7XG4gICAgfVxuXG4gICAgYXN5bmMgbG9hZFN0YXRlKCk6IFByb21pc2U8dm9pZD4ge1xuICAgICAgICBzd2l0Y2ggKHRoaXMubWV0YSkge1xuICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuSU5JVElBTDoge1xuICAgICAgICAgICAgICAgIHRoaXMubWV0YSA9IFN0YXRlTWFuYWdlckltcGxTdGF0ZS5MT0FESU5HO1xuICAgICAgICAgICAgICAgIGNvbnN0IGVudHJ5ID0gdGhpcy5iYXJyaWVyIS5lbnRyeSgpO1xuICAgICAgICAgICAgICAgIHRoaXMubG9hZFN0YXRlSW50ZXJuYWwoKTtcbiAgICAgICAgICAgICAgICByZXR1cm4gZW50cnk7XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICBjYXNlIFN0YXRlTWFuYWdlckltcGxTdGF0ZS5SRUFEWTpcbiAgICAgICAgICAgICAgICByZXR1cm47XG4gICAgICAgICAgICBjYXNlIFN0YXRlTWFuYWdlckltcGxTdGF0ZS5TQVZJTkc6XG4gICAgICAgICAgICAgICAgcmV0dXJuIHRoaXMuYmFycmllciEuZW50cnkoKTtcbiAgICAgICAgICAgIGNhc2UgU3RhdGVNYW5hZ2VySW1wbFN0YXRlLlNBVklOR19PVkVSUklERTpcbiAgICAgICAgICAgICAgICByZXR1cm4gdGhpcy5iYXJyaWVyIS5lbnRyeSgpO1xuICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuTE9BRElORzpcbiAgICAgICAgICAgICAgICByZXR1cm4gdGhpcy5iYXJyaWVyIS5lbnRyeSgpO1xuICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuT05DSEFOR0VfUkFDRTpcbiAgICAgICAgICAgICAgICByZXR1cm4gdGhpcy5iYXJyaWVyIS5lbnRyeSgpO1xuICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuUkVDT1ZFUlk6XG4gICAgICAgICAgICAgICAgcmV0dXJuIHRoaXMuYmFycmllciEuZW50cnkoKTtcbiAgICAgICAgfVxuICAgIH1cblxuICAgIGFkZENoYW5nZUxpc3RlbmVyKGNhbGxiYWNrOiAoKSA9PiB2b2lkKTogdm9pZCB7XG4gICAgICAgIHRoaXMubGlzdGVuZXJzLmFkZChjYWxsYmFjayk7XG4gICAgfVxuXG4gICAgZ2V0U3RhdGVGb3JUZXN0aW5nKCk6IHN0cmluZyB7XG4gICAgICAgIGlmICghX19URVNUX18pIHtcbiAgICAgICAgICAgIHJldHVybiAnJztcbiAgICAgICAgfVxuICAgICAgICBzd2l0Y2ggKHRoaXMubWV0YSkge1xuICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuSU5JVElBTDpcbiAgICAgICAgICAgICAgICByZXR1cm4gJ0luaXRpYWwnO1xuICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuTE9BRElORzpcbiAgICAgICAgICAgICAgICByZXR1cm4gJ0xvYWRpbmcnO1xuICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuUkVBRFk6XG4gICAgICAgICAgICAgICAgcmV0dXJuICdSZWFkeSc7XG4gICAgICAgICAgICBjYXNlIFN0YXRlTWFuYWdlckltcGxTdGF0ZS5TQVZJTkc6XG4gICAgICAgICAgICAgICAgcmV0dXJuICdTYXZpbmcnO1xuICAgICAgICAgICAgY2FzZSBTdGF0ZU1hbmFnZXJJbXBsU3RhdGUuU0FWSU5HX09WRVJSSURFOlxuICAgICAgICAgICAgICAgIHJldHVybiAnU2F2aW5nIE92ZXJyaWRlJztcbiAgICAgICAgICAgIGNhc2UgU3RhdGVNYW5hZ2VySW1wbFN0YXRlLk9OQ0hBTkdFX1JBQ0U6XG4gICAgICAgICAgICAgICAgcmV0dXJuICdPbmNoYW5nZSBSYWNlJztcbiAgICAgICAgICAgIGNhc2UgU3RhdGVNYW5hZ2VySW1wbFN0YXRlLlJFQ09WRVJZOlxuICAgICAgICAgICAgICAgIHJldHVybiAnUmVjb3ZlcnknO1xuICAgICAgICB9XG4gICAgfVxufVxuIiwiLyoqXG4gKiBUaGlzIGNsYXNzIGV4aXN0cyBvbmx5IHRvIHNpbXBsaWZ5IEplc3QgdGVzdGluZyBvZiB0aGUgcmVhbCBpbXBsZW1lbnRhdGlvblxuICogd2hpY2ggaXMgaW4gU3RhdGVNYW5hZ2VySW1wbCBjbGFzcy5cbiAqL1xuXG5pbXBvcnQge2lzTm9uUGVyc2lzdGVudH0gZnJvbSAnLi9wbGF0Zm9ybSc7XG5pbXBvcnQge1N0YXRlTWFuYWdlckltcGx9IGZyb20gJy4vc3RhdGUtbWFuYWdlci1pbXBsJztcblxuXG5leHBvcnQgY2xhc3MgU3RhdGVNYW5hZ2VyPFQgZXh0ZW5kcyBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPj4ge1xuICAgIHByaXZhdGUgc3RhdGVNYW5hZ2VyOiBTdGF0ZU1hbmFnZXJJbXBsPFQ+IHwgbnVsbDtcblxuICAgIGNvbnN0cnVjdG9yKGxvY2FsU3RvcmFnZUtleTogc3RyaW5nLCBwYXJlbnQ6IGFueSwgZGVmYXVsdHM6IFQsIGxvZ1dhcm46IChsb2c6IHN0cmluZykgPT4gdm9pZCl7XG4gICAgICAgIGlmIChpc05vblBlcnNpc3RlbnQpIHtcbiAgICAgICAgICAgIGZ1bmN0aW9uIGFkZExpc3RlbmVyKGxpc3RlbmVyOiAoZGF0YTogVCkgPT4gdm9pZCkge1xuICAgICAgICAgICAgICAgIGNocm9tZS5zdG9yYWdlLmxvY2FsLm9uQ2hhbmdlZC5hZGRMaXN0ZW5lcigoY2hhbmdlczogUmVjb3JkPHN0cmluZywgYW55PikgPT4ge1xuICAgICAgICAgICAgICAgICAgICBpZiAobG9jYWxTdG9yYWdlS2V5IGluIGNoYW5nZXMpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgIGxpc3RlbmVyKGNoYW5nZXNbbG9jYWxTdG9yYWdlS2V5XS5uZXdWYWx1ZSk7XG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICB9KTtcbiAgICAgICAgICAgIH1cblxuICAgICAgICAgICAgdGhpcy5zdGF0ZU1hbmFnZXIgPSBuZXcgU3RhdGVNYW5hZ2VySW1wbChcbiAgICAgICAgICAgICAgICBsb2NhbFN0b3JhZ2VLZXksXG4gICAgICAgICAgICAgICAgcGFyZW50LFxuICAgICAgICAgICAgICAgIGRlZmF1bHRzLFxuICAgICAgICAgICAgICAgIGNocm9tZS5zdG9yYWdlLmxvY2FsLFxuICAgICAgICAgICAgICAgIGFkZExpc3RlbmVyLFxuICAgICAgICAgICAgICAgIGxvZ1dhcm4sXG4gICAgICAgICAgICApO1xuICAgICAgICB9XG4gICAgfVxuXG4gICAgYXN5bmMgc2F2ZVN0YXRlKCk6IFByb21pc2U8dm9pZD4ge1xuICAgICAgICBpZiAodGhpcy5zdGF0ZU1hbmFnZXIpIHtcbiAgICAgICAgICAgIHJldHVybiB0aGlzLnN0YXRlTWFuYWdlci5zYXZlU3RhdGUoKTtcbiAgICAgICAgfVxuICAgIH1cblxuICAgIGFzeW5jIGxvYWRTdGF0ZSgpOiBQcm9taXNlPHZvaWQ+IHtcbiAgICAgICAgaWYgKHRoaXMuc3RhdGVNYW5hZ2VyKSB7XG4gICAgICAgICAgICByZXR1cm4gdGhpcy5zdGF0ZU1hbmFnZXIubG9hZFN0YXRlKCk7XG4gICAgICAgIH1cbiAgICB9XG59XG4iLCJkZWNsYXJlIGNvbnN0IF9fVEVTVF9fOiBib29sZWFuO1xuZGVjbGFyZSBjb25zdCBfX0RFQlVHX186IGJvb2xlYW47XG5cbi8vIFByb21pc3NpZmllZCB2ZXJzaW9uIG9mIGNocm9tZS50YWJzLnF1ZXJ5XG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gcXVlcnlUYWJzKHF1ZXJ5OiBjaHJvbWUudGFicy5RdWVyeUluZm8gPSB7fSk6IFByb21pc2U8Y2hyb21lLnRhYnMuVGFiW10+IHtcbiAgICByZXR1cm4gbmV3IFByb21pc2U8Y2hyb21lLnRhYnMuVGFiW10+KChyZXNvbHZlKSA9PiBjaHJvbWUudGFicy5xdWVyeShxdWVyeSwgcmVzb2x2ZSkpO1xufVxuXG4vKipcbiAqIEF0dGVtcHRzIHRvIGZpbmQgdGhlIGN1cnJlbnQgYWN0aXZlIHRhYlxuICogRGVzcGl0ZSBhbGwgZWZmb3J0cywgc29tZXRpbWVzIGFjdGl2ZSB0YWIgbWF5IG5vdCBiZSBkZXRlcm1pbmVkIHNvIHdlIGV4cGxpY2l0bHkgcmV0dXJuIG51bGxhYmxlIHZhbHVlLFxuICogYW5kIGhhbmRsZSB0aGlzIGNhc2UgaW4gY2FsbGVycyBleHBsaWNpdGx5XG4gKi9cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiBnZXRBY3RpdmVUYWIoKTogUHJvbWlzZTxjaHJvbWUudGFicy5UYWIgfCBudWxsPiB7XG4gICAgbGV0IGxvZzogc3RyaW5nIHwgbnVsbCA9IG51bGw7XG4gICAgbGV0IHRhYiA9IChhd2FpdCBxdWVyeVRhYnMoe1xuICAgICAgICBhY3RpdmU6IHRydWUsXG4gICAgICAgIGxhc3RGb2N1c2VkV2luZG93OiB0cnVlLFxuICAgICAgICAvLyBFeHBsaWNpdGx5IGV4Y2x1ZGUgRGFyayBSZWFkZXIncyBEZXYgVG9vbHMgYW5kIG90aGVyIHNwZWNpYWwgd2luZG93cyBmcm9tIHRoZSBxdWVyeVxuICAgICAgICB3aW5kb3dUeXBlOiAnbm9ybWFsJyxcbiAgICB9KSlbMF07XG4gICAgaWYgKCF0YWIpIHtcbiAgICAgICAgdGFiID0gKGF3YWl0IHF1ZXJ5VGFicyh7XG4gICAgICAgICAgICBhY3RpdmU6IHRydWUsXG4gICAgICAgICAgICBsYXN0Rm9jdXNlZFdpbmRvdzogdHJ1ZSxcbiAgICAgICAgICAgIHdpbmRvd1R5cGU6ICdhcHAnLFxuICAgICAgICB9KSlbMF07XG4gICAgfVxuICAgIGlmICghdGFiKSB7XG4gICAgICAgIGlmIChfX0RFQlVHX18gfHwgX19URVNUX18pIHtcbiAgICAgICAgICAgIGxvZyA9ICdtZXRob2QgMSc7XG4gICAgICAgIH1cbiAgICAgICAgLy8gV2hlbiBEYXJrIFJlYWRlcidzIERldlRvb2xzIGFyZSBvcGVuLCBsYXN0IGZvY3VzZWQgd2luZG93IG1pZ2h0IGJlIHRoZSBEZXZUb29scyB3aW5kb3dcbiAgICAgICAgLy8gc28gd2UgbGlmdCB0aGlzIHJlc3RyaWN0aW9uIGFuZCB0cnkgYWdhaW4gKHdpdGggdGhlIGJlc3QgZ3Vlc3MpXG4gICAgICAgIHRhYiA9IChhd2FpdCBxdWVyeVRhYnMoe1xuICAgICAgICAgICAgYWN0aXZlOiB0cnVlLFxuICAgICAgICAgICAgd2luZG93VHlwZTogJ25vcm1hbCcsXG4gICAgICAgIH0pKVswXTtcbiAgICB9XG4gICAgaWYgKCF0YWIpIHtcbiAgICAgICAgaWYgKF9fREVCVUdfXyB8fCBfX1RFU1RfXykge1xuICAgICAgICAgICAgbG9nID0gJ21ldGhvZCAyJztcbiAgICAgICAgfVxuICAgICAgICB0YWIgPSAoYXdhaXQgcXVlcnlUYWJzKHtcbiAgICAgICAgICAgIGFjdGl2ZTogdHJ1ZSxcbiAgICAgICAgICAgIHdpbmRvd1R5cGU6ICdhcHAnLFxuICAgICAgICB9KSlbMF07XG4gICAgfVxuICAgIGlmIChsb2cpIHtcbiAgICAgICAgY29uc29sZS53YXJuKGBUYWJNYW5hZ2VyLmdldEFjdGl2ZVRhYigpIGNvdWxkIG5vdCByZWxpYWJseSBmaW5kIHRoZSBhY3RpdmUgdGFiLCBwaWNraW5nIHRoZSBiZXN0IGd1ZXNzICR7bG9nfWAsIHRhYik7XG4gICAgfVxuICAgIC8vIEluIHJhcmUgY2FzZXMgdGFiIGNhbiBiZSBudWxsLCBkZXNwaXRlIHdoYXQgVHlwZVNjcmlwdCBzYXlzXG4gICAgcmV0dXJuIHRhYiB8fCBudWxsO1xufVxuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gZ2V0QWN0aXZlVGFiVVJMKCk6IFByb21pc2U8c3RyaW5nIHwgbnVsbD4ge1xuICAgIGNvbnN0IHRhYiA9IGF3YWl0IGdldEFjdGl2ZVRhYigpO1xuICAgIHJldHVybiB0YWIgJiYgdGFiLnVybCB8fCBudWxsO1xufVxuIiwiaW1wb3J0IHtleHRlbmRUaGVtZURlZmF1bHRzfSBmcm9tICdAcGx1cy9kZWZhdWx0cyc7XG5pbXBvcnQgdHlwZSB7VGhlbWUsIFVzZXJTZXR0aW5nc30gZnJvbSAnLi9kZWZpbml0aW9ucyc7XG5pbXBvcnQge1RoZW1lRW5naW5lfSBmcm9tICcuL2dlbmVyYXRvcnMvdGhlbWUtZW5naW5lcyc7XG5pbXBvcnQge0F1dG9tYXRpb25Nb2RlfSBmcm9tICcuL3V0aWxzL2F1dG9tYXRpb24nO1xuaW1wb3J0IHR5cGUge1BhcnNlZENvbG9yU2NoZW1lQ29uZmlnfSBmcm9tICcuL3V0aWxzL2NvbG9yc2NoZW1lLXBhcnNlcic7XG5pbXBvcnQge2lzTWFjT1MsIGlzV2luZG93cywgaXNDU1NDb2xvclNjaGVtZVByb3BTdXBwb3J0ZWQsIGlzRWRnZSwgaXNNb2JpbGV9IGZyb20gJy4vdXRpbHMvcGxhdGZvcm0nO1xuXG5kZWNsYXJlIGNvbnN0IF9fQ0hST01JVU1fTVYzX186IGJvb2xlYW47XG5kZWNsYXJlIGNvbnN0IF9fUExVU19fOiBib29sZWFuO1xuXG5leHBvcnQgY29uc3QgREVGQVVMVF9DT0xPUlMgPSB7XG4gICAgZGFya1NjaGVtZToge1xuICAgICAgICBiYWNrZ3JvdW5kOiAnIzE4MWExYicsXG4gICAgICAgIHRleHQ6ICcjZThlNmUzJyxcbiAgICB9LFxuICAgIGxpZ2h0U2NoZW1lOiB7XG4gICAgICAgIGJhY2tncm91bmQ6ICcjZGNkYWQ3JyxcbiAgICAgICAgdGV4dDogJyMxODFhMWInLFxuICAgIH0sXG59O1xuXG5leHBvcnQgY29uc3QgREVGQVVMVF9USEVNRTogVGhlbWUgPSB7XG4gICAgbW9kZTogMSxcbiAgICBicmlnaHRuZXNzOiAxMDAsXG4gICAgY29udHJhc3Q6IDEwMCxcbiAgICBncmF5c2NhbGU6IDAsXG4gICAgc2VwaWE6IDAsXG4gICAgdXNlRm9udDogZmFsc2UsXG4gICAgZm9udEZhbWlseTogaXNNYWNPUyA/ICdIZWx2ZXRpY2EgTmV1ZScgOiBpc1dpbmRvd3MgPyAnU2Vnb2UgVUknIDogJ09wZW4gU2FucycsXG4gICAgdGV4dFN0cm9rZTogMCxcbiAgICBlbmdpbmU6IFRoZW1lRW5naW5lLmR5bmFtaWNUaGVtZSxcbiAgICBzdHlsZXNoZWV0OiAnJyxcbiAgICBkYXJrU2NoZW1lQmFja2dyb3VuZENvbG9yOiBERUZBVUxUX0NPTE9SUy5kYXJrU2NoZW1lLmJhY2tncm91bmQsXG4gICAgZGFya1NjaGVtZVRleHRDb2xvcjogREVGQVVMVF9DT0xPUlMuZGFya1NjaGVtZS50ZXh0LFxuICAgIGxpZ2h0U2NoZW1lQmFja2dyb3VuZENvbG9yOiBERUZBVUxUX0NPTE9SUy5saWdodFNjaGVtZS5iYWNrZ3JvdW5kLFxuICAgIGxpZ2h0U2NoZW1lVGV4dENvbG9yOiBERUZBVUxUX0NPTE9SUy5saWdodFNjaGVtZS50ZXh0LFxuICAgIHNjcm9sbGJhckNvbG9yOiAnJyxcbiAgICBzZWxlY3Rpb25Db2xvcjogJ2F1dG8nLFxuICAgIHN0eWxlU3lzdGVtQ29udHJvbHM6IF9fQ0hST01JVU1fTVYzX18gPyBmYWxzZSA6ICFpc0NTU0NvbG9yU2NoZW1lUHJvcFN1cHBvcnRlZCxcbiAgICBsaWdodENvbG9yU2NoZW1lOiAnRGVmYXVsdCcsXG4gICAgZGFya0NvbG9yU2NoZW1lOiAnRGVmYXVsdCcsXG4gICAgaW1tZWRpYXRlTW9kaWZ5OiBmYWxzZSxcbn07XG5cbmlmIChfX1BMVVNfXykge1xuICAgIGV4dGVuZFRoZW1lRGVmYXVsdHMoREVGQVVMVF9USEVNRSk7XG59XG5cbmV4cG9ydCBjb25zdCBERUZBVUxUX0NPTE9SU0NIRU1FOiBQYXJzZWRDb2xvclNjaGVtZUNvbmZpZyA9IHtcbiAgICBsaWdodDoge1xuICAgICAgICBEZWZhdWx0OiB7XG4gICAgICAgICAgICBiYWNrZ3JvdW5kQ29sb3I6IERFRkFVTFRfQ09MT1JTLmxpZ2h0U2NoZW1lLmJhY2tncm91bmQsXG4gICAgICAgICAgICB0ZXh0Q29sb3I6IERFRkFVTFRfQ09MT1JTLmxpZ2h0U2NoZW1lLnRleHQsXG4gICAgICAgIH0sXG4gICAgfSxcbiAgICBkYXJrOiB7XG4gICAgICAgIERlZmF1bHQ6IHtcbiAgICAgICAgICAgIGJhY2tncm91bmRDb2xvcjogREVGQVVMVF9DT0xPUlMuZGFya1NjaGVtZS5iYWNrZ3JvdW5kLFxuICAgICAgICAgICAgdGV4dENvbG9yOiBERUZBVUxUX0NPTE9SUy5kYXJrU2NoZW1lLnRleHQsXG4gICAgICAgIH0sXG4gICAgfSxcbn07XG5cbmNvbnN0IGZpbHRlck1vZGVTaXRlcyA9IFtcbiAgICAnKi5vZmZpY2VhcHBzLmxpdmUuY29tJyxcbiAgICAnKi5zaGFyZXBvaW50LmNvbScsXG4gICAgJ2RvY3MuZ29vZ2xlLmNvbScsXG4gICAgJ29uZWRyaXZlLmxpdmUuY29tJyxcbl07XG5cbmV4cG9ydCBjb25zdCBERUZBVUxUX1NFVFRJTkdTOiBVc2VyU2V0dGluZ3MgPSB7XG4gICAgc2NoZW1lVmVyc2lvbjogMCxcbiAgICBlbmFibGVkOiB0cnVlLFxuICAgIGZldGNoTmV3czogdHJ1ZSxcbiAgICB0aGVtZTogREVGQVVMVF9USEVNRSxcbiAgICBwcmVzZXRzOiBbXSxcbiAgICBjdXN0b21UaGVtZXM6IGZpbHRlck1vZGVTaXRlcy5tYXAoKHVybCkgPT4ge1xuICAgICAgICBjb25zdCBlbmdpbmU6IFRoZW1lRW5naW5lID0gVGhlbWVFbmdpbmUuY3NzRmlsdGVyO1xuICAgICAgICByZXR1cm4ge1xuICAgICAgICAgICAgdXJsOiBbdXJsXSxcbiAgICAgICAgICAgIHRoZW1lOiB7Li4uREVGQVVMVF9USEVNRSwgZW5naW5lfSxcbiAgICAgICAgICAgIGJ1aWx0SW46IHRydWUsXG4gICAgICAgIH07XG4gICAgfSksXG4gICAgZW5hYmxlZEJ5RGVmYXVsdDogdHJ1ZSxcbiAgICBlbmFibGVkRm9yOiBbXSxcbiAgICBkaXNhYmxlZEZvcjogW10sXG4gICAgY2hhbmdlQnJvd3NlclRoZW1lOiBmYWxzZSxcbiAgICBzeW5jU2V0dGluZ3M6IHRydWUsXG4gICAgc3luY1NpdGVzRml4ZXM6IGZhbHNlLFxuICAgIGF1dG9tYXRpb246IHtcbiAgICAgICAgZW5hYmxlZDogaXNFZGdlICYmIGlzTW9iaWxlID8gdHJ1ZSA6IGZhbHNlLFxuICAgICAgICBtb2RlOiBpc0VkZ2UgJiYgaXNNb2JpbGUgPyBBdXRvbWF0aW9uTW9kZS5TWVNURU0gOiBBdXRvbWF0aW9uTW9kZS5OT05FLFxuICAgICAgICBiZWhhdmlvcjogJ09uT2ZmJyxcbiAgICB9LFxuICAgIHRpbWU6IHtcbiAgICAgICAgYWN0aXZhdGlvbjogJzE4OjAwJyxcbiAgICAgICAgZGVhY3RpdmF0aW9uOiAnOTowMCcsXG4gICAgfSxcbiAgICBsb2NhdGlvbjoge1xuICAgICAgICBsYXRpdHVkZTogbnVsbCxcbiAgICAgICAgbG9uZ2l0dWRlOiBudWxsLFxuICAgIH0sXG4gICAgcHJldmlld05ld0Rlc2lnbjogZmFsc2UsXG4gICAgcHJldmlld05ld2VzdERlc2lnbjogZmFsc2UsXG4gICAgZW5hYmxlRm9yUERGOiB0cnVlLFxuICAgIGVuYWJsZUZvclByb3RlY3RlZFBhZ2VzOiBmYWxzZSxcbiAgICBlbmFibGVDb250ZXh0TWVudXM6IGZhbHNlLFxuICAgIGRldGVjdERhcmtUaGVtZTogdHJ1ZSxcbn07XG4iLCIvLyBTZXBlcmF0b3IgaXMgdG8gaW5kaWNhdGUgdGhhdCB0aGUgaXQgc2hvdWxkIHN0YXJ0IHdpdGggYSBuZXcgZGVmaW5lZCBjb2xvcnNjaGVtZS5cbmNvbnN0IFNFUEVSQVRPUiA9ICc9Jy5yZXBlYXQoMzIpO1xuXG4vLyBKdXN0IGEgZmV3IGNvbnN0YW50cyB0byBtYWtlIHRoZSBjb2RlIG1vcmUgcmVhZGFibGUuXG5jb25zdCBiYWNrZ3JvdW5kUHJvcGVydHlMZW5ndGggPSAnYmFja2dyb3VuZDogJy5sZW5ndGg7XG5jb25zdCB0ZXh0UHJvcGVydHlMZW5ndGggPSAndGV4dDogJy5sZW5ndGg7XG5cbi8vIFNob3VsZCByZXR1cm4gYSBodW1hbml6ZWQgdmVyc2lvbiBvZiB0aGUgZ2l2ZW4gbnVtYmVyLlxuLy8gRm9yIGV4YW1wbGU6XG4vLyBodW1hbml6ZU51bWJlcigwKSA9PiAnMCdcbi8vIGh1bWFuaXplTnVtYmVyKDEpID0+ICcxc3QnXG4vLyBodW1hbml6ZU51bWJlcigyKSA9PiAnMm5kJ1xuLy8gaHVtYW5pemVOdW1iZXIoMykgPT4gJzNyZCdcbi8vIGh1bWFuaXplTnVtYmVyKDQpID0+ICc0dGgnXG4vLyBUT0RPKEFudG9uKTogcmV3cml0ZSBtZSB3aXRoIGNhc2UtZGVmYXVsdFxuLy8gZXNsaW50LWRpc2FibGUtbmV4dC1saW5lXG4vLyBAdHMtaWdub3JlXG5jb25zdCBodW1hbml6ZU51bWJlciA9IChudW1iZXI6IG51bWJlcik6IHN0cmluZyA9PiB7XG4gICAgaWYgKG51bWJlciA+IDMpIHtcbiAgICAgICAgcmV0dXJuIGAke251bWJlcn10aGA7XG4gICAgfVxuICAgIHN3aXRjaCAobnVtYmVyKSB7XG4gICAgICAgIGNhc2UgMDpcbiAgICAgICAgICAgIHJldHVybiAnMCc7XG4gICAgICAgIGNhc2UgMTpcbiAgICAgICAgICAgIHJldHVybiAnMXN0JztcbiAgICAgICAgY2FzZSAyOlxuICAgICAgICAgICAgcmV0dXJuICcybmQnO1xuICAgICAgICBjYXNlIDM6XG4gICAgICAgICAgICByZXR1cm4gJzNyZCc7XG4gICAgfVxufTtcblxuLy8gU2hvdWxkIHJldHVybiBpZiB0aGUgZ2l2ZW4gc3RyaW5nIGlzIGEgdmFsaWQgMyBvciA2IGRpZ2l0IGhleCBjb2xvci5cbmNvbnN0IGlzVmFsaWRIZXhDb2xvciA9IChjb2xvcjogc3RyaW5nKTogYm9vbGVhbiA9PiB7XG4gICAgcmV0dXJuIC9eIyhbMC05YS1mQS1GXXszfSl7MSwyfSQvLnRlc3QoY29sb3IpO1xufTtcblxuaW50ZXJmYWNlIENvbG9yU2NoZW1lVmFyaWFudCB7XG4gICAgLy8gVGhlIGJhY2tncm91bmQgY29sb3Igb2YgdGhlIGNvbG9yIHNjaGVtZSBpbiBoZXggZm9ybWF0LlxuICAgIGJhY2tncm91bmRDb2xvcjogc3RyaW5nO1xuICAgIC8vIFRoZSB0ZXh0IGNvbG9yIG9mIHRoZSBjb2xvciBzY2hlbWUgaW4gaGV4IGZvcm1hdC5cbiAgICB0ZXh0Q29sb3I6IHN0cmluZztcbn1cblxuZXhwb3J0IGludGVyZmFjZSBQYXJzZWRDb2xvclNjaGVtZUNvbmZpZyB7XG4gICAgLy8gQWxsIGRlZmluZWQgbGlnaHQgY29sb3Igc2NoZW1lcy5cbiAgICBsaWdodDogeyBbbmFtZTogc3RyaW5nXTogQ29sb3JTY2hlbWVWYXJpYW50IH07XG4gICAgLy8gQWxsIGRlZmluZWQgZGFyayBjb2xvciBzY2hlbWVzLlxuICAgIGRhcms6IHsgW25hbWU6IHN0cmluZ106IENvbG9yU2NoZW1lVmFyaWFudCB9O1xufVxuXG5leHBvcnQgZnVuY3Rpb24gcGFyc2VDb2xvclNjaGVtZUNvbmZpZyhjb25maWc6IHN0cmluZyk6IHsgcmVzdWx0OiBQYXJzZWRDb2xvclNjaGVtZUNvbmZpZzsgZXJyb3I6IHN0cmluZyB8IG51bGwgfSB7XG4gICAgLy8gTGV0J3MgZmlyc3QgZ2V0IGFsbCBcInBvc3NpYmxlXCIgc2VjdGlvbnMgb2YgdGhlIHRleHQuXG4gICAgLy8gV2UncmUgYWRkaW5nIGBcXG5gIHNvIHRoZSBzZWN0aW9ucyBcImZpcnN0XCIgd29yZCBpcyB0aGVcbiAgICAvLyBuYW1lIG9mIHRoZSBjb2xvciBzY2hlbWUuIFdlIGNvdWxkIHJlbW92ZSB0aGlzIGFuZFxuICAgIC8vIHNraXAgdGhpcyBpbiB0aGUgcHJvY2VzcyBvZiBwYXJzaW5nLCBidXQgYmVjYXVzZVxuICAgIC8vIHRoZSBmaXJzdCBlbnRyeSB3aWxsIG5vdCBoYXZlIHRoaXMgZmlyc3QgJ1xcbicgaXQgd2lsbFxuICAgIC8vIGJlIG1vcmUgY29tcGxpY2F0ZWQgdG8gb3RoZXJ3aXNlIGp1c3QgYWRkIHRoaXMgJ1xcbicgaGVyZS5cbiAgICBjb25zdCBzZWN0aW9ucyA9IGNvbmZpZy5zcGxpdChgJHtTRVBFUkFUT1IgfVxcblxcbmApO1xuXG4gICAgY29uc3QgZGVmaW5lZENvbG9yU2NoZW1lTmFtZXM6IFNldDxzdHJpbmc+ID0gbmV3IFNldCgpO1xuICAgIGxldCBsYXN0RGVmaW5lZENvbG9yU2NoZW1lTmFtZTogc3RyaW5nIHwgdW5kZWZpbmVkID0gJyc7XG5cbiAgICBjb25zdCBkZWZpbmVkQ29sb3JTY2hlbWVzOiBQYXJzZWRDb2xvclNjaGVtZUNvbmZpZyA9IHtcbiAgICAgICAgbGlnaHQ6IHt9LFxuICAgICAgICBkYXJrOiB7fSxcbiAgICB9O1xuXG4gICAgLy8gRGVmaW5lIHRoZSBpbnRlcnJ1cHQgYW5kIGVycm9yIHZhcmlhYmxlcy5cbiAgICAvLyBJbnRlcnJ1cHQgaXMgdG8gaW5kaWNhdGUgdGhhdCB0aGUgcGFyc2luZyBzaG91bGQgc3RvcC5cbiAgICAvLyBCdXQgYmVjYXVzZSB3ZSBjYW5ub3QgYnJlYWsgb3V0IG9mIGEgZm9yRWFjaCBsb29wLFxuICAgIC8vIHdlIG5lZWQgdG8gdXNlIGFuIGludGVycnVwdCB2YXJpYWJsZS5cbiAgICAvLyBUaGUgZXJyb3IgaXMgdG8gaW5kaWNhdGUgdGhhdCB0aGVyZSB3YXMgYW4gZXJyb3IuXG4gICAgLy8gQW5kIGFsc28gdGhlIHJlYXNvbiB3aHkgdGhlIHBhcnNpbmcgZmFpbGVkLlxuICAgIC8vIEl0IHdpbGwgYmUgdGhlIGZpcnN0IGVycm9yIHRoYXQgaXMgZm91bmQuXG4gICAgbGV0IGludGVycnVwdCA9IGZhbHNlO1xuICAgIGxldCBlcnJvcjogc3RyaW5nIHwgbnVsbCA9IG51bGw7XG5cbiAgICBjb25zdCB0aHJvd0Vycm9yID0gKG1lc3NhZ2U6IHN0cmluZykgPT4ge1xuICAgICAgICBpZiAoIWludGVycnVwdCkge1xuICAgICAgICAgICAgaW50ZXJydXB0ID0gdHJ1ZTtcbiAgICAgICAgICAgIGVycm9yID0gbWVzc2FnZTtcbiAgICAgICAgfVxuICAgIH07XG5cbiAgICAvLyBOb3cgd2Ugd2lsbCBpdGVyYXRlIHRyb3VnaG91dCBlYWNoIHNlY3Rpb24uXG4gICAgLy8gV2Ugd2lsbCBhbHdheXMgYXNzdW1lIGJhZC1mYWl0aCBhbmQgbWFrZSBzdXJlIHRvIGhhdmVcbiAgICAvLyBndWFyZHMgaW4gcGxhY2UuIEFzIHRoaXMgY291bGQgYWxzbyBiZSBiYWQgY29kZS5cbiAgICAvLyBXZSBzaG91bGRuJ3QgcmVseSBvbiB0aGF0IHRoZSBpbnB1dCBpcyBjb3JyZWN0LlxuICAgIHNlY3Rpb25zLmZvckVhY2goKHNlY3Rpb24pID0+IHtcbiAgICAgICAgLy8gQ2hlY2sgaWYgdGhlIGludGVycnVwdCB2YXJpYWJsZSBpcyBzZXQuXG4gICAgICAgIC8vIElmIGl0IGlzLCB3ZSBzaG91bGQgc3RvcCBwYXJzaW5nLlxuICAgICAgICBpZiAoaW50ZXJydXB0KSB7XG4gICAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cblxuICAgICAgICAvLyBGaXJzdCB3ZSBzcGxpdCB0aGUgc2VjdGlvbiBpbnRvIGxpbmVzLlxuICAgICAgICBjb25zdCBsaW5lcyA9IHNlY3Rpb24uc3BsaXQoJ1xcbicpO1xuXG4gICAgICAgIC8vIFdlIGhhdmUgdG8gbWFrZSBzdXJlIHRoYXQgdGhlIGZpcnN0IGxpbmUgaXMgYSB2YWxpZCBjb2xvciBzY2hlbWUgbmFtZS5cbiAgICAgICAgLy8gV2Ugd2lsbCBhbHNvIG1ha2Ugc3VyZSB0aGF0IHRoZSBuYW1lIGlzIG5vdCBhbHJlYWR5IGRlZmluZWQuXG4gICAgICAgIGNvbnN0IG5hbWUgPSBsaW5lc1swXTtcbiAgICAgICAgaWYgKCFuYW1lKSB7XG4gICAgICAgICAgICB0aHJvd0Vycm9yKCdObyBjb2xvciBzY2hlbWUgbmFtZSB3YXMgZm91bmQuJyk7XG4gICAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cbiAgICAgICAgaWYgKGRlZmluZWRDb2xvclNjaGVtZU5hbWVzLmhhcyhuYW1lKSkge1xuICAgICAgICAgICAgdGhyb3dFcnJvcihgVGhlIGNvbG9yIHNjaGVtZSBuYW1lIFwiJHtuYW1lfVwiIGlzIGFscmVhZHkgZGVmaW5lZC5gKTtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuICAgICAgICAvLyBDaGVjayBpZiB0aGUgbmFtZSBpcyBvbiBhbHBoYWJldGljYWwgb3JkZXIuXG4gICAgICAgIGlmIChsYXN0RGVmaW5lZENvbG9yU2NoZW1lTmFtZSAmJiBsYXN0RGVmaW5lZENvbG9yU2NoZW1lTmFtZSAhPT0gJ0RlZmF1bHQnICYmIG5hbWUubG9jYWxlQ29tcGFyZShsYXN0RGVmaW5lZENvbG9yU2NoZW1lTmFtZSkgPCAwKSB7XG4gICAgICAgICAgICB0aHJvd0Vycm9yKGBUaGUgY29sb3Igc2NoZW1lIG5hbWUgXCIke25hbWV9XCIgaXMgbm90IGluIGFscGhhYmV0aWNhbCBvcmRlci5gKTtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuICAgICAgICBsYXN0RGVmaW5lZENvbG9yU2NoZW1lTmFtZSA9IG5hbWU7XG5cbiAgICAgICAgLy8gQWRkIHRoZSBuYW1lIHRvIHRoZSBzZXQgb2YgZGVmaW5lZCBjb2xvciBzY2hlbWUgbmFtZXMuXG4gICAgICAgIGRlZmluZWRDb2xvclNjaGVtZU5hbWVzLmFkZChuYW1lKTtcblxuICAgICAgICAvLyBDaGVjayBpZiBsaW5lWzFdIGlzIGVtcHR5LCB3aGljaCBpcyBtdXN0IGJlLlxuICAgICAgICBpZiAobGluZXNbMV0pIHtcbiAgICAgICAgICAgIHRocm93RXJyb3IoYFRoZSBzZWNvbmQgbGluZSBvZiB0aGUgY29sb3Igc2NoZW1lIFwiJHtuYW1lfVwiIGlzIG5vdCBlbXB0eS5gKTtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuXG4gICAgICAgIGNvbnN0IGNoZWNrVmFyaWFudCA9IChsaW5lSW5kZXg6IG51bWJlciwgaXNTZWNvbmRWYXJpYW50OiBib29sZWFuKTogKENvbG9yU2NoZW1lVmFyaWFudCAmIHsgdmFyaWFudD86IHN0cmluZyB9KSB8IHVuZGVmaW5lZCA9PiB7XG4gICAgICAgICAgICAvLyBHZXQgdGhlIHBvc3NpYmxlIHZhcmlhbnQgbmFtZS5cbiAgICAgICAgICAgIGNvbnN0IHZhcmlhbnQgPSBsaW5lc1tsaW5lSW5kZXhdO1xuICAgICAgICAgICAgaWYgKCF2YXJpYW50KSB7XG4gICAgICAgICAgICAgICAgdGhyb3dFcnJvcihgVGhlIHRoaXJkIGxpbmUgb2YgdGhlIGNvbG9yIHNjaGVtZSBcIiR7bmFtZX1cIiBpcyBub3QgZGVmaW5lZC5gKTtcbiAgICAgICAgICAgICAgICByZXR1cm47XG4gICAgICAgICAgICB9XG5cbiAgICAgICAgICAgIC8vIENoZWNrIGlmIHRoZSB2YXJpYW50IGlzIHZhbGlkLlxuICAgICAgICAgICAgLy8gaWYgaXNTZWNvbmRWYXJpYW50IGlzIHRydWUsIHRoZW4gd2Ugd2lsbCBjaGVjayBpZiB0aGUgdmFyaWFudCBpcyAnTGlnaHQnLCAnRGFyaycgaXMgbm90IGNvbnNpZGVyZWQgdmFsaWQuXG4gICAgICAgICAgICBpZiAodmFyaWFudCAhPT0gJ0xJR0hUJyAmJiB2YXJpYW50ICE9PSAnREFSSycgJiYgKGlzU2Vjb25kVmFyaWFudCAmJiB2YXJpYW50ID09PSAnTGlnaHQnKSkge1xuICAgICAgICAgICAgICAgIHRocm93RXJyb3IoYFRoZSAke2h1bWFuaXplTnVtYmVyKGxpbmVJbmRleCl9IGxpbmUgb2YgdGhlIGNvbG9yIHNjaGVtZSBcIiR7bmFtZX1cIiBpcyBub3QgYSB2YWxpZCB2YXJpYW50LmApO1xuICAgICAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgICAgIH1cblxuICAgICAgICAgICAgLy8gR2V0IHRoZSBwb3NzaWJsZSBiYWNrZ3JvdW5kIGNvbG9yLlxuICAgICAgICAgICAgY29uc3QgZmlyc3RQcm9wZXJ0eSA9IGxpbmVzW2xpbmVJbmRleCArIDFdO1xuICAgICAgICAgICAgaWYgKCFmaXJzdFByb3BlcnR5KSB7XG4gICAgICAgICAgICAgICAgdGhyb3dFcnJvcihgVGhlICR7aHVtYW5pemVOdW1iZXIobGluZUluZGV4ICsgMSl9IGxpbmUgb2YgdGhlIGNvbG9yIHNjaGVtZSBcIiR7bmFtZX1cIiBpcyBub3QgZGVmaW5lZC5gKTtcbiAgICAgICAgICAgICAgICByZXR1cm47XG4gICAgICAgICAgICB9XG5cbiAgICAgICAgICAgIC8vIENoZWNrIGlmIHRoZSBwcm9wZXJ0eSBpcyBiYWNrZ3JvdW5kIGNvbG9yLlxuICAgICAgICAgICAgaWYgKCFmaXJzdFByb3BlcnR5LnN0YXJ0c1dpdGgoJ2JhY2tncm91bmQ6ICcpKSB7XG4gICAgICAgICAgICAgICAgdGhyb3dFcnJvcihgVGhlICR7aHVtYW5pemVOdW1iZXIobGluZUluZGV4ICsgMSl9IGxpbmUgb2YgdGhlIGNvbG9yIHNjaGVtZSBcIiR7bmFtZX1cIiBpcyBub3QgYmFja2dyb3VuZC1jb2xvciBwcm9wZXJ0eS5gKTtcbiAgICAgICAgICAgICAgICByZXR1cm47XG4gICAgICAgICAgICB9XG5cbiAgICAgICAgICAgIC8vIEdldCB0aGUgYmFja2dyb3VuZCBjb2xvciBhbmQgY2hlY2sgaWYgaXQgaXMgYSB2YWxpZCBoZXggY29sb3IuXG4gICAgICAgICAgICBjb25zdCBiYWNrZ3JvdW5kQ29sb3IgPSBmaXJzdFByb3BlcnR5LnNsaWNlKGJhY2tncm91bmRQcm9wZXJ0eUxlbmd0aCk7XG4gICAgICAgICAgICBpZiAoIWlzVmFsaWRIZXhDb2xvcihiYWNrZ3JvdW5kQ29sb3IpKSB7XG4gICAgICAgICAgICAgICAgdGhyb3dFcnJvcihgVGhlICR7aHVtYW5pemVOdW1iZXIobGluZUluZGV4ICsgMSl9IGxpbmUgb2YgdGhlIGNvbG9yIHNjaGVtZSBcIiR7bmFtZX1cIiBpcyBub3QgYSB2YWxpZCBoZXggY29sb3IuYCk7XG4gICAgICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICAgICAgfVxuXG4gICAgICAgICAgICAvLyBHZXQgdGhlIHBvc3NpYmxlIHRleHQgY29sb3IuXG4gICAgICAgICAgICBjb25zdCBzZWNvbmRQcm9wZXJ0eSA9IGxpbmVzW2xpbmVJbmRleCArIDJdO1xuICAgICAgICAgICAgaWYgKCFzZWNvbmRQcm9wZXJ0eSkge1xuICAgICAgICAgICAgICAgIHRocm93RXJyb3IoYFRoZSAke2h1bWFuaXplTnVtYmVyKGxpbmVJbmRleCArIDIpfSBsaW5lIG9mIHRoZSBjb2xvciBzY2hlbWUgXCIke25hbWV9XCIgaXMgbm90IGRlZmluZWQuYCk7XG4gICAgICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgLy8gQ2hlY2sgaWYgdGhlIHByb3BlcnR5IGlzIHRleHQgY29sb3IuXG4gICAgICAgICAgICBpZiAoIXNlY29uZFByb3BlcnR5LnN0YXJ0c1dpdGgoJ3RleHQ6ICcpKSB7XG4gICAgICAgICAgICAgICAgdGhyb3dFcnJvcihgVGhlICR7aHVtYW5pemVOdW1iZXIobGluZUluZGV4ICsgMil9IGxpbmUgb2YgdGhlIGNvbG9yIHNjaGVtZSBcIiR7bmFtZX1cIiBpcyBub3QgdGV4dC1jb2xvciBwcm9wZXJ0eS5gKTtcbiAgICAgICAgICAgICAgICByZXR1cm47XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICAvLyBHZXQgdGhlIHRleHQgY29sb3IgYW5kIGNoZWNrIGlmIGl0IGlzIGEgdmFsaWQgaGV4IGNvbG9yLlxuICAgICAgICAgICAgY29uc3QgdGV4dENvbG9yID0gc2Vjb25kUHJvcGVydHkuc2xpY2UodGV4dFByb3BlcnR5TGVuZ3RoKTtcbiAgICAgICAgICAgIGlmICghaXNWYWxpZEhleENvbG9yKHRleHRDb2xvcikpIHtcbiAgICAgICAgICAgICAgICB0aHJvd0Vycm9yKGBUaGUgJHtodW1hbml6ZU51bWJlcihsaW5lSW5kZXggKyAyKX0gbGluZSBvZiB0aGUgY29sb3Igc2NoZW1lIFwiJHtuYW1lfVwiIGlzIG5vdCBhIHZhbGlkIGhleCBjb2xvci5gKTtcbiAgICAgICAgICAgICAgICByZXR1cm47XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICAvLyBJZiB0aGUgdmFyaWFudCBpcyB0aGUgc2Vjb25kIHZhcmlhbnQsIHRoZW4gd2Ugd2lsbCByZXR1cm4gdGhlIHZhcmlhbnQgYW5kIHRoZSB2YXJpYW50IG5hbWUuXG4gICAgICAgICAgICByZXR1cm4ge1xuICAgICAgICAgICAgICAgIGJhY2tncm91bmRDb2xvcixcbiAgICAgICAgICAgICAgICB0ZXh0Q29sb3IsXG4gICAgICAgICAgICAgICAgdmFyaWFudCxcbiAgICAgICAgICAgIH07XG4gICAgICAgIH07XG5cbiAgICAgICAgY29uc3QgZmlyc3RWYXJpYW50ID0gY2hlY2tWYXJpYW50KDIsIGZhbHNlKSE7XG4gICAgICAgIGNvbnN0IGlzRmlyc3RWYXJpYW50TGlnaHQgPSBmaXJzdFZhcmlhbnQudmFyaWFudCA9PT0gJ0xJR0hUJztcbiAgICAgICAgZGVsZXRlIGZpcnN0VmFyaWFudC52YXJpYW50O1xuICAgICAgICAvLyBJZiB0aGUgaW50ZXJydXB0IHZhcmlhYmxlIGlzIHNldCwgd2Ugc2hvdWxkIHN0b3AgcGFyc2luZy5cbiAgICAgICAgaWYgKGludGVycnVwdCkge1xuICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICB9XG4gICAgICAgIGxldCBzZWNvbmRWYXJpYW50OiB0eXBlb2YgZmlyc3RWYXJpYW50IHwgbnVsbCA9IG51bGw7XG4gICAgICAgIGxldCBpc1NlY29uZFZhcmlhbnRMaWdodCA9IGZhbHNlO1xuICAgICAgICAvLyBDaGVjayBpZiB0aGUgN3RoIGxpbmUgaXMgZGVmaW5lZCBvdGhlcndpc2Ugd2Ugc2hvdWxkIHN0b3AgcGFyc2luZy5cbiAgICAgICAgaWYgKGxpbmVzWzZdKSB7XG4gICAgICAgICAgICBzZWNvbmRWYXJpYW50ID0gY2hlY2tWYXJpYW50KDYsIHRydWUpITtcbiAgICAgICAgICAgIGlzU2Vjb25kVmFyaWFudExpZ2h0ID0gc2Vjb25kVmFyaWFudC52YXJpYW50ID09PSAnTElHSFQnO1xuICAgICAgICAgICAgZGVsZXRlIHNlY29uZFZhcmlhbnQudmFyaWFudDtcbiAgICAgICAgICAgIC8vIElmIHRoZSBpbnRlcnJ1cHQgdmFyaWFibGUgaXMgc2V0LCB3ZSBzaG91bGQgc3RvcCBwYXJzaW5nLlxuICAgICAgICAgICAgaWYgKGludGVycnVwdCkge1xuICAgICAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIC8vIE11c3QgZW5kIHdpdGggMSBuZXcgbGluZSh0d28gVmFyaWFudHMpLlxuICAgICAgICAgICAgaWYgKGxpbmVzLmxlbmd0aCA+IDExIHx8IGxpbmVzWzldIHx8IGxpbmVzWzEwXSkge1xuICAgICAgICAgICAgICAgIHRocm93RXJyb3IoYFRoZSBjb2xvciBzY2hlbWUgXCIke25hbWV9XCIgZG9lc24ndCBlbmQgd2l0aCAxIG5ldyBsaW5lLmApO1xuICAgICAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfSBlbHNlIGlmIChsaW5lcy5sZW5ndGggPiA3KSB7XG4gICAgICAgICAgICB0aHJvd0Vycm9yKGBUaGUgY29sb3Igc2NoZW1lIFwiJHtuYW1lfVwiIGRvZXNuJ3QgZW5kIHdpdGggMSBuZXcgbGluZS5gKTtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuICAgICAgICBpZiAoc2Vjb25kVmFyaWFudCkge1xuICAgICAgICAgICAgaWYgKGlzRmlyc3RWYXJpYW50TGlnaHQgPT09IGlzU2Vjb25kVmFyaWFudExpZ2h0KSB7XG4gICAgICAgICAgICAgICAgdGhyb3dFcnJvcihgVGhlIGNvbG9yIHNjaGVtZSBcIiR7bmFtZX1cIiBoYXMgdGhlIHNhbWUgdmFyaWFudCB0d2ljZS5gKTtcbiAgICAgICAgICAgICAgICByZXR1cm47XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICBpZiAoaXNGaXJzdFZhcmlhbnRMaWdodCkge1xuICAgICAgICAgICAgICAgIGRlZmluZWRDb2xvclNjaGVtZXMubGlnaHRbbmFtZV0gPSBmaXJzdFZhcmlhbnQ7XG4gICAgICAgICAgICAgICAgZGVmaW5lZENvbG9yU2NoZW1lcy5kYXJrW25hbWVdID0gc2Vjb25kVmFyaWFudDtcbiAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgZGVmaW5lZENvbG9yU2NoZW1lcy5saWdodFtuYW1lXSA9IHNlY29uZFZhcmlhbnQ7XG4gICAgICAgICAgICAgICAgZGVmaW5lZENvbG9yU2NoZW1lcy5kYXJrW25hbWVdID0gZmlyc3RWYXJpYW50O1xuICAgICAgICAgICAgfVxuICAgICAgICB9IGVsc2UgaWYgKGlzRmlyc3RWYXJpYW50TGlnaHQpIHtcbiAgICAgICAgICAgIGRlZmluZWRDb2xvclNjaGVtZXMubGlnaHRbbmFtZV0gPSBmaXJzdFZhcmlhbnQ7XG4gICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICBkZWZpbmVkQ29sb3JTY2hlbWVzLmRhcmtbbmFtZV0gPSBmaXJzdFZhcmlhbnQ7XG4gICAgICAgIH1cbiAgICB9KTtcblxuICAgIHJldHVybiB7cmVzdWx0OiBkZWZpbmVkQ29sb3JTY2hlbWVzLCBlcnJvcjogZXJyb3J9O1xufVxuIiwiaW1wb3J0IHtERUZBVUxUX1NFVFRJTkdTLCBERUZBVUxUX1RIRU1FfSBmcm9tICcuLi9kZWZhdWx0cyc7XG5pbXBvcnQgdHlwZSB7VXNlclNldHRpbmdzLCBUaGVtZSwgVGhlbWVQcmVzZXQsIEN1c3RvbVNpdGVDb25maWcsIFRpbWVTZXR0aW5ncywgTG9jYXRpb25TZXR0aW5ncywgQXV0b21hdGlvbn0gZnJvbSAnLi4vZGVmaW5pdGlvbnMnO1xuXG5pbXBvcnQge0F1dG9tYXRpb25Nb2RlfSBmcm9tICcuL2F1dG9tYXRpb24nO1xuXG5mdW5jdGlvbiBpc0Jvb2xlYW4oeDogYW55KTogeCBpcyBib29sZWFuIHtcbiAgICByZXR1cm4gdHlwZW9mIHggPT09ICdib29sZWFuJztcbn1cblxuZnVuY3Rpb24gaXNQbGFpbk9iamVjdCh4OiBhbnkpOiB4IGlzIFJlY29yZDxzdHJpbmcsIHVua25vd24+IHtcbiAgICByZXR1cm4gdHlwZW9mIHggPT09ICdvYmplY3QnICYmIHggIT0gbnVsbCAmJiAhQXJyYXkuaXNBcnJheSh4KTtcbn1cblxuZnVuY3Rpb24gaXNBcnJheSh4OiBhbnkpIHtcbiAgICByZXR1cm4gQXJyYXkuaXNBcnJheSh4KTtcbn1cblxuZnVuY3Rpb24gaXNTdHJpbmcoeDogYW55KTogeCBpcyBzdHJpbmcge1xuICAgIHJldHVybiB0eXBlb2YgeCA9PT0gJ3N0cmluZyc7XG59XG5cbmZ1bmN0aW9uIGlzTm9uRW1wdHlTdHJpbmcoeDogYW55KTogeCBpcyBzdHJpbmcge1xuICAgIHJldHVybiB4ICYmIGlzU3RyaW5nKHgpO1xufVxuXG5mdW5jdGlvbiBpc05vbkVtcHR5QXJyYXlPZk5vbkVtcHR5U3RyaW5ncyh4OiBhbnkpOiB4IGlzIGFueVtdIHtcbiAgICByZXR1cm4gQXJyYXkuaXNBcnJheSh4KSAmJiB4Lmxlbmd0aCA+IDAgJiYgeC5ldmVyeSgocykgPT4gaXNOb25FbXB0eVN0cmluZyhzKSk7XG59XG5cbmZ1bmN0aW9uIGlzUmVnRXhwTWF0Y2gocmVnZXhwOiBSZWdFeHApIHtcbiAgICByZXR1cm4gKHg6IGFueSk6IHggaXMgc3RyaW5nID0+IHtcbiAgICAgICAgcmV0dXJuIGlzU3RyaW5nKHgpICYmIHgubWF0Y2gocmVnZXhwKSAhPSBudWxsO1xuICAgIH07XG59XG5cbmNvbnN0IGlzVGltZSA9IGlzUmVnRXhwTWF0Y2goL14oKDA/WzAtOV0pfCgxWzAtOV0pfCgyWzAtM10pKTooWzAtNV1bMC05XSkkLyk7XG5mdW5jdGlvbiBpc051bWJlcih4OiBhbnkpOiB4IGlzIG51bWJlciB7XG4gICAgcmV0dXJuIHR5cGVvZiB4ID09PSAnbnVtYmVyJyAmJiAhaXNOYU4oeCk7XG59XG5cbmZ1bmN0aW9uIGlzTnVtYmVyQmV0d2VlbihtaW46IG51bWJlciwgbWF4OiBudW1iZXIpIHtcbiAgICByZXR1cm4gKHg6IGFueSk6IHggaXMgbnVtYmVyID0+IHtcbiAgICAgICAgcmV0dXJuIGlzTnVtYmVyKHgpICYmIHggPj0gbWluICYmIHggPD0gbWF4O1xuICAgIH07XG59XG5cbmZ1bmN0aW9uIGlzT25lT2YoLi4udmFsdWVzOiBhbnlbXSkge1xuICAgIHJldHVybiAoeDogYW55KSA9PiB2YWx1ZXMuaW5jbHVkZXMoeCk7XG59XG5cbmZ1bmN0aW9uIGhhc1JlcXVpcmVkUHJvcGVydGllczxUIGV4dGVuZHMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4+KG9iajogVCwga2V5czogQXJyYXk8a2V5b2YgVD4pIHtcbiAgICByZXR1cm4ga2V5cy5ldmVyeSgoa2V5KSA9PiBvYmouaGFzT3duUHJvcGVydHkoa2V5KSk7XG59XG5cbmZ1bmN0aW9uIGNyZWF0ZVZhbGlkYXRvcigpIHtcbiAgICBjb25zdCBlcnJvcnM6IHN0cmluZ1tdID0gW107XG5cbiAgICBmdW5jdGlvbiB2YWxpZGF0ZVByb3BlcnR5PFQgZXh0ZW5kcyBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPj4ob2JqOiBULCBrZXk6IGtleW9mIFQsIHZhbGlkYXRvcjogKHg6IGFueSkgPT4gYm9vbGVhbiwgZmFsbGJhY2s6IFQpIHtcbiAgICAgICAgaWYgKCFvYmouaGFzT3duUHJvcGVydHkoa2V5KSB8fCB2YWxpZGF0b3Iob2JqW2tleV0pKSB7XG4gICAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cbiAgICAgICAgZXJyb3JzLnB1c2goYFVuZXhwZWN0ZWQgdmFsdWUgZm9yIFwiJHtrZXkgYXMgc3RyaW5nfVwiOiAke0pTT04uc3RyaW5naWZ5KG9ialtrZXldKX1gKTtcbiAgICAgICAgb2JqW2tleV0gPSBmYWxsYmFja1trZXldO1xuICAgIH1cblxuICAgIGZ1bmN0aW9uIHZhbGlkYXRlQXJyYXk8VCBleHRlbmRzIFJlY29yZDxzdHJpbmcsIHVua25vd24+LCBWPihvYmo6IFQsIGtleToga2V5b2YgVCwgdmFsaWRhdG9yOiAoeDogVikgPT4gYm9vbGVhbikge1xuICAgICAgICBpZiAoIW9iai5oYXNPd25Qcm9wZXJ0eShrZXkpKSB7XG4gICAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cbiAgICAgICAgY29uc3Qgd3JvbmdWYWx1ZXMgPSBuZXcgU2V0KCk7XG4gICAgICAgIGNvbnN0IGFycjogYW55W10gPSBvYmpba2V5XSBhcyBhbnk7XG4gICAgICAgIGZvciAobGV0IGkgPSAwOyBpIDwgYXJyLmxlbmd0aDsgaSsrKSB7XG4gICAgICAgICAgICBpZiAoIXZhbGlkYXRvcihhcnJbaV0pKSB7XG4gICAgICAgICAgICAgICAgd3JvbmdWYWx1ZXMuYWRkKGFycltpXSk7XG4gICAgICAgICAgICAgICAgYXJyLnNwbGljZShpLCAxKTtcbiAgICAgICAgICAgICAgICBpLS07XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgICAgaWYgKHdyb25nVmFsdWVzLnNpemUgPiAwKSB7XG4gICAgICAgICAgICBlcnJvcnMucHVzaChgQXJyYXkgXCIke2tleSBhcyBzdHJpbmd9XCIgaGFzIHdyb25nIHZhbHVlczogJHtBcnJheS5mcm9tKHdyb25nVmFsdWVzKS5tYXAoKHYpID0+IEpTT04uc3RyaW5naWZ5KHYpKS5qb2luKCc7ICcpfWApO1xuICAgICAgICB9XG4gICAgfVxuXG4gICAgcmV0dXJuIHt2YWxpZGF0ZVByb3BlcnR5LCB2YWxpZGF0ZUFycmF5LCBlcnJvcnN9O1xufVxuXG5pbnRlcmZhY2UgU2V0dGluZ1ZhbGlkYXRpb25SZXN1bHQge1xuICAgIHNldHRpbmdzOiBQYXJ0aWFsPFVzZXJTZXR0aW5ncz47XG4gICAgZXJyb3JzOiBzdHJpbmdbXTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIHZhbGlkYXRlU2V0dGluZ3Moc2V0dGluZ3M6IFBhcnRpYWw8VXNlclNldHRpbmdzPik6IFNldHRpbmdWYWxpZGF0aW9uUmVzdWx0IHtcbiAgICBpZiAoIWlzUGxhaW5PYmplY3Qoc2V0dGluZ3MpKSB7XG4gICAgICAgIHJldHVybiB7ZXJyb3JzOiBbJ1NldHRpbmdzIGFyZSBub3QgYSBwbGFpbiBvYmplY3QnXSwgc2V0dGluZ3M6IERFRkFVTFRfU0VUVElOR1N9O1xuICAgIH1cblxuICAgIGNvbnN0IHt2YWxpZGF0ZVByb3BlcnR5LCB2YWxpZGF0ZUFycmF5LCBlcnJvcnN9ID0gY3JlYXRlVmFsaWRhdG9yKCk7XG4gICAgY29uc3QgaXNWYWxpZFByZXNldFRoZW1lID0gKHRoZW1lOiBUaGVtZSkgPT4ge1xuICAgICAgICBpZiAoIWlzUGxhaW5PYmplY3QodGhlbWUpKSB7XG4gICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgIH1cbiAgICAgICAgY29uc3Qge2Vycm9yczogdGhlbWVFcnJvcnN9ID0gdmFsaWRhdGVUaGVtZSh0aGVtZSk7XG4gICAgICAgIHJldHVybiB0aGVtZUVycm9ycy5sZW5ndGggPT09IDA7XG4gICAgfTtcblxuICAgIHZhbGlkYXRlUHJvcGVydHkoc2V0dGluZ3MsICdzY2hlbWVWZXJzaW9uJywgaXNOdW1iZXIsIERFRkFVTFRfU0VUVElOR1MpO1xuXG4gICAgdmFsaWRhdGVQcm9wZXJ0eShzZXR0aW5ncywgJ2VuYWJsZWQnLCBpc0Jvb2xlYW4sIERFRkFVTFRfU0VUVElOR1MpO1xuICAgIHZhbGlkYXRlUHJvcGVydHkoc2V0dGluZ3MsICdmZXRjaE5ld3MnLCBpc0Jvb2xlYW4sIERFRkFVTFRfU0VUVElOR1MpO1xuXG4gICAgdmFsaWRhdGVQcm9wZXJ0eShzZXR0aW5ncywgJ3RoZW1lJywgaXNQbGFpbk9iamVjdCwgREVGQVVMVF9TRVRUSU5HUyk7XG4gICAgY29uc3Qge2Vycm9yczogdGhlbWVFcnJvcnN9ID0gdmFsaWRhdGVUaGVtZShzZXR0aW5ncy50aGVtZSk7XG4gICAgZXJyb3JzLnB1c2goLi4udGhlbWVFcnJvcnMpO1xuXG4gICAgdmFsaWRhdGVQcm9wZXJ0eShzZXR0aW5ncywgJ3ByZXNldHMnLCBpc0FycmF5LCBERUZBVUxUX1NFVFRJTkdTKTtcbiAgICB2YWxpZGF0ZUFycmF5KHNldHRpbmdzLCAncHJlc2V0cycsIChwcmVzZXQ6IFRoZW1lUHJlc2V0KSA9PiB7XG4gICAgICAgIGNvbnN0IHByZXNldFZhbGlkYXRvciA9IGNyZWF0ZVZhbGlkYXRvcigpO1xuICAgICAgICBpZiAoIShpc1BsYWluT2JqZWN0KHByZXNldCkgJiYgaGFzUmVxdWlyZWRQcm9wZXJ0aWVzKHByZXNldCwgWydpZCcsICduYW1lJywgJ3VybHMnLCAndGhlbWUnXSkpKSB7XG4gICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgIH1cbiAgICAgICAgcHJlc2V0VmFsaWRhdG9yLnZhbGlkYXRlUHJvcGVydHkocHJlc2V0LCAnaWQnLCBpc05vbkVtcHR5U3RyaW5nLCBwcmVzZXQpO1xuICAgICAgICBwcmVzZXRWYWxpZGF0b3IudmFsaWRhdGVQcm9wZXJ0eShwcmVzZXQsICduYW1lJywgaXNOb25FbXB0eVN0cmluZywgcHJlc2V0KTtcbiAgICAgICAgcHJlc2V0VmFsaWRhdG9yLnZhbGlkYXRlUHJvcGVydHkocHJlc2V0LCAndXJscycsIGlzTm9uRW1wdHlBcnJheU9mTm9uRW1wdHlTdHJpbmdzLCBwcmVzZXQpO1xuICAgICAgICBwcmVzZXRWYWxpZGF0b3IudmFsaWRhdGVQcm9wZXJ0eShwcmVzZXQsICd0aGVtZScsIGlzVmFsaWRQcmVzZXRUaGVtZSwgcHJlc2V0KTtcbiAgICAgICAgcmV0dXJuIHByZXNldFZhbGlkYXRvci5lcnJvcnMubGVuZ3RoID09PSAwO1xuICAgIH0pO1xuXG4gICAgdmFsaWRhdGVQcm9wZXJ0eShzZXR0aW5ncywgJ2N1c3RvbVRoZW1lcycsIGlzQXJyYXksIERFRkFVTFRfU0VUVElOR1MpO1xuICAgIHZhbGlkYXRlQXJyYXkoc2V0dGluZ3MsICdjdXN0b21UaGVtZXMnLCAoY3VzdG9tOiBDdXN0b21TaXRlQ29uZmlnKSA9PiB7XG4gICAgICAgIGlmICghKGlzUGxhaW5PYmplY3QoY3VzdG9tKSAmJiBoYXNSZXF1aXJlZFByb3BlcnRpZXMoY3VzdG9tLCBbJ3VybCcsICd0aGVtZSddKSkpIHtcbiAgICAgICAgICAgIHJldHVybiBmYWxzZTtcbiAgICAgICAgfVxuICAgICAgICBjb25zdCBwcmVzZXRWYWxpZGF0b3IgPSBjcmVhdGVWYWxpZGF0b3IoKTtcbiAgICAgICAgcHJlc2V0VmFsaWRhdG9yLnZhbGlkYXRlUHJvcGVydHkoY3VzdG9tLCAndXJsJywgaXNOb25FbXB0eUFycmF5T2ZOb25FbXB0eVN0cmluZ3MsIGN1c3RvbSk7XG4gICAgICAgIHByZXNldFZhbGlkYXRvci52YWxpZGF0ZVByb3BlcnR5KGN1c3RvbSwgJ3RoZW1lJywgaXNWYWxpZFByZXNldFRoZW1lLCBjdXN0b20pO1xuICAgICAgICByZXR1cm4gcHJlc2V0VmFsaWRhdG9yLmVycm9ycy5sZW5ndGggPT09IDA7XG4gICAgfSk7XG5cbiAgICB2YWxpZGF0ZVByb3BlcnR5KHNldHRpbmdzLCAnZW5hYmxlZEZvcicsIGlzQXJyYXksIERFRkFVTFRfU0VUVElOR1MpO1xuICAgIHZhbGlkYXRlQXJyYXkoc2V0dGluZ3MsICdlbmFibGVkRm9yJywgaXNOb25FbXB0eVN0cmluZyk7XG4gICAgdmFsaWRhdGVQcm9wZXJ0eShzZXR0aW5ncywgJ2Rpc2FibGVkRm9yJywgaXNBcnJheSwgREVGQVVMVF9TRVRUSU5HUyk7XG4gICAgdmFsaWRhdGVBcnJheShzZXR0aW5ncywgJ2Rpc2FibGVkRm9yJywgaXNOb25FbXB0eVN0cmluZyk7XG5cbiAgICB2YWxpZGF0ZVByb3BlcnR5KHNldHRpbmdzLCAnZW5hYmxlZEJ5RGVmYXVsdCcsIGlzQm9vbGVhbiwgREVGQVVMVF9TRVRUSU5HUyk7XG4gICAgdmFsaWRhdGVQcm9wZXJ0eShzZXR0aW5ncywgJ2NoYW5nZUJyb3dzZXJUaGVtZScsIGlzQm9vbGVhbiwgREVGQVVMVF9TRVRUSU5HUyk7XG4gICAgdmFsaWRhdGVQcm9wZXJ0eShzZXR0aW5ncywgJ3N5bmNTZXR0aW5ncycsIGlzQm9vbGVhbiwgREVGQVVMVF9TRVRUSU5HUyk7XG4gICAgdmFsaWRhdGVQcm9wZXJ0eShzZXR0aW5ncywgJ3N5bmNTaXRlc0ZpeGVzJywgaXNCb29sZWFuLCBERUZBVUxUX1NFVFRJTkdTKTtcbiAgICB2YWxpZGF0ZVByb3BlcnR5KHNldHRpbmdzLCAnYXV0b21hdGlvbicsIChhdXRvbWF0aW9uOiBBdXRvbWF0aW9uKSA9PiB7XG4gICAgICAgIGlmICghaXNQbGFpbk9iamVjdChhdXRvbWF0aW9uKSkge1xuICAgICAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgICAgICB9XG5cbiAgICAgICAgY29uc3QgYXV0b21hdGlvblZhbGlkYXRvciA9IGNyZWF0ZVZhbGlkYXRvcigpO1xuICAgICAgICBhdXRvbWF0aW9uVmFsaWRhdG9yLnZhbGlkYXRlUHJvcGVydHkoYXV0b21hdGlvbiwgJ2VuYWJsZWQnLCBpc0Jvb2xlYW4sIGF1dG9tYXRpb24pO1xuICAgICAgICBhdXRvbWF0aW9uVmFsaWRhdG9yLnZhbGlkYXRlUHJvcGVydHkoYXV0b21hdGlvbiwgJ21vZGUnLCBpc09uZU9mKEF1dG9tYXRpb25Nb2RlLlNZU1RFTSwgQXV0b21hdGlvbk1vZGUuVElNRSwgQXV0b21hdGlvbk1vZGUuTE9DQVRJT04sIEF1dG9tYXRpb25Nb2RlLk5PTkUpLCBhdXRvbWF0aW9uKTtcbiAgICAgICAgYXV0b21hdGlvblZhbGlkYXRvci52YWxpZGF0ZVByb3BlcnR5KGF1dG9tYXRpb24sICdiZWhhdmlvcicsIGlzT25lT2YoJ09uT2ZmJywgJ1NjaGVtZScpLCBhdXRvbWF0aW9uKTtcbiAgICAgICAgcmV0dXJuIGF1dG9tYXRpb25WYWxpZGF0b3IuZXJyb3JzLmxlbmd0aCA9PT0gMDtcbiAgICB9LCBERUZBVUxUX1NFVFRJTkdTKTtcblxuICAgIHZhbGlkYXRlUHJvcGVydHkoc2V0dGluZ3MsIEF1dG9tYXRpb25Nb2RlLlRJTUUsICh0aW1lOiBUaW1lU2V0dGluZ3MpID0+IHtcbiAgICAgICAgaWYgKCFpc1BsYWluT2JqZWN0KHRpbWUpKSB7XG4gICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgIH1cbiAgICAgICAgY29uc3QgdGltZVZhbGlkYXRvciA9IGNyZWF0ZVZhbGlkYXRvcigpO1xuICAgICAgICB0aW1lVmFsaWRhdG9yLnZhbGlkYXRlUHJvcGVydHkodGltZSwgJ2FjdGl2YXRpb24nLCBpc1RpbWUsIHRpbWUpO1xuICAgICAgICB0aW1lVmFsaWRhdG9yLnZhbGlkYXRlUHJvcGVydHkodGltZSwgJ2RlYWN0aXZhdGlvbicsIGlzVGltZSwgdGltZSk7XG4gICAgICAgIHJldHVybiB0aW1lVmFsaWRhdG9yLmVycm9ycy5sZW5ndGggPT09IDA7XG4gICAgfSwgREVGQVVMVF9TRVRUSU5HUyk7XG5cbiAgICB2YWxpZGF0ZVByb3BlcnR5KHNldHRpbmdzLCBBdXRvbWF0aW9uTW9kZS5MT0NBVElPTiwgKGxvY2F0aW9uOiBMb2NhdGlvblNldHRpbmdzKSA9PiB7XG4gICAgICAgIGlmICghaXNQbGFpbk9iamVjdChsb2NhdGlvbikpIHtcbiAgICAgICAgICAgIHJldHVybiBmYWxzZTtcbiAgICAgICAgfVxuICAgICAgICBjb25zdCBsb2NWYWxpZGF0b3IgPSBjcmVhdGVWYWxpZGF0b3IoKTtcbiAgICAgICAgY29uc3QgaXNWYWxpZExvYyA9ICh4OiBhbnkpID0+IHggPT09IG51bGwgfHwgaXNOdW1iZXIoeCk7XG4gICAgICAgIGxvY1ZhbGlkYXRvci52YWxpZGF0ZVByb3BlcnR5KGxvY2F0aW9uLCAnbGF0aXR1ZGUnLCBpc1ZhbGlkTG9jLCBsb2NhdGlvbik7XG4gICAgICAgIGxvY1ZhbGlkYXRvci52YWxpZGF0ZVByb3BlcnR5KGxvY2F0aW9uLCAnbG9uZ2l0dWRlJywgaXNWYWxpZExvYywgbG9jYXRpb24pO1xuICAgICAgICByZXR1cm4gbG9jVmFsaWRhdG9yLmVycm9ycy5sZW5ndGggPT09IDA7XG4gICAgfSwgREVGQVVMVF9TRVRUSU5HUyk7XG5cbiAgICB2YWxpZGF0ZVByb3BlcnR5KHNldHRpbmdzLCAncHJldmlld05ld0Rlc2lnbicsIGlzQm9vbGVhbiwgREVGQVVMVF9TRVRUSU5HUyk7XG4gICAgdmFsaWRhdGVQcm9wZXJ0eShzZXR0aW5ncywgJ3ByZXZpZXdOZXdlc3REZXNpZ24nLCBpc0Jvb2xlYW4sIERFRkFVTFRfU0VUVElOR1MpO1xuICAgIHZhbGlkYXRlUHJvcGVydHkoc2V0dGluZ3MsICdlbmFibGVGb3JQREYnLCBpc0Jvb2xlYW4sIERFRkFVTFRfU0VUVElOR1MpO1xuICAgIHZhbGlkYXRlUHJvcGVydHkoc2V0dGluZ3MsICdlbmFibGVGb3JQcm90ZWN0ZWRQYWdlcycsIGlzQm9vbGVhbiwgREVGQVVMVF9TRVRUSU5HUyk7XG4gICAgdmFsaWRhdGVQcm9wZXJ0eShzZXR0aW5ncywgJ2VuYWJsZUNvbnRleHRNZW51cycsIGlzQm9vbGVhbiwgREVGQVVMVF9TRVRUSU5HUyk7XG4gICAgdmFsaWRhdGVQcm9wZXJ0eShzZXR0aW5ncywgJ2RldGVjdERhcmtUaGVtZScsIGlzQm9vbGVhbiwgREVGQVVMVF9TRVRUSU5HUyk7XG5cbiAgICByZXR1cm4ge2Vycm9ycywgc2V0dGluZ3N9O1xufVxuXG5pbnRlcmZhY2UgVGhlbWVWYWxpZGF0aW9uUmVzdWx0IHtcbiAgICB0aGVtZTogUGFydGlhbDxUaGVtZT47XG4gICAgZXJyb3JzOiBzdHJpbmdbXTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIHZhbGlkYXRlVGhlbWUodGhlbWU6IFBhcnRpYWw8VGhlbWU+IHwgbnVsbCB8IHVuZGVmaW5lZCk6IFRoZW1lVmFsaWRhdGlvblJlc3VsdCB7XG4gICAgaWYgKCFpc1BsYWluT2JqZWN0KHRoZW1lKSkge1xuICAgICAgICByZXR1cm4ge2Vycm9yczogWydUaGVtZSBpcyBub3QgYSBwbGFpbiBvYmplY3QnXSwgdGhlbWU6IERFRkFVTFRfVEhFTUV9O1xuICAgIH1cblxuICAgIGNvbnN0IHt2YWxpZGF0ZVByb3BlcnR5LCBlcnJvcnN9ID0gY3JlYXRlVmFsaWRhdG9yKCk7XG4gICAgdmFsaWRhdGVQcm9wZXJ0eSh0aGVtZSwgJ21vZGUnLCBpc09uZU9mKDAsIDEpLCBERUZBVUxUX1RIRU1FKTtcbiAgICB2YWxpZGF0ZVByb3BlcnR5KHRoZW1lLCAnYnJpZ2h0bmVzcycsIGlzTnVtYmVyQmV0d2VlbigwLCAyMDApLCBERUZBVUxUX1RIRU1FKTtcbiAgICB2YWxpZGF0ZVByb3BlcnR5KHRoZW1lLCAnY29udHJhc3QnLCBpc051bWJlckJldHdlZW4oMCwgMjAwKSwgREVGQVVMVF9USEVNRSk7XG4gICAgdmFsaWRhdGVQcm9wZXJ0eSh0aGVtZSwgJ2dyYXlzY2FsZScsIGlzTnVtYmVyQmV0d2VlbigwLCAxMDApLCBERUZBVUxUX1RIRU1FKTtcbiAgICB2YWxpZGF0ZVByb3BlcnR5KHRoZW1lLCAnc2VwaWEnLCBpc051bWJlckJldHdlZW4oMCwgMTAwKSwgREVGQVVMVF9USEVNRSk7XG4gICAgdmFsaWRhdGVQcm9wZXJ0eSh0aGVtZSwgJ3VzZUZvbnQnLCBpc0Jvb2xlYW4sIERFRkFVTFRfVEhFTUUpO1xuICAgIHZhbGlkYXRlUHJvcGVydHkodGhlbWUsICdmb250RmFtaWx5JywgaXNOb25FbXB0eVN0cmluZywgREVGQVVMVF9USEVNRSk7XG4gICAgdmFsaWRhdGVQcm9wZXJ0eSh0aGVtZSwgJ3RleHRTdHJva2UnLCBpc051bWJlckJldHdlZW4oMCwgMSksIERFRkFVTFRfVEhFTUUpO1xuICAgIHZhbGlkYXRlUHJvcGVydHkodGhlbWUsICdlbmdpbmUnLCBpc09uZU9mKCdkeW5hbWljVGhlbWUnLCAnc3RhdGljVGhlbWUnLCAnY3NzRmlsdGVyJywgJ3N2Z0ZpbHRlcicpLCBERUZBVUxUX1RIRU1FKTtcbiAgICB2YWxpZGF0ZVByb3BlcnR5KHRoZW1lLCAnc3R5bGVzaGVldCcsIGlzU3RyaW5nLCBERUZBVUxUX1RIRU1FKTtcbiAgICB2YWxpZGF0ZVByb3BlcnR5KHRoZW1lLCAnZGFya1NjaGVtZUJhY2tncm91bmRDb2xvcicsIGlzUmVnRXhwTWF0Y2goL14jWzAtOWEtZl17Nn0kL2kpLCBERUZBVUxUX1RIRU1FKTtcbiAgICB2YWxpZGF0ZVByb3BlcnR5KHRoZW1lLCAnZGFya1NjaGVtZVRleHRDb2xvcicsIGlzUmVnRXhwTWF0Y2goL14jWzAtOWEtZl17Nn0kL2kpLCBERUZBVUxUX1RIRU1FKTtcbiAgICB2YWxpZGF0ZVByb3BlcnR5KHRoZW1lLCAnbGlnaHRTY2hlbWVCYWNrZ3JvdW5kQ29sb3InLCBpc1JlZ0V4cE1hdGNoKC9eI1swLTlhLWZdezZ9JC9pKSwgREVGQVVMVF9USEVNRSk7XG4gICAgdmFsaWRhdGVQcm9wZXJ0eSh0aGVtZSwgJ2xpZ2h0U2NoZW1lVGV4dENvbG9yJywgaXNSZWdFeHBNYXRjaCgvXiNbMC05YS1mXXs2fSQvaSksIERFRkFVTFRfVEhFTUUpO1xuICAgIHZhbGlkYXRlUHJvcGVydHkodGhlbWUsICdzY3JvbGxiYXJDb2xvcicsICh4OiBhbnkpID0+IHggPT09ICcnIHx8IGlzUmVnRXhwTWF0Y2goL14oYXV0byl8KCNbMC05YS1mXXs2fSkkL2kpKHgpLCBERUZBVUxUX1RIRU1FKTtcbiAgICB2YWxpZGF0ZVByb3BlcnR5KHRoZW1lLCAnc2VsZWN0aW9uQ29sb3InLCBpc1JlZ0V4cE1hdGNoKC9eKGF1dG8pfCgjWzAtOWEtZl17Nn0pJC9pKSwgREVGQVVMVF9USEVNRSk7XG4gICAgdmFsaWRhdGVQcm9wZXJ0eSh0aGVtZSwgJ3N0eWxlU3lzdGVtQ29udHJvbHMnLCBpc0Jvb2xlYW4sIERFRkFVTFRfVEhFTUUpO1xuICAgIHZhbGlkYXRlUHJvcGVydHkodGhlbWUsICdsaWdodENvbG9yU2NoZW1lJywgaXNOb25FbXB0eVN0cmluZywgREVGQVVMVF9USEVNRSk7XG4gICAgdmFsaWRhdGVQcm9wZXJ0eSh0aGVtZSwgJ2RhcmtDb2xvclNjaGVtZScsIGlzTm9uRW1wdHlTdHJpbmcsIERFRkFVTFRfVEhFTUUpO1xuICAgIHZhbGlkYXRlUHJvcGVydHkodGhlbWUsICdpbW1lZGlhdGVNb2RpZnknLCBpc0Jvb2xlYW4sIERFRkFVTFRfVEhFTUUpO1xuXG4gICAgcmV0dXJuIHtlcnJvcnMsIHRoZW1lfTtcbn1cbiIsImRlY2xhcmUgY29uc3QgX19ERUJVR19fOiBib29sZWFuO1xuZGVjbGFyZSBjb25zdCBfX0xPR19fOiAnaW5mbycgfCAnd2FybicgfCAnYXNzZXJ0JztcblxubGV0IHNvY2tldDogV2ViU29ja2V0IHwgbnVsbCA9IG51bGw7XG5sZXQgbWVzc2FnZVF1ZXVlOiBzdHJpbmdbXSA9IFtdO1xuZnVuY3Rpb24gY3JlYXRlU29ja2V0KCk6IHZvaWQge1xuICAgIGlmIChzb2NrZXQpIHtcbiAgICAgICAgcmV0dXJuO1xuICAgIH1cbiAgICBjb25zdCBuZXdTb2NrZXQgPSBuZXcgV2ViU29ja2V0KGB3czovL2xvY2FsaG9zdDokezkwMDB9YCk7XG4gICAgc29ja2V0ID0gbmV3U29ja2V0O1xuICAgIG5ld1NvY2tldC5hZGRFdmVudExpc3RlbmVyKCdvcGVuJywgKCkgPT4ge1xuICAgICAgICBtZXNzYWdlUXVldWUuZm9yRWFjaCgobWVzc2FnZSkgPT4gbmV3U29ja2V0LnNlbmQobWVzc2FnZSkpO1xuICAgICAgICBtZXNzYWdlUXVldWUgPSBbXTtcbiAgICB9KTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIHNlbmRMb2cobGV2ZWw6ICdpbmZvJyB8ICd3YXJuJyB8ICdhc3NlcnQnLCAuLi5hcmdzOiBhbnlbXSk6IHZvaWQge1xuICAgIGlmICghX19ERUJVR19fIHx8ICFfX0xPR19fKSB7XG4gICAgICAgIHJldHVybjtcbiAgICB9XG4gICAgY29uc3QgbWVzc2FnZSA9IEpTT04uc3RyaW5naWZ5KHtsZXZlbCwgbG9nOiBhcmdzfSk7XG4gICAgaWYgKHNvY2tldCAmJiBzb2NrZXQucmVhZHlTdGF0ZSA9PT0gc29ja2V0Lk9QRU4pIHtcbiAgICAgICAgc29ja2V0LnNlbmQobWVzc2FnZSk7XG4gICAgfSBlbHNlIHtcbiAgICAgICAgY3JlYXRlU29ja2V0KCk7XG4gICAgICAgIG1lc3NhZ2VRdWV1ZS5wdXNoKG1lc3NhZ2UpO1xuICAgIH1cbn1cbiIsImltcG9ydCB7c2VuZExvZ30gZnJvbSAnLi9zZW5kTG9nJztcblxuZGVjbGFyZSBjb25zdCBfX0RFQlVHX186IGJvb2xlYW47XG5kZWNsYXJlIGNvbnN0IF9fVEVTVF9fOiBib29sZWFuO1xuXG5leHBvcnQgZnVuY3Rpb24gbG9nSW5mbyguLi5hcmdzOiBhbnlbXSk6IHZvaWQge1xuICAgIGlmIChfX0RFQlVHX18pIHtcbiAgICAgICAgY29uc29sZS5pbmZvKC4uLmFyZ3MpO1xuICAgICAgICBzZW5kTG9nKCdpbmZvJywgYXJncyk7XG4gICAgfVxufVxuXG5leHBvcnQgZnVuY3Rpb24gbG9nV2FybiguLi5hcmdzOiBhbnlbXSk6IHZvaWQge1xuICAgIGlmIChfX0RFQlVHX18pIHtcbiAgICAgICAgY29uc29sZS53YXJuKC4uLmFyZ3MpO1xuICAgICAgICBzZW5kTG9nKCd3YXJuJywgYXJncyk7XG4gICAgfVxufVxuXG5leHBvcnQgZnVuY3Rpb24gbG9nSW5mb0NvbGxhcHNlZCh0aXRsZTogc3RyaW5nLCAuLi5hcmdzOiBhbnlbXSk6IHZvaWQge1xuICAgIGlmIChfX0RFQlVHX18pIHtcbiAgICAgICAgY29uc29sZS5ncm91cENvbGxhcHNlZCh0aXRsZSk7XG4gICAgICAgIGNvbnNvbGUubG9nKC4uLmFyZ3MpO1xuICAgICAgICBjb25zb2xlLmdyb3VwRW5kKCk7XG4gICAgICAgIHNlbmRMb2coJ2luZm8nLCBhcmdzKTtcbiAgICB9XG59XG5cbmZ1bmN0aW9uIGxvZ0Fzc2VydCguLi5hcmdzOiBhbnlbXSk6IHZvaWQge1xuICAgIGlmICgoX19URVNUX18gfHwgX19ERUJVR19fKSkge1xuICAgICAgICBjb25zb2xlLmFzc2VydCguLi5hcmdzKTtcbiAgICAgICAgc2VuZExvZygnYXNzZXJ0JywgLi4uYXJncyk7XG4gICAgfVxufVxuXG5leHBvcnQgZnVuY3Rpb24gQVNTRVJUKGRlc2NyaXB0aW9uOiBzdHJpbmcsIGNvbmRpdGlvbjogKCgpID0+IGJvb2xlYW4pIHwgYW55KTogdm9pZCB7XG4gICAgaWYgKChfX1RFU1RfXyB8fCBfX0RFQlVHX18pICYmICh0eXBlb2YgY29uZGl0aW9uID09PSAnZnVuY3Rpb24nICYmICFjb25kaXRpb24oKSkgfHwgIWNvbmRpdGlvbikge1xuICAgICAgICBsb2dBc3NlcnQoZGVzY3JpcHRpb24pO1xuICAgICAgICBpZiAoX19URVNUX18pIHtcbiAgICAgICAgICAgIHRocm93IG5ldyBFcnJvcihgQXNzZXJ0aW9uIGZhaWxlZDogJHtkZXNjcmlwdGlvbn1gKTtcbiAgICAgICAgfVxuICAgIH1cbn1cbiIsImltcG9ydCB7VGhlbWVFbmdpbmV9IGZyb20gJy4uL2dlbmVyYXRvcnMvdGhlbWUtZW5naW5lcyc7XG5pbXBvcnQge0RFRkFVTFRfU0VUVElOR1MsIERFRkFVTFRfVEhFTUV9IGZyb20gJy4uL2RlZmF1bHRzJztcbmltcG9ydCB0eXBlIHtVc2VyU2V0dGluZ3N9IGZyb20gJy4uL2RlZmluaXRpb25zJztcbmltcG9ydCB7ZGVib3VuY2V9IGZyb20gJy4uL3V0aWxzL2RlYm91bmNlJztcbmltcG9ydCB7UHJvbWlzZUJhcnJpZXJ9IGZyb20gJy4uL3V0aWxzL3Byb21pc2UtYmFycmllcic7XG5pbXBvcnQge2lzVVJMTWF0Y2hlZH0gZnJvbSAnLi4vdXRpbHMvdXJsJztcbmltcG9ydCB7dmFsaWRhdGVTZXR0aW5nc30gZnJvbSAnLi4vdXRpbHMvdmFsaWRhdGlvbic7XG5cbmltcG9ydCB7cmVhZFN5bmNTdG9yYWdlLCByZWFkTG9jYWxTdG9yYWdlLCB3cml0ZVN5bmNTdG9yYWdlLCB3cml0ZUxvY2FsU3RvcmFnZSwgcmVtb3ZlU3luY1N0b3JhZ2UsIHJlbW92ZUxvY2FsU3RvcmFnZX0gZnJvbSAnLi91dGlscy9leHRlbnNpb24tYXBpJztcbmltcG9ydCB7bG9nV2Fybn0gZnJvbSAnLi91dGlscy9sb2cnO1xuXG5cbmNvbnN0IFNBVkVfVElNRU9VVCA9IDEwMDA7XG5cbmV4cG9ydCBkZWZhdWx0IGNsYXNzIFVzZXJTdG9yYWdlIHtcbiAgICBwcml2YXRlIHN0YXRpYyBsb2FkQmFycmllcjogUHJvbWlzZUJhcnJpZXI8VXNlclNldHRpbmdzLCB2b2lkPjtcbiAgICBwcml2YXRlIHN0YXRpYyBzYXZlU3RvcmFnZUJhcnJpZXI6IFByb21pc2VCYXJyaWVyPHZvaWQsIHZvaWQ+IHwgbnVsbDtcbiAgICBzdGF0aWMgc2V0dGluZ3M6IFJlYWRvbmx5PFVzZXJTZXR0aW5ncz47XG5cbiAgICBzdGF0aWMgYXN5bmMgbG9hZFNldHRpbmdzKCk6IFByb21pc2U8dm9pZD4ge1xuICAgICAgICBpZiAoIVVzZXJTdG9yYWdlLnNldHRpbmdzKSB7XG4gICAgICAgICAgICBVc2VyU3RvcmFnZS5zZXR0aW5ncyA9IGF3YWl0IFVzZXJTdG9yYWdlLmxvYWRTZXR0aW5nc0Zyb21TdG9yYWdlKCk7XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBmaWxsRGVmYXVsdHMoc2V0dGluZ3M6IFVzZXJTZXR0aW5ncykge1xuICAgICAgICBzZXR0aW5ncy50aGVtZSA9IHsuLi5ERUZBVUxUX1RIRU1FLCAuLi5zZXR0aW5ncy50aGVtZX07XG4gICAgICAgIHNldHRpbmdzLnRpbWUgPSB7Li4uREVGQVVMVF9TRVRUSU5HUy50aW1lLCAuLi5zZXR0aW5ncy50aW1lfTtcbiAgICAgICAgc2V0dGluZ3MucHJlc2V0cy5mb3JFYWNoKChwcmVzZXQpID0+IHtcbiAgICAgICAgICAgIHByZXNldC50aGVtZSA9IHsuLi5ERUZBVUxUX1RIRU1FLCAuLi5wcmVzZXQudGhlbWV9O1xuICAgICAgICB9KTtcbiAgICAgICAgc2V0dGluZ3MuY3VzdG9tVGhlbWVzLmZvckVhY2goKHNpdGUpID0+IHtcbiAgICAgICAgICAgIHNpdGUudGhlbWUgPSB7Li4uREVGQVVMVF9USEVNRSwgLi4uc2l0ZS50aGVtZX07XG4gICAgICAgIH0pO1xuICAgICAgICBpZiAoc2V0dGluZ3MuY3VzdG9tVGhlbWVzLmxlbmd0aCA9PT0gMCkge1xuICAgICAgICAgICAgc2V0dGluZ3MuY3VzdG9tVGhlbWVzID0gREVGQVVMVF9TRVRUSU5HUy5jdXN0b21UaGVtZXM7XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICAvLyBtaWdyYXRlQXV0b21hdGlvblNldHRpbmdzIG1pZ3JhdGVzIG9sZCBhdXRvbWF0aW9uIHNldHRpbmdzIHRvIHRoZSBuZXcgaW50ZXJmYWNlLlxuICAgIC8vIEl0IHdpbGwgbW92ZSBzZXR0aW5ncy5hdXRvbWF0aW9uICYgc2V0dGluZ3MuYXV0b21hdGlvbkJlaGF2aW9yIGludG8sXG4gICAgLy8gc2V0dGluZ3MuYXV0b21hdGlvbiA9IHsgZW5hYmxlZCwgbW9kZSwgYmVoYXZpb3IgfS5cbiAgICAvLyBSZW1vdmUgdGhpcyBvdmVyIHR3byB5ZWFycyhtaWQtMjAyNCkuXG4gICAgLy8gVGhpcyB3b24ndCBhbHdheXMgd29yaywgYmVjYXVzZSBicm93c2VycyBjYW4gZGVjaWRlIHRvIGluc3RlYWQgdXNlIHRoZSBkZWZhdWx0IHNldHRpbmdzXG4gICAgLy8gd2hlbiB0aGV5IG5vdGljZSBhIGRpZmZlcmVudCB0eXBlIGJlaW5nIHJlcXVlc3RlZCBmb3IgYXV0b21hdGlvbiwgaW4gdGhhdCBjYXNlIGl0J3MgYSBkYXRhLWxvc3NcbiAgICAvLyBhbmQgbm90IHNvbWV0aGluZyB3ZSBjYW4gZW5jb3VudGVyIGZvciwgZXhjZXB0IGZvciBkb2luZyBhbHdheXMgdHdvIGV4dHJhIHJlcXVlc3RzIHRvIGV4cGxpY2l0bHlcbiAgICAvLyBjaGVjayBmb3IgdGhpcyBjYXNlIHdoaWNoIGlzIGluZWZmaWNpZW50IHVzYWdlIG9mIHJlcXVlc3Rpbmcgc3RvcmFnZS5cbiAgICBwcml2YXRlIHN0YXRpYyBtaWdyYXRlQXV0b21hdGlvblNldHRpbmdzKHNldHRpbmdzOiBVc2VyU2V0dGluZ3MpOiB2b2lkIHtcbiAgICAgICAgaWYgKHR5cGVvZiBzZXR0aW5ncy5hdXRvbWF0aW9uID09PSAnc3RyaW5nJykge1xuICAgICAgICAgICAgY29uc3QgYXV0b21hdGlvbk1vZGUgPSBzZXR0aW5ncy5hdXRvbWF0aW9uO1xuICAgICAgICAgICAgY29uc3QgYXV0b21hdGlvbkJlaGF2aW9yOiBVc2VyU2V0dGluZ3NbJ2F1dG9tYXRpb24nXVsnYmVoYXZpb3InXSA9IChzZXR0aW5ncyBhcyBhbnkpLmF1dG9tYXRpb25CZWhhdmlvdXI7XG4gICAgICAgICAgICBpZiAoc2V0dGluZ3MuYXV0b21hdGlvbiA9PT0gJycpIHtcbiAgICAgICAgICAgICAgICBzZXR0aW5ncy5hdXRvbWF0aW9uID0ge1xuICAgICAgICAgICAgICAgICAgICBlbmFibGVkOiBmYWxzZSxcbiAgICAgICAgICAgICAgICAgICAgbW9kZTogYXV0b21hdGlvbk1vZGUsXG4gICAgICAgICAgICAgICAgICAgIGJlaGF2aW9yOiBhdXRvbWF0aW9uQmVoYXZpb3IsXG4gICAgICAgICAgICAgICAgfTtcbiAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgc2V0dGluZ3MuYXV0b21hdGlvbiA9IHtcbiAgICAgICAgICAgICAgICAgICAgZW5hYmxlZDogdHJ1ZSxcbiAgICAgICAgICAgICAgICAgICAgbW9kZTogYXV0b21hdGlvbk1vZGUsXG4gICAgICAgICAgICAgICAgICAgIGJlaGF2aW9yOiBhdXRvbWF0aW9uQmVoYXZpb3IsXG4gICAgICAgICAgICAgICAgfTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGRlbGV0ZSAoc2V0dGluZ3MgYXMgYW55KS5hdXRvbWF0aW9uQmVoYXZpb3VyO1xuICAgICAgICB9XG4gICAgfVxuXG4gICAgcHJpdmF0ZSBzdGF0aWMgbWlncmF0ZVNpdGVMaXN0c1YyKGRlcHJlY2F0ZWQ6IGFueSk6IFBhcnRpYWw8VXNlclNldHRpbmdzPiB7XG4gICAgICAgIGNvbnN0IHNldHRpbmdzOiBQYXJ0aWFsPFVzZXJTZXR0aW5ncz4gPSB7fTtcbiAgICAgICAgc2V0dGluZ3MuZW5hYmxlZEJ5RGVmYXVsdCA9ICFkZXByZWNhdGVkLmFwcGx5VG9MaXN0ZWRPbmx5O1xuICAgICAgICBpZiAoc2V0dGluZ3MuZW5hYmxlZEJ5RGVmYXVsdCkge1xuICAgICAgICAgICAgc2V0dGluZ3MuZGlzYWJsZWRGb3IgPSBkZXByZWNhdGVkLnNpdGVMaXN0ID8/IFtdO1xuICAgICAgICAgICAgc2V0dGluZ3MuZW5hYmxlZEZvciA9IGRlcHJlY2F0ZWQuc2l0ZUxpc3RFbmFibGVkID8/IFtdO1xuICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgc2V0dGluZ3MuZGlzYWJsZWRGb3IgPSBbXTtcbiAgICAgICAgICAgIHNldHRpbmdzLmVuYWJsZWRGb3IgPSBkZXByZWNhdGVkLnNpdGVMaXN0ID8/IFtdO1xuICAgICAgICB9XG4gICAgICAgIHJldHVybiBzZXR0aW5ncztcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBtaWdyYXRlQnVpbHRJblNWR0ZpbHRlclRvQ1NTRmlsdGVyKHNldHRpbmdzOiBVc2VyU2V0dGluZ3MpOiB2b2lkIHtcbiAgICAgICAgc2V0dGluZ3M/LmN1c3RvbVRoZW1lcz8uZm9yRWFjaCgoYykgPT4ge1xuICAgICAgICAgICAgaWYgKFxuICAgICAgICAgICAgICAgIGM/LnRoZW1lPy5lbmdpbmUgPT09IFRoZW1lRW5naW5lLnN2Z0ZpbHRlciAmJlxuICAgICAgICAgICAgICAgIChjLmJ1aWx0SW4gfHwgYy51cmw/LmluY2x1ZGVzKCdkb2NzLmdvb2dsZS5jb20nKSlcbiAgICAgICAgICAgICkge1xuICAgICAgICAgICAgICAgIGMudGhlbWUuZW5naW5lID0gVGhlbWVFbmdpbmUuY3NzRmlsdGVyO1xuICAgICAgICAgICAgfVxuICAgICAgICB9KTtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBhc3luYyBsb2FkU2V0dGluZ3NGcm9tU3RvcmFnZSgpOiBQcm9taXNlPFVzZXJTZXR0aW5ncz4ge1xuICAgICAgICBpZiAoVXNlclN0b3JhZ2UubG9hZEJhcnJpZXIpIHtcbiAgICAgICAgICAgIHJldHVybiBhd2FpdCBVc2VyU3RvcmFnZS5sb2FkQmFycmllci5lbnRyeSgpO1xuICAgICAgICB9XG4gICAgICAgIFVzZXJTdG9yYWdlLmxvYWRCYXJyaWVyID0gbmV3IFByb21pc2VCYXJyaWVyKCk7XG5cbiAgICAgICAgbGV0IGxvY2FsID0gYXdhaXQgcmVhZExvY2FsU3RvcmFnZShERUZBVUxUX1NFVFRJTkdTKTtcblxuICAgICAgICBpZiAobG9jYWwuc2NoZW1lVmVyc2lvbiA8IDIpIHtcbiAgICAgICAgICAgIGNvbnN0IHN5bmMgPSBhd2FpdCByZWFkU3luY1N0b3JhZ2Uoe3NjaGVtZVZlcnNpb246IDB9KTtcbiAgICAgICAgICAgIGlmICghc3luYyB8fCBzeW5jLnNjaGVtZVZlcnNpb24gPCAyKSB7XG4gICAgICAgICAgICAgICAgY29uc3QgZGVwcmVjYXRlZERlZmF1bHRzID0ge1xuICAgICAgICAgICAgICAgICAgICBzaXRlTGlzdDogW10sXG4gICAgICAgICAgICAgICAgICAgIHNpdGVMaXN0RW5hYmxlZDogW10sXG4gICAgICAgICAgICAgICAgICAgIGFwcGx5VG9MaXN0ZWRPbmx5OiBmYWxzZSxcbiAgICAgICAgICAgICAgICB9O1xuICAgICAgICAgICAgICAgIGNvbnN0IGxvY2FsRGVwcmVjYXRlZCA9IGF3YWl0IHJlYWRMb2NhbFN0b3JhZ2UoZGVwcmVjYXRlZERlZmF1bHRzKTtcbiAgICAgICAgICAgICAgICBjb25zdCBsb2NhbFRyYW5zZm9ybWVkID0gVXNlclN0b3JhZ2UubWlncmF0ZVNpdGVMaXN0c1YyKGxvY2FsRGVwcmVjYXRlZCk7XG4gICAgICAgICAgICAgICAgYXdhaXQgd3JpdGVMb2NhbFN0b3JhZ2Uoe3NjaGVtZVZlcnNpb246IDIsIC4uLmxvY2FsVHJhbnNmb3JtZWR9KTtcbiAgICAgICAgICAgICAgICBhd2FpdCByZW1vdmVMb2NhbFN0b3JhZ2UoT2JqZWN0LmtleXMoZGVwcmVjYXRlZERlZmF1bHRzKSk7XG5cbiAgICAgICAgICAgICAgICBjb25zdCBzeW5jRGVwcmVjYXRlZCA9IGF3YWl0IHJlYWRTeW5jU3RvcmFnZShkZXByZWNhdGVkRGVmYXVsdHMpO1xuICAgICAgICAgICAgICAgIGNvbnN0IHN5bmNUcmFuc2Zvcm1lZCA9IFVzZXJTdG9yYWdlLm1pZ3JhdGVTaXRlTGlzdHNWMihzeW5jRGVwcmVjYXRlZCk7XG4gICAgICAgICAgICAgICAgYXdhaXQgd3JpdGVTeW5jU3RvcmFnZSh7c2NoZW1lVmVyc2lvbjogMiwgLi4uc3luY1RyYW5zZm9ybWVkfSk7XG4gICAgICAgICAgICAgICAgYXdhaXQgcmVtb3ZlU3luY1N0b3JhZ2UoT2JqZWN0LmtleXMoZGVwcmVjYXRlZERlZmF1bHRzKSk7XG5cbiAgICAgICAgICAgICAgICBsb2NhbCA9IGF3YWl0IHJlYWRMb2NhbFN0b3JhZ2UoREVGQVVMVF9TRVRUSU5HUyk7XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cblxuICAgICAgICBjb25zdCB7ZXJyb3JzOiBsb2NhbENmZ0Vycm9yc30gPSB2YWxpZGF0ZVNldHRpbmdzKGxvY2FsKTtcbiAgICAgICAgbG9jYWxDZmdFcnJvcnMuZm9yRWFjaCgoZXJyKSA9PiBsb2dXYXJuKGVycikpO1xuICAgICAgICBpZiAobG9jYWwuc3luY1NldHRpbmdzID09IG51bGwpIHtcbiAgICAgICAgICAgIGxvY2FsLnN5bmNTZXR0aW5ncyA9IERFRkFVTFRfU0VUVElOR1Muc3luY1NldHRpbmdzO1xuICAgICAgICB9XG4gICAgICAgIGlmICghbG9jYWwuc3luY1NldHRpbmdzKSB7XG4gICAgICAgICAgICBVc2VyU3RvcmFnZS5taWdyYXRlQXV0b21hdGlvblNldHRpbmdzKGxvY2FsKTtcbiAgICAgICAgICAgIFVzZXJTdG9yYWdlLm1pZ3JhdGVCdWlsdEluU1ZHRmlsdGVyVG9DU1NGaWx0ZXIobG9jYWwpO1xuICAgICAgICAgICAgVXNlclN0b3JhZ2UuZmlsbERlZmF1bHRzKGxvY2FsKTtcbiAgICAgICAgICAgIFVzZXJTdG9yYWdlLmxvYWRCYXJyaWVyLnJlc29sdmUobG9jYWwpO1xuICAgICAgICAgICAgcmV0dXJuIGxvY2FsO1xuICAgICAgICB9XG5cbiAgICAgICAgY29uc3QgJHN5bmMgPSBhd2FpdCByZWFkU3luY1N0b3JhZ2UoREVGQVVMVF9TRVRUSU5HUyk7XG4gICAgICAgIGlmICghJHN5bmMpIHtcbiAgICAgICAgICAgIGxvZ1dhcm4oJ1N5bmMgc2V0dGluZ3MgYXJlIG1pc3NpbmcnKTtcbiAgICAgICAgICAgIGxvY2FsLnN5bmNTZXR0aW5ncyA9IGZhbHNlO1xuICAgICAgICAgICAgVXNlclN0b3JhZ2Uuc2V0KHtzeW5jU2V0dGluZ3M6IGZhbHNlfSk7XG4gICAgICAgICAgICBVc2VyU3RvcmFnZS5zYXZlU3luY1NldHRpbmcoZmFsc2UpO1xuICAgICAgICAgICAgVXNlclN0b3JhZ2UubG9hZEJhcnJpZXIucmVzb2x2ZShsb2NhbCk7XG4gICAgICAgICAgICByZXR1cm4gbG9jYWw7XG4gICAgICAgIH1cblxuICAgICAgICBjb25zdCB7ZXJyb3JzOiBzeW5jQ2ZnRXJyb3JzfSA9IHZhbGlkYXRlU2V0dGluZ3MoJHN5bmMpO1xuICAgICAgICBzeW5jQ2ZnRXJyb3JzLmZvckVhY2goKGVycikgPT4gbG9nV2FybihlcnIpKTtcblxuICAgICAgICBVc2VyU3RvcmFnZS5taWdyYXRlQXV0b21hdGlvblNldHRpbmdzKCRzeW5jKTtcbiAgICAgICAgVXNlclN0b3JhZ2UubWlncmF0ZUJ1aWx0SW5TVkdGaWx0ZXJUb0NTU0ZpbHRlcigkc3luYyk7XG4gICAgICAgIFVzZXJTdG9yYWdlLmZpbGxEZWZhdWx0cygkc3luYyk7XG5cbiAgICAgICAgVXNlclN0b3JhZ2UubG9hZEJhcnJpZXIucmVzb2x2ZSgkc3luYyk7XG4gICAgICAgIHJldHVybiAkc3luYztcbiAgICB9XG5cbiAgICBzdGF0aWMgYXN5bmMgc2F2ZVNldHRpbmdzKCk6IFByb21pc2U8dm9pZD4ge1xuICAgICAgICBpZiAoIVVzZXJTdG9yYWdlLnNldHRpbmdzKSB7XG4gICAgICAgICAgICAvLyBUaGlzIHBhdGggaXMgbmV2ZXIgdGFrZW4gYmVjYXVzZSBFeHRlbnNpb24gYWx3YXlzIGNhbGxzIFVzZXJTdG9yYWdlLmxvYWRTZXR0aW5ncygpXG4gICAgICAgICAgICAvLyBiZWZvcmUgY2FsbGluZyBVc2VyU3RvcmFnZS5zYXZlU2V0dGluZ3MoKS5cbiAgICAgICAgICAgIGxvZ1dhcm4oJ0NvdWxkIG5vdCBzYXZlIHNldHRpbmdzIGludG8gc3RvcmFnZSBiZWNhdXNlIHRoZSBzZXR0aW5ncyBhcmUgbWlzc2luZy4nKTtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuICAgICAgICBhd2FpdCBVc2VyU3RvcmFnZS5zYXZlU2V0dGluZ3NJbnRvU3RvcmFnZSgpO1xuICAgIH1cblxuICAgIHN0YXRpYyBhc3luYyBzYXZlU3luY1NldHRpbmcoc3luYzogYm9vbGVhbik6IFByb21pc2U8dm9pZD4ge1xuICAgICAgICBjb25zdCBvYmogPSB7c3luY1NldHRpbmdzOiBzeW5jfTtcbiAgICAgICAgYXdhaXQgd3JpdGVMb2NhbFN0b3JhZ2Uob2JqKTtcbiAgICAgICAgdHJ5IHtcbiAgICAgICAgICAgIGF3YWl0IHdyaXRlU3luY1N0b3JhZ2Uob2JqKTtcbiAgICAgICAgfSBjYXRjaCAoZXJyKSB7XG4gICAgICAgICAgICBsb2dXYXJuKCdTZXR0aW5ncyBzeW5jaHJvbml6YXRpb24gd2FzIGRpc2FibGVkIGR1ZSB0byBlcnJvcjonLCBjaHJvbWUucnVudGltZS5sYXN0RXJyb3IpO1xuICAgICAgICAgICAgVXNlclN0b3JhZ2Uuc2V0KHtzeW5jU2V0dGluZ3M6IGZhbHNlfSk7XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBzYXZlU2V0dGluZ3NJbnRvU3RvcmFnZSA9IGRlYm91bmNlKFNBVkVfVElNRU9VVCwgYXN5bmMgKCkgPT4ge1xuICAgICAgICBpZiAoVXNlclN0b3JhZ2Uuc2F2ZVN0b3JhZ2VCYXJyaWVyKSB7XG4gICAgICAgICAgICBhd2FpdCBVc2VyU3RvcmFnZS5zYXZlU3RvcmFnZUJhcnJpZXIuZW50cnkoKTtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuICAgICAgICBVc2VyU3RvcmFnZS5zYXZlU3RvcmFnZUJhcnJpZXIgPSBuZXcgUHJvbWlzZUJhcnJpZXIoKTtcblxuICAgICAgICBjb25zdCBzZXR0aW5ncyA9IFVzZXJTdG9yYWdlLnNldHRpbmdzO1xuICAgICAgICBpZiAoc2V0dGluZ3Muc3luY1NldHRpbmdzKSB7XG4gICAgICAgICAgICB0cnkge1xuICAgICAgICAgICAgICAgIGF3YWl0IHdyaXRlU3luY1N0b3JhZ2Uoc2V0dGluZ3MpO1xuICAgICAgICAgICAgfSBjYXRjaCAoZXJyKSB7XG4gICAgICAgICAgICAgICAgbG9nV2FybignU2V0dGluZ3Mgc3luY2hyb25pemF0aW9uIHdhcyBkaXNhYmxlZCBkdWUgdG8gZXJyb3I6JywgY2hyb21lLnJ1bnRpbWUubGFzdEVycm9yKTtcbiAgICAgICAgICAgICAgICBVc2VyU3RvcmFnZS5zZXQoe3N5bmNTZXR0aW5nczogZmFsc2V9KTtcbiAgICAgICAgICAgICAgICBhd2FpdCBVc2VyU3RvcmFnZS5zYXZlU3luY1NldHRpbmcoZmFsc2UpO1xuICAgICAgICAgICAgICAgIGF3YWl0IHdyaXRlTG9jYWxTdG9yYWdlKHNldHRpbmdzKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgIGF3YWl0IHdyaXRlTG9jYWxTdG9yYWdlKHNldHRpbmdzKTtcbiAgICAgICAgfVxuXG4gICAgICAgIFVzZXJTdG9yYWdlLnNhdmVTdG9yYWdlQmFycmllci5yZXNvbHZlKCk7XG4gICAgICAgIFVzZXJTdG9yYWdlLnNhdmVTdG9yYWdlQmFycmllciA9IG51bGw7XG4gICAgfSk7XG5cbiAgICBzdGF0aWMgc2V0KCRzZXR0aW5nczogUGFydGlhbDxVc2VyU2V0dGluZ3M+KTogdm9pZCB7XG4gICAgICAgIGlmICghVXNlclN0b3JhZ2Uuc2V0dGluZ3MpIHtcbiAgICAgICAgICAgIC8vIFRoaXMgcGF0aCBpcyBuZXZlciB0YWtlbiBiZWNhdXNlIEV4dGVuc2lvbiBhbHdheXMgY2FsbHMgVXNlclN0b3JhZ2UubG9hZFNldHRpbmdzKClcbiAgICAgICAgICAgIC8vIGJlZm9yZSBjYWxsaW5nIFVzZXJTdG9yYWdlLnNldCgpLlxuICAgICAgICAgICAgbG9nV2FybignQ291bGQgbm90IG1vZGlmeSBzZXR0aW5ncyBiZWNhdXNlIHRoZSBzZXR0aW5ncyBhcmUgbWlzc2luZy4nKTtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuXG4gICAgICAgIGNvbnN0IGZpbHRlclNpdGVMaXN0ID0gKHNpdGVMaXN0OiBzdHJpbmdbXSkgPT4ge1xuICAgICAgICAgICAgaWYgKCFBcnJheS5pc0FycmF5KHNpdGVMaXN0KSkge1xuICAgICAgICAgICAgICAgIGNvbnN0IGxpc3Q6IHN0cmluZ1tdID0gW107XG4gICAgICAgICAgICAgICAgZm9yIChjb25zdCBrZXkgaW4gKHNpdGVMaXN0IGFzIHN0cmluZ1tdKSkge1xuICAgICAgICAgICAgICAgICAgICBjb25zdCBpbmRleCA9IE51bWJlcihrZXkpO1xuICAgICAgICAgICAgICAgICAgICBpZiAoIWlzTmFOKGluZGV4KSkge1xuICAgICAgICAgICAgICAgICAgICAgICAgbGlzdFtpbmRleF0gPSBzaXRlTGlzdFtrZXldO1xuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIHNpdGVMaXN0ID0gbGlzdDtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIHJldHVybiBzaXRlTGlzdC5maWx0ZXIoKHBhdHRlcm4pID0+IHtcbiAgICAgICAgICAgICAgICBsZXQgaXNPSyA9IGZhbHNlO1xuICAgICAgICAgICAgICAgIHRyeSB7XG4gICAgICAgICAgICAgICAgICAgIGlzVVJMTWF0Y2hlZCgnaHR0cHM6Ly9nb29nbGUuY29tLycsIHBhdHRlcm4pO1xuICAgICAgICAgICAgICAgICAgICBpc1VSTE1hdGNoZWQoJ1s6OjFdOjEzMzcnLCBwYXR0ZXJuKTtcbiAgICAgICAgICAgICAgICAgICAgaXNPSyA9IHRydWU7XG4gICAgICAgICAgICAgICAgfSBjYXRjaCAoZXJyKSB7XG4gICAgICAgICAgICAgICAgICAgIGxvZ1dhcm4oYFBhdHRlcm4gXCIke3BhdHRlcm59XCIgZXhjbHVkZWRgKTtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgcmV0dXJuIGlzT0sgJiYgcGF0dGVybiAhPT0gJy8nO1xuICAgICAgICAgICAgfSk7XG4gICAgICAgIH07XG5cbiAgICAgICAgY29uc3Qge2VuYWJsZWRGb3IsIGRpc2FibGVkRm9yfSA9ICRzZXR0aW5ncztcbiAgICAgICAgY29uc3QgdXBkYXRlZFNldHRpbmdzID0gey4uLlVzZXJTdG9yYWdlLnNldHRpbmdzLCAuLi4kc2V0dGluZ3N9O1xuICAgICAgICBpZiAoZW5hYmxlZEZvcikge1xuICAgICAgICAgICAgdXBkYXRlZFNldHRpbmdzLmVuYWJsZWRGb3IgPSBmaWx0ZXJTaXRlTGlzdChlbmFibGVkRm9yKTtcbiAgICAgICAgfVxuICAgICAgICBpZiAoZGlzYWJsZWRGb3IpIHtcbiAgICAgICAgICAgIHVwZGF0ZWRTZXR0aW5ncy5kaXNhYmxlZEZvciA9IGZpbHRlclNpdGVMaXN0KGRpc2FibGVkRm9yKTtcbiAgICAgICAgfVxuXG4gICAgICAgIFVzZXJTdG9yYWdlLnNldHRpbmdzID0gdXBkYXRlZFNldHRpbmdzO1xuICAgIH1cbn1cbiIsImltcG9ydCB7aXNGaXJlZm94fSBmcm9tICcuL3BsYXRmb3JtJztcblxuYXN5bmMgZnVuY3Rpb24gZ2V0T0tSZXNwb25zZSh1cmw6IHN0cmluZywgbWltZVR5cGU/OiBzdHJpbmcsIG9yaWdpbj86IHN0cmluZyk6IFByb21pc2U8UmVzcG9uc2U+IHtcbiAgICBjb25zdCBjcmVkZW50aWFscyA9IG9yaWdpbiAmJiB1cmwuc3RhcnRzV2l0aChgJHtvcmlnaW59L2ApID8gdW5kZWZpbmVkIDogJ29taXQnO1xuICAgIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgZmV0Y2goXG4gICAgICAgIHVybCxcbiAgICAgICAge1xuICAgICAgICAgICAgY2FjaGU6ICdmb3JjZS1jYWNoZScsXG4gICAgICAgICAgICBjcmVkZW50aWFscyxcbiAgICAgICAgICAgIHJlZmVycmVyOiBvcmlnaW4sXG4gICAgICAgIH0sXG4gICAgKTtcblxuICAgIC8vIEZpcmVmb3ggYnVnLCBjb250ZW50IHR5cGUgaXMgXCJhcHBsaWNhdGlvbi94LXVua25vd24tY29udGVudC10eXBlXCJcbiAgICBpZiAoaXNGaXJlZm94ICYmIG1pbWVUeXBlID09PSAndGV4dC9jc3MnICYmIHVybC5zdGFydHNXaXRoKCdtb3otZXh0ZW5zaW9uOi8vJykgJiYgdXJsLmVuZHNXaXRoKCcuY3NzJykpIHtcbiAgICAgICAgcmV0dXJuIHJlc3BvbnNlO1xuICAgIH1cblxuICAgIGlmIChtaW1lVHlwZSAmJiAhKHJlc3BvbnNlLmhlYWRlcnMuZ2V0KCdDb250ZW50LVR5cGUnKSA9PT0gbWltZVR5cGUgfHwgcmVzcG9uc2UuaGVhZGVycy5nZXQoJ0NvbnRlbnQtVHlwZScpIS5zdGFydHNXaXRoKGAke21pbWVUeXBlfTtgKSkpIHtcbiAgICAgICAgdGhyb3cgbmV3IEVycm9yKGBNaW1lIHR5cGUgbWlzbWF0Y2ggd2hlbiBsb2FkaW5nICR7dXJsfWApO1xuICAgIH1cblxuICAgIGlmICghcmVzcG9uc2Uub2spIHtcbiAgICAgICAgdGhyb3cgbmV3IEVycm9yKGBVbmFibGUgdG8gbG9hZCAke3VybH0gJHtyZXNwb25zZS5zdGF0dXN9ICR7cmVzcG9uc2Uuc3RhdHVzVGV4dH1gKTtcbiAgICB9XG5cbiAgICByZXR1cm4gcmVzcG9uc2U7XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiBsb2FkQXNEYXRhVVJMKHVybDogc3RyaW5nLCBtaW1lVHlwZT86IHN0cmluZyk6IFByb21pc2U8c3RyaW5nPiB7XG4gICAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBnZXRPS1Jlc3BvbnNlKHVybCwgbWltZVR5cGUpO1xuICAgIHJldHVybiBhd2FpdCByZWFkUmVzcG9uc2VBc0RhdGFVUkwocmVzcG9uc2UpO1xufVxuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gbG9hZEFzQmxvYih1cmw6IHN0cmluZywgbWltZVR5cGU/OiBzdHJpbmcpOiBQcm9taXNlPEJsb2I+IHtcbiAgICBjb25zdCByZXNwb25zZSA9IGF3YWl0IGdldE9LUmVzcG9uc2UodXJsLCBtaW1lVHlwZSk7XG4gICAgcmV0dXJuIGF3YWl0IHJlc3BvbnNlLmJsb2IoKTtcbn1cblxuZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIHJlYWRSZXNwb25zZUFzRGF0YVVSTChyZXNwb25zZTogUmVzcG9uc2UpOiBQcm9taXNlPHN0cmluZz4ge1xuICAgIGNvbnN0IGJsb2IgPSBhd2FpdCByZXNwb25zZS5ibG9iKCk7XG4gICAgY29uc3QgZGF0YVVSTCA9IGF3YWl0IChuZXcgUHJvbWlzZTxzdHJpbmc+KChyZXNvbHZlKSA9PiB7XG4gICAgICAgIGNvbnN0IHJlYWRlciA9IG5ldyBGaWxlUmVhZGVyKCk7XG4gICAgICAgIHJlYWRlci5vbmxvYWRlbmQgPSAoKSA9PiByZXNvbHZlKHJlYWRlci5yZXN1bHQgYXMgc3RyaW5nKTtcbiAgICAgICAgcmVhZGVyLnJlYWRBc0RhdGFVUkwoYmxvYik7XG4gICAgfSkpO1xuICAgIHJldHVybiBkYXRhVVJMO1xufVxuXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gbG9hZEFzVGV4dCh1cmw6IHN0cmluZywgbWltZVR5cGU/OiBzdHJpbmcsIG9yaWdpbj86IHN0cmluZyk6IFByb21pc2U8c3RyaW5nPiB7XG4gICAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBnZXRPS1Jlc3BvbnNlKHVybCwgbWltZVR5cGUsIG9yaWdpbik7XG4gICAgcmV0dXJuIGF3YWl0IHJlc3BvbnNlLnRleHQoKTtcbn1cbiIsImltcG9ydCB7bG9hZEFzRGF0YVVSTCwgbG9hZEFzVGV4dH0gZnJvbSAnLi4vLi4vdXRpbHMvbmV0d29yayc7XG5pbXBvcnQge2lzWE1MSHR0cFJlcXVlc3RTdXBwb3J0ZWQsIGlzRmV0Y2hTdXBwb3J0ZWR9IGZyb20gJy4uLy4uL3V0aWxzL3BsYXRmb3JtJztcbmltcG9ydCB7Z2V0U3RyaW5nU2l6ZX0gZnJvbSAnLi4vLi4vdXRpbHMvdGV4dCc7XG5pbXBvcnQge2dldER1cmF0aW9ufSBmcm9tICcuLi8uLi91dGlscy90aW1lJztcblxuZGVjbGFyZSBjb25zdCBfX1RFU1RfXzogYm9vbGVhbjtcblxuaW50ZXJmYWNlIFJlcXVlc3RQYXJhbXMge1xuICAgIHVybDogc3RyaW5nO1xuICAgIHRpbWVvdXQ/OiBudW1iZXI7XG59XG5cbnR5cGUgRmlsZUxvYWRlclJlc3BvbnNlID0ge2RhdGE6IHN0cmluZzsgZXJyb3I/OiBFcnJvcn0gfCB7ZGF0YT86IHN0cmluZzsgZXJyb3I6IEVycm9yfTtcblxuZXhwb3J0IGludGVyZmFjZSBGaWxlTG9hZGVyIHtcbiAgICBnZXQ6IChmZXRjaFJlcXVlc3RQYXJhbWV0ZXJzOiBGZXRjaFJlcXVlc3RQYXJhbWV0ZXJzKSA9PiBQcm9taXNlPEZpbGVMb2FkZXJSZXNwb25zZT47XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiByZWFkVGV4dChwYXJhbXM6IFJlcXVlc3RQYXJhbXMpOiBQcm9taXNlPHN0cmluZz4ge1xuICAgIHJldHVybiBuZXcgUHJvbWlzZSgocmVzb2x2ZSwgcmVqZWN0KSA9PiB7XG4gICAgICAgIGlmIChpc1hNTEh0dHBSZXF1ZXN0U3VwcG9ydGVkKSB7XG4gICAgICAgICAgICAvLyBVc2UgWE1MSHR0cFJlcXVlc3QgaWYgaXQgaXMgYXZhaWxhYmxlXG4gICAgICAgICAgICBjb25zdCByZXF1ZXN0ID0gbmV3IFhNTEh0dHBSZXF1ZXN0KCk7XG4gICAgICAgICAgICByZXF1ZXN0Lm92ZXJyaWRlTWltZVR5cGUoJ3RleHQvcGxhaW4nKTtcbiAgICAgICAgICAgIHJlcXVlc3Qub3BlbignR0VUJywgcGFyYW1zLnVybCwgdHJ1ZSk7XG4gICAgICAgICAgICByZXF1ZXN0Lm9ubG9hZCA9ICgpID0+IHtcbiAgICAgICAgICAgICAgICBpZiAocmVxdWVzdC5zdGF0dXMgPj0gMjAwICYmIHJlcXVlc3Quc3RhdHVzIDwgMzAwKSB7XG4gICAgICAgICAgICAgICAgICAgIHJlc29sdmUocmVxdWVzdC5yZXNwb25zZVRleHQpO1xuICAgICAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgICAgIHJlamVjdChuZXcgRXJyb3IoYCR7cmVxdWVzdC5zdGF0dXN9OiAke3JlcXVlc3Quc3RhdHVzVGV4dH1gKSk7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfTtcbiAgICAgICAgICAgIHJlcXVlc3Qub25lcnJvciA9ICgpID0+IHJlamVjdChuZXcgRXJyb3IoYCR7cmVxdWVzdC5zdGF0dXN9OiAke3JlcXVlc3Quc3RhdHVzVGV4dH1gKSk7XG4gICAgICAgICAgICBpZiAocGFyYW1zLnRpbWVvdXQpIHtcbiAgICAgICAgICAgICAgICByZXF1ZXN0LnRpbWVvdXQgPSBwYXJhbXMudGltZW91dDtcbiAgICAgICAgICAgICAgICByZXF1ZXN0Lm9udGltZW91dCA9ICgpID0+IHJlamVjdChuZXcgRXJyb3IoJ0ZpbGUgbG9hZGluZyBzdG9wcGVkIGR1ZSB0byB0aW1lb3V0JykpO1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgcmVxdWVzdC5zZW5kKCk7XG4gICAgICAgIH0gZWxzZSBpZiAoaXNGZXRjaFN1cHBvcnRlZCkge1xuICAgICAgICAgICAgLy8gWE1MSHR0cFJlcXVlc3QgaXMgbm90IGF2YWlsYWJsZSBpbiBTZXJ2aWNlIFdvcmtlciBjb250ZXh0cyBsaWtlXG4gICAgICAgICAgICAvLyBNYW5pZmVzdCBWMyBiYWNrZ3JvdW5kIGNvbnRleHRcbiAgICAgICAgICAgIGxldCBhYm9ydENvbnRyb2xsZXI6IEFib3J0Q29udHJvbGxlcjtcbiAgICAgICAgICAgIGxldCBzaWduYWw6IEFib3J0U2lnbmFsIHwgdW5kZWZpbmVkO1xuICAgICAgICAgICAgbGV0IHRpbWVkT3V0ID0gZmFsc2U7XG4gICAgICAgICAgICBpZiAocGFyYW1zLnRpbWVvdXQpIHtcbiAgICAgICAgICAgICAgICBhYm9ydENvbnRyb2xsZXIgPSBuZXcgQWJvcnRDb250cm9sbGVyKCk7XG4gICAgICAgICAgICAgICAgc2lnbmFsID0gYWJvcnRDb250cm9sbGVyLnNpZ25hbDtcbiAgICAgICAgICAgICAgICBzZXRUaW1lb3V0KCgpID0+IHtcbiAgICAgICAgICAgICAgICAgICAgYWJvcnRDb250cm9sbGVyLmFib3J0KCk7XG4gICAgICAgICAgICAgICAgICAgIHRpbWVkT3V0ID0gdHJ1ZTtcbiAgICAgICAgICAgICAgICB9LCBwYXJhbXMudGltZW91dCk7XG4gICAgICAgICAgICB9XG5cbiAgICAgICAgICAgIGZldGNoKHBhcmFtcy51cmwsIHtzaWduYWx9KVxuICAgICAgICAgICAgICAgIC50aGVuKChyZXNwb25zZSkgPT4ge1xuICAgICAgICAgICAgICAgICAgICBpZiAocmVzcG9uc2Uuc3RhdHVzID49IDIwMCAmJiAocmVzcG9uc2Uuc3RhdHVzIDwgMzAwKSkge1xuICAgICAgICAgICAgICAgICAgICAgICAgcmVzb2x2ZShyZXNwb25zZS50ZXh0KCkpO1xuICAgICAgICAgICAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgICAgICAgICAgICAgcmVqZWN0KG5ldyBFcnJvcihgJHtyZXNwb25zZS5zdGF0dXN9OiAke3Jlc3BvbnNlLnN0YXR1c1RleHR9YCkpO1xuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgfSkuY2F0Y2goKGVycm9yKSA9PiB7XG4gICAgICAgICAgICAgICAgICAgIGlmICh0aW1lZE91dCkge1xuICAgICAgICAgICAgICAgICAgICAgICAgcmVqZWN0KG5ldyBFcnJvcignRmlsZSBsb2FkaW5nIHN0b3BwZWQgZHVlIHRvIHRpbWVvdXQnKSk7XG4gICAgICAgICAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgICAgICAgICByZWplY3QoZXJyb3IpO1xuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgfSk7XG4gICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICByZWplY3QobmV3IEVycm9yKGBOZWl0aGVyIFhNTEh0dHBSZXF1ZXN0IG5vciBGZXRjaCBBUEkgYXJlIGFjY2Vzc2libGUhYCkpO1xuICAgICAgICB9XG4gICAgfSk7XG59XG5cbmludGVyZmFjZSBDYWNoZVJlY29yZCB7XG4gICAgZXhwaXJlczogbnVtYmVyO1xuICAgIHNpemU6IG51bWJlcjtcbiAgICB1cmw6IHN0cmluZztcbiAgICB2YWx1ZTogc3RyaW5nO1xufVxuXG5jbGFzcyBMaW1pdGVkQ2FjaGVTdG9yYWdlIHtcbiAgICAvLyBUT0RPOiByZW1vdmUgdHlwZSBjYXN0IGFmdGVyIGRlcGVuZGVuY3kgdXBkYXRlXG4gICAgcHJpdmF0ZSBzdGF0aWMgcmVhZG9ubHkgUVVPVEFfQllURVMgPSAoKCFfX1RFU1RfXyAmJiAobmF2aWdhdG9yIGFzIGFueSkuZGV2aWNlTWVtb3J5KSB8fCA0KSAqIDE2ICogMTAyNCAqIDEwMjQ7XG4gICAgcHJpdmF0ZSBzdGF0aWMgcmVhZG9ubHkgVFRMID0gZ2V0RHVyYXRpb24oe21pbnV0ZXM6IDEwfSk7XG4gICAgcHJpdmF0ZSBzdGF0aWMgcmVhZG9ubHkgQUxBUk1fTkFNRSA9ICduZXR3b3JrJztcblxuICAgIHByaXZhdGUgYnl0ZXNJblVzZSA9IDA7XG4gICAgcHJpdmF0ZSByZWNvcmRzID0gbmV3IE1hcDxzdHJpbmcsIENhY2hlUmVjb3JkPigpO1xuICAgIHByaXZhdGUgc3RhdGljIGFsYXJtSXNBY3RpdmUgPSBmYWxzZTtcblxuICAgIGNvbnN0cnVjdG9yKCkge1xuICAgICAgICBjaHJvbWUuYWxhcm1zLm9uQWxhcm0uYWRkTGlzdGVuZXIoYXN5bmMgKGFsYXJtKSA9PiB7XG4gICAgICAgICAgICBpZiAoYWxhcm0ubmFtZSA9PT0gTGltaXRlZENhY2hlU3RvcmFnZS5BTEFSTV9OQU1FKSB7XG4gICAgICAgICAgICAgICAgLy8gV2Ugc2NoZWR1bGUgb25seSBvbmUtdGltZSBhbGFybXMsIHNvIG9uY2UgaXQgZ29lcyBvZmYsXG4gICAgICAgICAgICAgICAgLy8gdGhlcmUgYXJlIG5vIG1vcmUgYWxhcm1zIHNjaGVkdWxlZC5cbiAgICAgICAgICAgICAgICBMaW1pdGVkQ2FjaGVTdG9yYWdlLmFsYXJtSXNBY3RpdmUgPSBmYWxzZTtcbiAgICAgICAgICAgICAgICB0aGlzLnJlbW92ZUV4cGlyZWRSZWNvcmRzKCk7XG4gICAgICAgICAgICB9XG4gICAgICAgIH0pO1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIGVuc3VyZUFsYXJtSXNTY2hlZHVsZWQoKXtcbiAgICAgICAgaWYgKCF0aGlzLmFsYXJtSXNBY3RpdmUpIHtcbiAgICAgICAgICAgIGNocm9tZS5hbGFybXMuY3JlYXRlKExpbWl0ZWRDYWNoZVN0b3JhZ2UuQUxBUk1fTkFNRSwge2RlbGF5SW5NaW51dGVzOiAxfSk7XG4gICAgICAgICAgICB0aGlzLmFsYXJtSXNBY3RpdmUgPSB0cnVlO1xuICAgICAgICB9XG4gICAgfVxuXG4gICAgaGFzKHVybDogc3RyaW5nKSB7XG4gICAgICAgIHJldHVybiB0aGlzLnJlY29yZHMuaGFzKHVybCk7XG4gICAgfVxuXG4gICAgZ2V0KHVybDogc3RyaW5nKSB7XG4gICAgICAgIGlmICh0aGlzLnJlY29yZHMuaGFzKHVybCkpIHtcbiAgICAgICAgICAgIGNvbnN0IHJlY29yZCA9IHRoaXMucmVjb3Jkcy5nZXQodXJsKSE7XG4gICAgICAgICAgICByZWNvcmQuZXhwaXJlcyA9IERhdGUubm93KCkgKyBMaW1pdGVkQ2FjaGVTdG9yYWdlLlRUTDtcbiAgICAgICAgICAgIHRoaXMucmVjb3Jkcy5kZWxldGUodXJsKTtcbiAgICAgICAgICAgIHRoaXMucmVjb3Jkcy5zZXQodXJsLCByZWNvcmQpO1xuICAgICAgICAgICAgcmV0dXJuIHJlY29yZC52YWx1ZTtcbiAgICAgICAgfVxuICAgICAgICByZXR1cm4gbnVsbDtcbiAgICB9XG5cbiAgICBzZXQodXJsOiBzdHJpbmcsIHZhbHVlOiBzdHJpbmcpIHtcbiAgICAgICAgTGltaXRlZENhY2hlU3RvcmFnZS5lbnN1cmVBbGFybUlzU2NoZWR1bGVkKCk7XG5cbiAgICAgICAgY29uc3Qgc2l6ZSA9IGdldFN0cmluZ1NpemUodmFsdWUpO1xuICAgICAgICBpZiAoc2l6ZSA+IExpbWl0ZWRDYWNoZVN0b3JhZ2UuUVVPVEFfQllURVMpIHtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuXG4gICAgICAgIGZvciAoY29uc3QgW3VybCwgcmVjb3JkXSBvZiB0aGlzLnJlY29yZHMpIHtcbiAgICAgICAgICAgIGlmICh0aGlzLmJ5dGVzSW5Vc2UgKyBzaXplID4gTGltaXRlZENhY2hlU3RvcmFnZS5RVU9UQV9CWVRFUykge1xuICAgICAgICAgICAgICAgIHRoaXMucmVjb3Jkcy5kZWxldGUodXJsKTtcbiAgICAgICAgICAgICAgICB0aGlzLmJ5dGVzSW5Vc2UgLT0gcmVjb3JkLnNpemU7XG4gICAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG5cbiAgICAgICAgaWYgKHRoaXMucmVjb3Jkcy5zaXplID09PSAwKSB7XG4gICAgICAgICAgICB0aGlzLmJ5dGVzSW5Vc2UgPSAwO1xuICAgICAgICB9XG5cbiAgICAgICAgY29uc3QgZXhwaXJlcyA9IERhdGUubm93KCkgKyBMaW1pdGVkQ2FjaGVTdG9yYWdlLlRUTDtcbiAgICAgICAgdGhpcy5yZWNvcmRzLnNldCh1cmwsIHt1cmwsIHZhbHVlLCBzaXplLCBleHBpcmVzfSk7XG4gICAgICAgIHRoaXMuYnl0ZXNJblVzZSArPSBzaXplO1xuICAgIH1cblxuICAgIHByaXZhdGUgcmVtb3ZlRXhwaXJlZFJlY29yZHMoKSB7XG4gICAgICAgIGNvbnN0IG5vdyA9IERhdGUubm93KCk7XG4gICAgICAgIGZvciAoY29uc3QgW3VybCwgcmVjb3JkXSBvZiB0aGlzLnJlY29yZHMpIHtcbiAgICAgICAgICAgIGlmIChyZWNvcmQuZXhwaXJlcyA8IG5vdykge1xuICAgICAgICAgICAgICAgIHRoaXMucmVjb3Jkcy5kZWxldGUodXJsKTtcbiAgICAgICAgICAgICAgICB0aGlzLmJ5dGVzSW5Vc2UgLT0gcmVjb3JkLnNpemU7XG4gICAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG5cbiAgICAgICAgaWYgKHRoaXMucmVjb3Jkcy5zaXplID09PSAwKSB7XG4gICAgICAgICAgICB0aGlzLmJ5dGVzSW5Vc2UgPSAwO1xuICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgTGltaXRlZENhY2hlU3RvcmFnZS5lbnN1cmVBbGFybUlzU2NoZWR1bGVkKCk7XG4gICAgICAgIH1cbiAgICB9XG59XG5cbmZ1bmN0aW9uIGNyZWF0ZUxpbWl0ZXIoKSB7XG4gICAgY29uc3QgbG9hZGluZ1VybHMgPSBuZXcgU2V0PHN0cmluZz4oKTtcbiAgICBjb25zdCBhd2FpdGluZ1VybHMgPSBuZXcgTWFwPHN0cmluZywgU2V0PChyZXNwb25zZTogRmlsZUxvYWRlclJlc3BvbnNlKSA9PiB2b2lkPj4oKTtcblxuICAgIGZ1bmN0aW9uIGxvYWRpbmcodXJsOiBzdHJpbmcpIHtcbiAgICAgICAgY29uc3QgcmVzdWx0ID0gbG9hZGluZ1VybHMuaGFzKHVybCk7XG4gICAgICAgIGxvYWRpbmdVcmxzLmFkZCh1cmwpO1xuICAgICAgICByZXR1cm4gcmVzdWx0O1xuICAgIH1cblxuICAgIGFzeW5jIGZ1bmN0aW9uIHdhaXQodXJsOiBzdHJpbmcpIHtcbiAgICAgICAgcmV0dXJuIG5ldyBQcm9taXNlPEZpbGVMb2FkZXJSZXNwb25zZT4oKHJlc29sdmUpID0+IHtcbiAgICAgICAgICAgIGlmICghYXdhaXRpbmdVcmxzLmhhcyh1cmwpKSB7XG4gICAgICAgICAgICAgICAgYXdhaXRpbmdVcmxzLnNldCh1cmwsIG5ldyBTZXQoKSk7XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICBhd2FpdGluZ1VybHMuZ2V0KHVybCk/LmFkZChyZXNvbHZlKTtcbiAgICAgICAgfSk7XG4gICAgfVxuXG4gICAgYXN5bmMgZnVuY3Rpb24gbG9hZGVkKHVybDogc3RyaW5nLCBkYXRhOiBzdHJpbmcpIHtcbiAgICAgICAgbG9hZGluZ1VybHMuZGVsZXRlKHVybCk7XG4gICAgICAgIGlmIChhd2FpdGluZ1VybHMuaGFzKHVybCkpIHtcbiAgICAgICAgICAgIGNvbnN0IHJlc3BvbnNlID0ge2RhdGF9O1xuICAgICAgICAgICAgYXdhaXRpbmdVcmxzLmdldCh1cmwpIS5mb3JFYWNoKChjYWxsYmFjaykgPT4gY2FsbGJhY2socmVzcG9uc2UpKTtcbiAgICAgICAgICAgIGF3YWl0aW5nVXJscy5kZWxldGUodXJsKTtcbiAgICAgICAgfVxuICAgIH1cblxuICAgIGFzeW5jIGZ1bmN0aW9uIGZhaWxlZCh1cmw6IHN0cmluZywgZXJyb3I6IEVycm9yKSB7XG4gICAgICAgIGxvYWRpbmdVcmxzLmRlbGV0ZSh1cmwpO1xuICAgICAgICBpZiAoYXdhaXRpbmdVcmxzLmhhcyh1cmwpKSB7XG4gICAgICAgICAgICBjb25zdCByZXNwb25zZSA9IHtlcnJvcn07XG4gICAgICAgICAgICBhd2FpdGluZ1VybHMuZ2V0KHVybCkhLmZvckVhY2goKGNhbGxiYWNrKSA9PiBjYWxsYmFjayhyZXNwb25zZSkpO1xuICAgICAgICAgICAgYXdhaXRpbmdVcmxzLmRlbGV0ZSh1cmwpO1xuICAgICAgICB9XG4gICAgfVxuXG4gICAgcmV0dXJuIHtsb2FkaW5nLCB3YWl0LCBsb2FkZWQsIGZhaWxlZH07XG59XG5cbmV4cG9ydCBpbnRlcmZhY2UgRmV0Y2hSZXF1ZXN0UGFyYW1ldGVycyB7XG4gICAgdXJsOiBzdHJpbmc7XG4gICAgcmVzcG9uc2VUeXBlOiAnZGF0YS11cmwnIHwgJ3RleHQnO1xuICAgIG1pbWVUeXBlPzogc3RyaW5nO1xuICAgIG9yaWdpbj86IHN0cmluZztcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGNyZWF0ZUZpbGVMb2FkZXIoKTogRmlsZUxvYWRlciB7XG4gICAgY29uc3QgY2FjaGVzID0ge1xuICAgICAgICAnZGF0YS11cmwnOiBuZXcgTGltaXRlZENhY2hlU3RvcmFnZSgpLFxuICAgICAgICAndGV4dCc6IG5ldyBMaW1pdGVkQ2FjaGVTdG9yYWdlKCksXG4gICAgfTtcblxuICAgIGNvbnN0IGxvYWRlcnMgPSB7XG4gICAgICAgICdkYXRhLXVybCc6IGxvYWRBc0RhdGFVUkwsXG4gICAgICAgICd0ZXh0JzogbG9hZEFzVGV4dCxcbiAgICB9O1xuXG4gICAgY29uc3QgbGltaXRlcnMgPSB7XG4gICAgICAgICdkYXRhLXVybCc6IGNyZWF0ZUxpbWl0ZXIoKSxcbiAgICAgICAgJ3RleHQnOiBjcmVhdGVMaW1pdGVyKCksXG4gICAgfTtcblxuICAgIGFzeW5jIGZ1bmN0aW9uIGdldCh7dXJsLCByZXNwb25zZVR5cGUsIG1pbWVUeXBlLCBvcmlnaW59OiBGZXRjaFJlcXVlc3RQYXJhbWV0ZXJzKTogUHJvbWlzZTxGaWxlTG9hZGVyUmVzcG9uc2U+IHtcbiAgICAgICAgY29uc3QgY2FjaGUgPSBjYWNoZXNbcmVzcG9uc2VUeXBlXTtcbiAgICAgICAgY29uc3QgbG9hZCA9IGxvYWRlcnNbcmVzcG9uc2VUeXBlXTtcbiAgICAgICAgY29uc3QgbGltaXRlciA9IGxpbWl0ZXJzW3Jlc3BvbnNlVHlwZV07XG4gICAgICAgIGlmIChjYWNoZS5oYXModXJsKSkge1xuICAgICAgICAgICAgY29uc3QgZGF0YSA9IGNhY2hlLmdldCh1cmwpITtcbiAgICAgICAgICAgIHJldHVybiB7ZGF0YX07XG4gICAgICAgIH1cblxuICAgICAgICBpZiAobGltaXRlci5sb2FkaW5nKHVybCkpIHtcbiAgICAgICAgICAgIHJldHVybiBsaW1pdGVyLndhaXQodXJsKTtcbiAgICAgICAgfVxuXG4gICAgICAgIHRyeSB7XG4gICAgICAgICAgICBjb25zdCBkYXRhID0gYXdhaXQgbG9hZCh1cmwsIG1pbWVUeXBlLCBvcmlnaW4pO1xuICAgICAgICAgICAgY2FjaGUuc2V0KHVybCwgZGF0YSk7XG4gICAgICAgICAgICBsaW1pdGVyLmxvYWRlZCh1cmwsIGRhdGEpO1xuICAgICAgICAgICAgcmV0dXJuIHtkYXRhfTtcbiAgICAgICAgfSBjYXRjaCAoZXJyb3IpIHtcbiAgICAgICAgICAgIGxpbWl0ZXIuZmFpbGVkKHVybCwgZXJyb3IpO1xuICAgICAgICAgICAgcmV0dXJuIHtlcnJvcn07XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICByZXR1cm4ge2dldH07XG59XG4iLCJpbXBvcnQge0RFRkFVTFRfQ09MT1JTQ0hFTUV9IGZyb20gJy4uL2RlZmF1bHRzJztcbmltcG9ydCB7aW5kZXhTaXRlc0ZpeGVzQ29uZmlnfSBmcm9tICcuLi9nZW5lcmF0b3JzL3V0aWxzL3BhcnNlJztcbmltcG9ydCB0eXBlIHtTaXRlRml4ZXNJbmRleH0gZnJvbSAnLi4vZ2VuZXJhdG9ycy91dGlscy9wYXJzZSc7XG5pbXBvcnQgdHlwZSB7UGFyc2VkQ29sb3JTY2hlbWVDb25maWd9IGZyb20gJy4uL3V0aWxzL2NvbG9yc2NoZW1lLXBhcnNlcic7XG5pbXBvcnQge3BhcnNlQ29sb3JTY2hlbWVDb25maWd9IGZyb20gJy4uL3V0aWxzL2NvbG9yc2NoZW1lLXBhcnNlcic7XG5pbXBvcnQge0NPTkZJR19VUkxfQkFTRX0gZnJvbSAnLi4vdXRpbHMvbGlua3MnO1xuaW1wb3J0IHtwYXJzZUFycmF5fSBmcm9tICcuLi91dGlscy90ZXh0JztcbmltcG9ydCB7Z2V0RHVyYXRpb259IGZyb20gJy4uL3V0aWxzL3RpbWUnO1xuaW1wb3J0IHtpbmRleFVSTFRlbXBsYXRlTGlzdCwgaXNVUkxJbkluZGV4ZWRMaXN0fSBmcm9tICcuLi91dGlscy91cmwnO1xuaW1wb3J0IHR5cGUge1VSTFRlbXBsYXRlSW5kZXh9IGZyb20gJy4uL3V0aWxzL3VybCc7XG5pbXBvcnQgVXNlclN0b3JhZ2UgZnJvbSAnLi91c2VyLXN0b3JhZ2UnO1xuaW1wb3J0IHtsb2dXYXJufSBmcm9tICcuL3V0aWxzL2xvZyc7XG5pbXBvcnQge3JlYWRUZXh0fSBmcm9tICcuL3V0aWxzL25ldHdvcmsnO1xuXG5jb25zdCBDT05GSUdfVVJMcyA9IHtcbiAgICBkYXJrU2l0ZXM6IHtcbiAgICAgICAgcmVtb3RlOiBgJHtDT05GSUdfVVJMX0JBU0V9L2Rhcmstc2l0ZXMuY29uZmlnYCxcbiAgICAgICAgbG9jYWw6ICcuLi9jb25maWcvZGFyay1zaXRlcy5jb25maWcnLFxuICAgIH0sXG4gICAgZHluYW1pY1RoZW1lRml4ZXM6IHtcbiAgICAgICAgcmVtb3RlOiBgJHtDT05GSUdfVVJMX0JBU0V9L2R5bmFtaWMtdGhlbWUtZml4ZXMuY29uZmlnYCxcbiAgICAgICAgbG9jYWw6ICcuLi9jb25maWcvZHluYW1pYy10aGVtZS1maXhlcy5jb25maWcnLFxuICAgIH0sXG4gICAgaW52ZXJzaW9uRml4ZXM6IHtcbiAgICAgICAgcmVtb3RlOiBgJHtDT05GSUdfVVJMX0JBU0V9L2ludmVyc2lvbi1maXhlcy5jb25maWdgLFxuICAgICAgICBsb2NhbDogJy4uL2NvbmZpZy9pbnZlcnNpb24tZml4ZXMuY29uZmlnJyxcbiAgICB9LFxuICAgIHN0YXRpY1RoZW1lczoge1xuICAgICAgICByZW1vdGU6IGAke0NPTkZJR19VUkxfQkFTRX0vc3RhdGljLXRoZW1lcy5jb25maWdgLFxuICAgICAgICBsb2NhbDogJy4uL2NvbmZpZy9zdGF0aWMtdGhlbWVzLmNvbmZpZycsXG4gICAgfSxcbiAgICBjb2xvclNjaGVtZXM6IHtcbiAgICAgICAgcmVtb3RlOiBgJHtDT05GSUdfVVJMX0JBU0V9L2NvbG9yLXNjaGVtZXMuZHJjb25mYCxcbiAgICAgICAgbG9jYWw6ICcuLi9jb25maWcvY29sb3Itc2NoZW1lcy5kcmNvbmYnLFxuICAgIH0sXG4gICAgZGV0ZWN0b3JIaW50czoge1xuICAgICAgICByZW1vdGU6IGAke0NPTkZJR19VUkxfQkFTRX0vZGV0ZWN0b3ItaGludHMuY29uZmlnYCxcbiAgICAgICAgbG9jYWw6ICcuLi9jb25maWcvZGV0ZWN0b3ItaGludHMuY29uZmlnJyxcbiAgICB9LFxufTtcblxuY29uc3QgUkVNT1RFX1RJTUVPVVRfTVMgPSBnZXREdXJhdGlvbih7c2Vjb25kczogMTB9KTtcblxuaW50ZXJmYWNlIExvY2FsQ29uZmlnIHtcbiAgICBsb2NhbDogYm9vbGVhbjtcbn1cblxuaW50ZXJmYWNlIENvbmZpZyBleHRlbmRzIExvY2FsQ29uZmlnIHtcbiAgICBuYW1lPzogc3RyaW5nO1xuICAgIGxvY2FsOiBib29sZWFuO1xuICAgIGxvY2FsVVJMOiBzdHJpbmc7XG4gICAgcmVtb3RlVVJMPzogc3RyaW5nO1xufVxuXG5leHBvcnQgZGVmYXVsdCBjbGFzcyBDb25maWdNYW5hZ2VyIHtcbiAgICBwcml2YXRlIHN0YXRpYyBEQVJLX1NJVEVTX0lOREVYOiBVUkxUZW1wbGF0ZUluZGV4IHwgbnVsbDtcbiAgICBzdGF0aWMgREVURUNUT1JfSElOVFNfSU5ERVg6IFNpdGVGaXhlc0luZGV4IHwgbnVsbDtcbiAgICBzdGF0aWMgREVURUNUT1JfSElOVFNfUkFXOiBzdHJpbmcgfCBudWxsO1xuICAgIHN0YXRpYyBEWU5BTUlDX1RIRU1FX0ZJWEVTX0lOREVYOiBTaXRlRml4ZXNJbmRleCB8IG51bGw7XG4gICAgc3RhdGljIERZTkFNSUNfVEhFTUVfRklYRVNfUkFXOiBzdHJpbmcgfCBudWxsO1xuICAgIHN0YXRpYyBJTlZFUlNJT05fRklYRVNfSU5ERVg6IFNpdGVGaXhlc0luZGV4IHwgbnVsbDtcbiAgICBzdGF0aWMgSU5WRVJTSU9OX0ZJWEVTX1JBVzogc3RyaW5nIHwgbnVsbDtcbiAgICBzdGF0aWMgU1RBVElDX1RIRU1FU19JTkRFWDogU2l0ZUZpeGVzSW5kZXggfCBudWxsO1xuICAgIHN0YXRpYyBTVEFUSUNfVEhFTUVTX1JBVzogc3RyaW5nIHwgbnVsbDtcbiAgICBzdGF0aWMgQ09MT1JfU0NIRU1FU19SQVc6IFBhcnNlZENvbG9yU2NoZW1lQ29uZmlnIHwgbnVsbDtcblxuICAgIHN0YXRpYyByYXcgPSB7XG4gICAgICAgIGRhcmtTaXRlczogbnVsbCBhcyBzdHJpbmcgfCBudWxsLFxuICAgICAgICBkZXRlY3RvckhpbnRzOiBudWxsIGFzIHN0cmluZyB8IG51bGwsXG4gICAgICAgIGR5bmFtaWNUaGVtZUZpeGVzOiBudWxsIGFzIHN0cmluZyB8IG51bGwsXG4gICAgICAgIGludmVyc2lvbkZpeGVzOiBudWxsIGFzIHN0cmluZyB8IG51bGwsXG4gICAgICAgIHN0YXRpY1RoZW1lczogbnVsbCBhcyBzdHJpbmcgfCBudWxsLFxuICAgICAgICBjb2xvclNjaGVtZXM6IG51bGwgYXMgc3RyaW5nIHwgbnVsbCxcbiAgICB9O1xuXG4gICAgc3RhdGljIG92ZXJyaWRlcyA9IHtcbiAgICAgICAgZGFya1NpdGVzOiBudWxsIGFzIHN0cmluZyB8IG51bGwsXG4gICAgICAgIGRldGVjdG9ySGludHM6IG51bGwgYXMgc3RyaW5nIHwgbnVsbCxcbiAgICAgICAgZHluYW1pY1RoZW1lRml4ZXM6IG51bGwgYXMgc3RyaW5nIHwgbnVsbCxcbiAgICAgICAgaW52ZXJzaW9uRml4ZXM6IG51bGwgYXMgc3RyaW5nIHwgbnVsbCxcbiAgICAgICAgc3RhdGljVGhlbWVzOiBudWxsIGFzIHN0cmluZyB8IG51bGwsXG4gICAgfTtcblxuICAgIHByaXZhdGUgc3RhdGljIGFzeW5jIGxvYWRDb25maWcoe1xuICAgICAgICBuYW1lLFxuICAgICAgICBsb2NhbCxcbiAgICAgICAgbG9jYWxVUkwsXG4gICAgICAgIHJlbW90ZVVSTCxcbiAgICB9OiBDb25maWcpIHtcbiAgICAgICAgbGV0ICRjb25maWc6IHN0cmluZztcbiAgICAgICAgY29uc3QgbG9hZExvY2FsID0gYXN5bmMgKCkgPT4gYXdhaXQgcmVhZFRleHQoe3VybDogbG9jYWxVUkx9KTtcbiAgICAgICAgaWYgKGxvY2FsKSB7XG4gICAgICAgICAgICAkY29uZmlnID0gYXdhaXQgbG9hZExvY2FsKCk7XG4gICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICB0cnkge1xuICAgICAgICAgICAgICAgICRjb25maWcgPSBhd2FpdCByZWFkVGV4dCh7XG4gICAgICAgICAgICAgICAgICAgIHVybDogYCR7cmVtb3RlVVJMfT9ub2NhY2hlPSR7RGF0ZS5ub3coKX1gLFxuICAgICAgICAgICAgICAgICAgICB0aW1lb3V0OiBSRU1PVEVfVElNRU9VVF9NUyxcbiAgICAgICAgICAgICAgICB9KTtcbiAgICAgICAgICAgIH0gY2F0Y2ggKGVycikge1xuICAgICAgICAgICAgICAgIGNvbnNvbGUuZXJyb3IoYCR7bmFtZX0gcmVtb3RlIGxvYWQgZXJyb3JgLCBlcnIpO1xuICAgICAgICAgICAgICAgICRjb25maWcgPSBhd2FpdCBsb2FkTG9jYWwoKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgICByZXR1cm4gJGNvbmZpZztcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBhc3luYyBsb2FkQ29sb3JTY2hlbWVzKHtsb2NhbH06IExvY2FsQ29uZmlnKSB7XG4gICAgICAgIGNvbnN0ICRjb25maWcgPSBhd2FpdCBDb25maWdNYW5hZ2VyLmxvYWRDb25maWcoe1xuICAgICAgICAgICAgbmFtZTogJ0NvbG9yIFNjaGVtZXMnLFxuICAgICAgICAgICAgbG9jYWwsXG4gICAgICAgICAgICBsb2NhbFVSTDogQ09ORklHX1VSTHMuY29sb3JTY2hlbWVzLmxvY2FsLFxuICAgICAgICAgICAgcmVtb3RlVVJMOiBDT05GSUdfVVJMcy5jb2xvclNjaGVtZXMucmVtb3RlLFxuICAgICAgICB9KTtcbiAgICAgICAgQ29uZmlnTWFuYWdlci5yYXcuY29sb3JTY2hlbWVzID0gJGNvbmZpZztcbiAgICAgICAgQ29uZmlnTWFuYWdlci5oYW5kbGVDb2xvclNjaGVtZXMoKTtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBhc3luYyBsb2FkRGFya1NpdGVzKHtsb2NhbH06IExvY2FsQ29uZmlnKSB7XG4gICAgICAgIGNvbnN0IHNpdGVzID0gYXdhaXQgQ29uZmlnTWFuYWdlci5sb2FkQ29uZmlnKHtcbiAgICAgICAgICAgIG5hbWU6ICdEYXJrIFNpdGVzJyxcbiAgICAgICAgICAgIGxvY2FsLFxuICAgICAgICAgICAgbG9jYWxVUkw6IENPTkZJR19VUkxzLmRhcmtTaXRlcy5sb2NhbCxcbiAgICAgICAgICAgIHJlbW90ZVVSTDogQ09ORklHX1VSTHMuZGFya1NpdGVzLnJlbW90ZSxcbiAgICAgICAgfSk7XG4gICAgICAgIENvbmZpZ01hbmFnZXIucmF3LmRhcmtTaXRlcyA9IHNpdGVzO1xuICAgICAgICBDb25maWdNYW5hZ2VyLmhhbmRsZURhcmtTaXRlcygpO1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIGFzeW5jIGxvYWREZXRlY3RvckhpbnRzKHtsb2NhbH06IExvY2FsQ29uZmlnKSB7XG4gICAgICAgIGNvbnN0ICRjb25maWcgPSBhd2FpdCBDb25maWdNYW5hZ2VyLmxvYWRDb25maWcoe1xuICAgICAgICAgICAgbmFtZTogJ0RldGVjdG9yIEhpbnRzJyxcbiAgICAgICAgICAgIGxvY2FsLFxuICAgICAgICAgICAgbG9jYWxVUkw6IENPTkZJR19VUkxzLmRldGVjdG9ySGludHMubG9jYWwsXG4gICAgICAgICAgICByZW1vdGVVUkw6IENPTkZJR19VUkxzLmRldGVjdG9ySGludHMucmVtb3RlLFxuICAgICAgICB9KTtcbiAgICAgICAgQ29uZmlnTWFuYWdlci5yYXcuZGV0ZWN0b3JIaW50cyA9ICRjb25maWc7XG4gICAgICAgIENvbmZpZ01hbmFnZXIuaGFuZGxlRGV0ZWN0b3JIaW50cygpO1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIGFzeW5jIGxvYWREeW5hbWljVGhlbWVGaXhlcyh7bG9jYWx9OiBMb2NhbENvbmZpZykge1xuICAgICAgICBjb25zdCBmaXhlcyA9IGF3YWl0IENvbmZpZ01hbmFnZXIubG9hZENvbmZpZyh7XG4gICAgICAgICAgICBuYW1lOiAnRHluYW1pYyBUaGVtZSBGaXhlcycsXG4gICAgICAgICAgICBsb2NhbCxcbiAgICAgICAgICAgIGxvY2FsVVJMOiBDT05GSUdfVVJMcy5keW5hbWljVGhlbWVGaXhlcy5sb2NhbCxcbiAgICAgICAgICAgIHJlbW90ZVVSTDogQ09ORklHX1VSTHMuZHluYW1pY1RoZW1lRml4ZXMucmVtb3RlLFxuICAgICAgICB9KTtcbiAgICAgICAgQ29uZmlnTWFuYWdlci5yYXcuZHluYW1pY1RoZW1lRml4ZXMgPSBmaXhlcztcbiAgICAgICAgQ29uZmlnTWFuYWdlci5oYW5kbGVEeW5hbWljVGhlbWVGaXhlcygpO1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIGFzeW5jIGxvYWRJbnZlcnNpb25GaXhlcyh7bG9jYWx9OiBMb2NhbENvbmZpZykge1xuICAgICAgICBjb25zdCBmaXhlcyA9IGF3YWl0IENvbmZpZ01hbmFnZXIubG9hZENvbmZpZyh7XG4gICAgICAgICAgICBuYW1lOiAnSW52ZXJzaW9uIEZpeGVzJyxcbiAgICAgICAgICAgIGxvY2FsLFxuICAgICAgICAgICAgbG9jYWxVUkw6IENPTkZJR19VUkxzLmludmVyc2lvbkZpeGVzLmxvY2FsLFxuICAgICAgICAgICAgcmVtb3RlVVJMOiBDT05GSUdfVVJMcy5pbnZlcnNpb25GaXhlcy5yZW1vdGUsXG4gICAgICAgIH0pO1xuICAgICAgICBDb25maWdNYW5hZ2VyLnJhdy5pbnZlcnNpb25GaXhlcyA9IGZpeGVzO1xuICAgICAgICBDb25maWdNYW5hZ2VyLmhhbmRsZUludmVyc2lvbkZpeGVzKCk7XG4gICAgfVxuXG4gICAgcHJpdmF0ZSBzdGF0aWMgYXN5bmMgbG9hZFN0YXRpY1RoZW1lcyh7bG9jYWx9OiBMb2NhbENvbmZpZykge1xuICAgICAgICBjb25zdCB0aGVtZXMgPSBhd2FpdCBDb25maWdNYW5hZ2VyLmxvYWRDb25maWcoe1xuICAgICAgICAgICAgbmFtZTogJ1N0YXRpYyBUaGVtZXMnLFxuICAgICAgICAgICAgbG9jYWwsXG4gICAgICAgICAgICBsb2NhbFVSTDogQ09ORklHX1VSTHMuc3RhdGljVGhlbWVzLmxvY2FsLFxuICAgICAgICAgICAgcmVtb3RlVVJMOiBDT05GSUdfVVJMcy5zdGF0aWNUaGVtZXMucmVtb3RlLFxuICAgICAgICB9KTtcbiAgICAgICAgQ29uZmlnTWFuYWdlci5yYXcuc3RhdGljVGhlbWVzID0gdGhlbWVzO1xuICAgICAgICBDb25maWdNYW5hZ2VyLmhhbmRsZVN0YXRpY1RoZW1lcygpO1xuICAgIH1cblxuICAgIHN0YXRpYyBhc3luYyBsb2FkKGNvbmZpZz86IExvY2FsQ29uZmlnKTogUHJvbWlzZTx2b2lkPiB7XG4gICAgICAgIGlmICghY29uZmlnKSB7XG4gICAgICAgICAgICBhd2FpdCBVc2VyU3RvcmFnZS5sb2FkU2V0dGluZ3MoKTtcbiAgICAgICAgICAgIGNvbmZpZyA9IHtcbiAgICAgICAgICAgICAgICBsb2NhbDogIVVzZXJTdG9yYWdlLnNldHRpbmdzLnN5bmNTaXRlc0ZpeGVzLFxuICAgICAgICAgICAgfTtcbiAgICAgICAgfVxuXG4gICAgICAgIGF3YWl0IFByb21pc2UuYWxsKFtcbiAgICAgICAgICAgIENvbmZpZ01hbmFnZXIubG9hZENvbG9yU2NoZW1lcyhjb25maWcpLFxuICAgICAgICAgICAgQ29uZmlnTWFuYWdlci5sb2FkRGFya1NpdGVzKGNvbmZpZyksXG4gICAgICAgICAgICBDb25maWdNYW5hZ2VyLmxvYWREZXRlY3RvckhpbnRzKGNvbmZpZyksXG4gICAgICAgICAgICBDb25maWdNYW5hZ2VyLmxvYWREeW5hbWljVGhlbWVGaXhlcyhjb25maWcpLFxuICAgICAgICAgICAgQ29uZmlnTWFuYWdlci5sb2FkSW52ZXJzaW9uRml4ZXMoY29uZmlnKSxcbiAgICAgICAgICAgIENvbmZpZ01hbmFnZXIubG9hZFN0YXRpY1RoZW1lcyhjb25maWcpLFxuICAgICAgICBdKS5jYXRjaCgoZXJyKSA9PiBjb25zb2xlLmVycm9yKCdGYXRhbGl0eScsIGVycikpO1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIGhhbmRsZUNvbG9yU2NoZW1lcygpOiB2b2lkIHtcbiAgICAgICAgY29uc3QgJGNvbmZpZyA9IENvbmZpZ01hbmFnZXIucmF3LmNvbG9yU2NoZW1lcztcbiAgICAgICAgY29uc3Qge3Jlc3VsdCwgZXJyb3J9ID0gcGFyc2VDb2xvclNjaGVtZUNvbmZpZygkY29uZmlnIHx8ICcnKTtcbiAgICAgICAgaWYgKGVycm9yKSB7XG4gICAgICAgICAgICBsb2dXYXJuKGBDb2xvciBTY2hlbWVzIHBhcnNlIGVycm9yLCBkZWZhdWx0aW5nIHRvIGZhbGxiYWNrLiAke2Vycm9yfS5gKTtcbiAgICAgICAgICAgIENvbmZpZ01hbmFnZXIuQ09MT1JfU0NIRU1FU19SQVcgPSBERUZBVUxUX0NPTE9SU0NIRU1FO1xuICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICB9XG4gICAgICAgIENvbmZpZ01hbmFnZXIuQ09MT1JfU0NIRU1FU19SQVcgPSByZXN1bHQ7XG4gICAgfVxuXG4gICAgcHJpdmF0ZSBzdGF0aWMgaGFuZGxlRGFya1NpdGVzKCk6IHZvaWQge1xuICAgICAgICBjb25zdCAkc2l0ZXMgPSBDb25maWdNYW5hZ2VyLm92ZXJyaWRlcy5kYXJrU2l0ZXMgfHwgQ29uZmlnTWFuYWdlci5yYXcuZGFya1NpdGVzO1xuICAgICAgICBjb25zdCB0ZW1wbGF0ZXMgPSBwYXJzZUFycmF5KCRzaXRlcyEpO1xuICAgICAgICBDb25maWdNYW5hZ2VyLkRBUktfU0lURVNfSU5ERVggPSBpbmRleFVSTFRlbXBsYXRlTGlzdCh0ZW1wbGF0ZXMpO1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIGhhbmRsZURldGVjdG9ySGludHMoKTogdm9pZCB7XG4gICAgICAgIGNvbnN0ICRoaW50cyA9IENvbmZpZ01hbmFnZXIub3ZlcnJpZGVzLmRldGVjdG9ySGludHMgfHwgQ29uZmlnTWFuYWdlci5yYXcuZGV0ZWN0b3JIaW50cyB8fCAnJztcbiAgICAgICAgQ29uZmlnTWFuYWdlci5ERVRFQ1RPUl9ISU5UU19JTkRFWCA9IGluZGV4U2l0ZXNGaXhlc0NvbmZpZygkaGludHMpO1xuICAgICAgICBDb25maWdNYW5hZ2VyLkRFVEVDVE9SX0hJTlRTX1JBVyA9ICRoaW50cztcbiAgICB9XG5cbiAgICBzdGF0aWMgaGFuZGxlRHluYW1pY1RoZW1lRml4ZXMoKTogdm9pZCB7XG4gICAgICAgIGNvbnN0ICRmaXhlcyA9IENvbmZpZ01hbmFnZXIub3ZlcnJpZGVzLmR5bmFtaWNUaGVtZUZpeGVzIHx8IENvbmZpZ01hbmFnZXIucmF3LmR5bmFtaWNUaGVtZUZpeGVzIHx8ICcnO1xuICAgICAgICBDb25maWdNYW5hZ2VyLkRZTkFNSUNfVEhFTUVfRklYRVNfSU5ERVggPSBpbmRleFNpdGVzRml4ZXNDb25maWcoJGZpeGVzKTtcbiAgICAgICAgQ29uZmlnTWFuYWdlci5EWU5BTUlDX1RIRU1FX0ZJWEVTX1JBVyA9ICRmaXhlcztcbiAgICB9XG5cbiAgICBzdGF0aWMgaGFuZGxlSW52ZXJzaW9uRml4ZXMoKTogdm9pZCB7XG4gICAgICAgIGNvbnN0ICRmaXhlcyA9IENvbmZpZ01hbmFnZXIub3ZlcnJpZGVzLmludmVyc2lvbkZpeGVzIHx8IENvbmZpZ01hbmFnZXIucmF3LmludmVyc2lvbkZpeGVzIHx8ICcnO1xuICAgICAgICBDb25maWdNYW5hZ2VyLklOVkVSU0lPTl9GSVhFU19JTkRFWCA9IGluZGV4U2l0ZXNGaXhlc0NvbmZpZygkZml4ZXMpO1xuICAgICAgICBDb25maWdNYW5hZ2VyLklOVkVSU0lPTl9GSVhFU19SQVcgPSAkZml4ZXM7XG4gICAgfVxuXG4gICAgc3RhdGljIGhhbmRsZVN0YXRpY1RoZW1lcygpOiB2b2lkIHtcbiAgICAgICAgY29uc3QgJHRoZW1lcyA9IENvbmZpZ01hbmFnZXIub3ZlcnJpZGVzLnN0YXRpY1RoZW1lcyB8fCBDb25maWdNYW5hZ2VyLnJhdy5zdGF0aWNUaGVtZXMgfHwgJyc7XG4gICAgICAgIENvbmZpZ01hbmFnZXIuU1RBVElDX1RIRU1FU19JTkRFWCA9IGluZGV4U2l0ZXNGaXhlc0NvbmZpZygkdGhlbWVzKTtcbiAgICAgICAgQ29uZmlnTWFuYWdlci5TVEFUSUNfVEhFTUVTX1JBVyA9ICR0aGVtZXM7XG4gICAgfVxuXG4gICAgc3RhdGljIGlzVVJMSW5EYXJrTGlzdCh1cmw6IHN0cmluZyk6IGJvb2xlYW4ge1xuICAgICAgICBpZiAoIUNvbmZpZ01hbmFnZXIuREFSS19TSVRFU19JTkRFWCkge1xuICAgICAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgICAgICB9XG4gICAgICAgIHJldHVybiBpc1VSTEluSW5kZXhlZExpc3QodXJsLCBDb25maWdNYW5hZ2VyLkRBUktfU0lURVNfSU5ERVgpO1xuICAgIH1cbn1cbiIsImltcG9ydCB7cGFyc2VJbnZlcnNpb25GaXhlcywgZm9ybWF0SW52ZXJzaW9uRml4ZXN9IGZyb20gJy4uL2dlbmVyYXRvcnMvY3NzLWZpbHRlcic7XG5pbXBvcnQge3BhcnNlRHluYW1pY1RoZW1lRml4ZXMsIGZvcm1hdER5bmFtaWNUaGVtZUZpeGVzfSBmcm9tICcuLi9nZW5lcmF0b3JzL2R5bmFtaWMtdGhlbWUnO1xuaW1wb3J0IHtwYXJzZVN0YXRpY1RoZW1lcywgZm9ybWF0U3RhdGljVGhlbWVzfSBmcm9tICcuLi9nZW5lcmF0b3JzL3N0YXRpYy10aGVtZSc7XG5pbXBvcnQge2lzRmlyZWZveH0gZnJvbSAnLi4vdXRpbHMvcGxhdGZvcm0nO1xuXG5pbXBvcnQgQ29uZmlnTWFuYWdlciBmcm9tICcuL2NvbmZpZy1tYW5hZ2VyJztcbmltcG9ydCB7bG9nSW5mb30gZnJvbSAnLi91dGlscy9sb2cnO1xuXG4vLyBUT0RPKGJlcnNoYW5za2l5KTogQWRkIHN1cHBvcnQgZm9yIHJlYWRzL3dyaXRlcyBvZiBtdWx0aXBsZSBrZXlzIGF0IG9uY2UgZm9yIHBlcmZvcm1hbmNlLlxuLy8gVE9ETyhiZXJzaGFuc2tpeSk6IFBvcHVwIFVJIGhlZWRzIG9ubHkgaGFzQ3VzdG9tKkZpeGVzKCkgYW5kIG5vdGhpbmcgZWxzZS4gQ29uc2lkZXIgc3RvcmluZyB0aGF0IGRhdGEgc2VwYXJhdGVseS5cbmludGVyZmFjZSBEZXZUb29sc1N0b3JhZ2Uge1xuICAgIGdldChrZXk6IHN0cmluZyk6IFByb21pc2U8c3RyaW5nIHwgbnVsbD47XG4gICAgc2V0KGtleTogc3RyaW5nLCB2YWx1ZTogc3RyaW5nKTogUHJvbWlzZTx2b2lkPiB8IHZvaWQ7XG4gICAgcmVtb3ZlKGtleTogc3RyaW5nKTogUHJvbWlzZTx2b2lkPiB8IHZvaWQ7XG4gICAgaGFzKGtleTogc3RyaW5nKTogUHJvbWlzZTxib29sZWFuPiB8IGJvb2xlYW47XG59XG5cbmNsYXNzIFBlcnNpc3RlbnRTdG9yYWdlV3JhcHBlciBpbXBsZW1lbnRzIERldlRvb2xzU3RvcmFnZSB7XG4gICAgLy8gQ2FjaGUgaW5mb3JtYXRpb24gd2l0aGluIGJhY2tncm91bmQgY29udGV4dCBmb3IgZnV0dXJlIHVzZSB3aXRob3V0IHdhaXRpbmcuXG4gICAgcHJpdmF0ZSBjYWNoZToge1trZXk6IHN0cmluZ106IHN0cmluZyB8IG51bGx9ID0ge307XG5cbiAgICBhc3luYyBnZXQoa2V5OiBzdHJpbmcpIHtcbiAgICAgICAgaWYgKGtleSBpbiB0aGlzLmNhY2hlKSB7XG4gICAgICAgICAgICByZXR1cm4gdGhpcy5jYWNoZVtrZXldO1xuICAgICAgICB9XG4gICAgICAgIHJldHVybiBuZXcgUHJvbWlzZTxzdHJpbmcgfCBudWxsPigocmVzb2x2ZSkgPT4ge1xuICAgICAgICAgICAgY2hyb21lLnN0b3JhZ2UubG9jYWwuZ2V0PFJlY29yZDxzdHJpbmcsIGFueT4+KGtleSwgKHJlc3VsdCkgPT4ge1xuICAgICAgICAgICAgICAgIC8vIElmIGNhY2hlIHJlY2VpdmVkIGEgbmV3IHZhbHVlIChmcm9tIGNhbGwgdG8gc2V0KCkpXG4gICAgICAgICAgICAgICAgLy8gYmVmb3JlIHdlIHJldHJpZXZlZCB0aGUgb2xkIHZhbHVlIGZyb20gc3RvcmFnZSxcbiAgICAgICAgICAgICAgICAvLyByZXR1cm4gdGhlIG5ldyB2YWx1ZS5cbiAgICAgICAgICAgICAgICBpZiAoa2V5IGluIHRoaXMuY2FjaGUpIHtcbiAgICAgICAgICAgICAgICAgICAgbG9nSW5mbyhgS2V5ICR7a2V5fSB3YXMgd3JpdHRlbiB0byBkdXJpbmcgcmVhZCBvcGVyYXRpb24uYCk7XG4gICAgICAgICAgICAgICAgICAgIHJlc29sdmUodGhpcy5jYWNoZVtrZXldKTtcbiAgICAgICAgICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICAgICAgICAgIH1cblxuICAgICAgICAgICAgICAgIGlmIChjaHJvbWUucnVudGltZS5sYXN0RXJyb3IpIHtcbiAgICAgICAgICAgICAgICAgICAgY29uc29sZS5lcnJvcignRmFpbGVkIHRvIHF1ZXJ5IERldlRvb2xzIGRhdGEnLCBjaHJvbWUucnVudGltZS5sYXN0RXJyb3IpO1xuICAgICAgICAgICAgICAgICAgICByZXNvbHZlKG51bGwpO1xuICAgICAgICAgICAgICAgICAgICByZXR1cm47XG4gICAgICAgICAgICAgICAgfVxuXG4gICAgICAgICAgICAgICAgdGhpcy5jYWNoZVtrZXldID0gcmVzdWx0W2tleV07XG4gICAgICAgICAgICAgICAgcmVzb2x2ZShyZXN1bHRba2V5XSk7XG4gICAgICAgICAgICB9KTtcbiAgICAgICAgfSk7XG4gICAgfVxuXG4gICAgYXN5bmMgc2V0KGtleTogc3RyaW5nLCB2YWx1ZTogc3RyaW5nKSB7XG4gICAgICAgIHRoaXMuY2FjaGVba2V5XSA9IHZhbHVlO1xuICAgICAgICByZXR1cm4gbmV3IFByb21pc2U8dm9pZD4oKHJlc29sdmUpID0+IGNocm9tZS5zdG9yYWdlLmxvY2FsLnNldCh7W2tleV06IHZhbHVlfSwgKCkgPT4ge1xuICAgICAgICAgICAgaWYgKGNocm9tZS5ydW50aW1lLmxhc3RFcnJvcikge1xuICAgICAgICAgICAgICAgIGNvbnNvbGUuZXJyb3IoJ0ZhaWxlZCB0byB3cml0ZSBEZXZUb29scyBkYXRhJywgY2hyb21lLnJ1bnRpbWUubGFzdEVycm9yKTtcbiAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgcmVzb2x2ZSgpO1xuICAgICAgICAgICAgfVxuICAgICAgICB9KSk7XG4gICAgfVxuXG4gICAgYXN5bmMgcmVtb3ZlKGtleTogc3RyaW5nKSB7XG4gICAgICAgIHRoaXMuY2FjaGVba2V5XSA9IG51bGw7XG4gICAgICAgIHJldHVybiBuZXcgUHJvbWlzZTx2b2lkPigocmVzb2x2ZSkgPT4gY2hyb21lLnN0b3JhZ2UubG9jYWwucmVtb3ZlKGtleSwgKCkgPT4ge1xuICAgICAgICAgICAgaWYgKGNocm9tZS5ydW50aW1lLmxhc3RFcnJvcikge1xuICAgICAgICAgICAgICAgIGNvbnNvbGUuZXJyb3IoJ0ZhaWxlZCB0byBkZWxldGUgRGV2VG9vbHMgZGF0YScsIGNocm9tZS5ydW50aW1lLmxhc3RFcnJvcik7XG4gICAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgICAgIHJlc29sdmUoKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfSkpO1xuICAgIH1cblxuICAgIGFzeW5jIGhhcyhrZXk6IHN0cmluZykge1xuICAgICAgICByZXR1cm4gQm9vbGVhbihhd2FpdCB0aGlzLmdldChrZXkpKTtcbiAgICB9XG59XG5cbmNsYXNzIFRlbXBTdG9yYWdlIGltcGxlbWVudHMgRGV2VG9vbHNTdG9yYWdlIHtcbiAgICBwcml2YXRlIG1hcCA9IG5ldyBNYXA8c3RyaW5nLCBzdHJpbmc+KCk7XG5cbiAgICBhc3luYyBnZXQoa2V5OiBzdHJpbmcpIHtcbiAgICAgICAgcmV0dXJuIHRoaXMubWFwLmdldChrZXkpIHx8IG51bGw7XG4gICAgfVxuXG4gICAgc2V0KGtleTogc3RyaW5nLCB2YWx1ZTogc3RyaW5nKSB7XG4gICAgICAgIHRoaXMubWFwLnNldChrZXksIHZhbHVlKTtcbiAgICB9XG5cbiAgICByZW1vdmUoa2V5OiBzdHJpbmcpIHtcbiAgICAgICAgdGhpcy5tYXAuZGVsZXRlKGtleSk7XG4gICAgfVxuXG4gICAgYXN5bmMgaGFzKGtleTogc3RyaW5nKSB7XG4gICAgICAgIHJldHVybiB0aGlzLm1hcC5oYXMoa2V5KTtcbiAgICB9XG59XG5cbmV4cG9ydCBkZWZhdWx0IGNsYXNzIERldlRvb2xzIHtcbiAgICBwcml2YXRlIHN0YXRpYyBvbkNoYW5nZTogKCkgPT4gdm9pZDtcbiAgICBwcml2YXRlIHN0YXRpYyBzdG9yZTogRGV2VG9vbHNTdG9yYWdlO1xuXG4gICAgc3RhdGljIGluaXQob25DaGFuZ2U6ICgpID0+IHZvaWQpOiB2b2lkIHtcbiAgICAgICAgLy8gRmlyZWZveCBkb24ndCBzZWVtIHRvIGxpa2UgdXNpbmcgc3RvcmFnZS5sb2NhbCB0byBzdG9yZSBiaWcgZGF0YSBvbiB0aGUgYmFja2dyb3VuZC1leHRlbnNpb24uXG4gICAgICAgIC8vIERpc2FibGluZyBpdCBmb3Igbm93IGFuZCBkZWZhdWx0aW5nIGJhY2sgdG8gbG9jYWxTdG9yYWdlLlxuICAgICAgICBpZiAoIWlzRmlyZWZveCAmJiB0eXBlb2YgY2hyb21lLnN0b3JhZ2UubG9jYWwgIT09ICd1bmRlZmluZWQnICYmIGNocm9tZS5zdG9yYWdlLmxvY2FsICE9PSBudWxsKSB7XG4gICAgICAgICAgICBEZXZUb29scy5zdG9yZSA9IG5ldyBQZXJzaXN0ZW50U3RvcmFnZVdyYXBwZXIoKTtcbiAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgIERldlRvb2xzLnN0b3JlID0gbmV3IFRlbXBTdG9yYWdlKCk7XG4gICAgICAgIH1cbiAgICAgICAgRGV2VG9vbHMubG9hZENvbmZpZ092ZXJyaWRlcygpO1xuICAgICAgICBEZXZUb29scy5vbkNoYW5nZSA9IG9uQ2hhbmdlO1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIEtFWV9EWU5BTUlDID0gJ2Rldl9keW5hbWljX3RoZW1lX2ZpeGVzJztcbiAgICBwcml2YXRlIHN0YXRpYyBLRVlfRklMVEVSID0gJ2Rldl9pbnZlcnNpb25fZml4ZXMnO1xuICAgIHByaXZhdGUgc3RhdGljIEtFWV9TVEFUSUMgPSAnZGV2X3N0YXRpY190aGVtZXMnO1xuXG4gICAgcHJpdmF0ZSBzdGF0aWMgYXN5bmMgbG9hZENvbmZpZ092ZXJyaWRlcygpOiBQcm9taXNlPHZvaWQ+IHtcbiAgICAgICAgY29uc3QgW1xuICAgICAgICAgICAgZHluYW1pY1RoZW1lRml4ZXMsXG4gICAgICAgICAgICBpbnZlcnNpb25GaXhlcyxcbiAgICAgICAgICAgIHN0YXRpY1RoZW1lcyxcbiAgICAgICAgXSA9IGF3YWl0IFByb21pc2UuYWxsKFtcbiAgICAgICAgICAgIERldlRvb2xzLmdldFNhdmVkRHluYW1pY1RoZW1lRml4ZXMoKSxcbiAgICAgICAgICAgIERldlRvb2xzLmdldFNhdmVkSW52ZXJzaW9uRml4ZXMoKSxcbiAgICAgICAgICAgIERldlRvb2xzLmdldFNhdmVkU3RhdGljVGhlbWVzKCksXG4gICAgICAgIF0pO1xuICAgICAgICBDb25maWdNYW5hZ2VyLm92ZXJyaWRlcy5keW5hbWljVGhlbWVGaXhlcyA9IGR5bmFtaWNUaGVtZUZpeGVzIHx8IG51bGw7XG4gICAgICAgIENvbmZpZ01hbmFnZXIub3ZlcnJpZGVzLmludmVyc2lvbkZpeGVzID0gaW52ZXJzaW9uRml4ZXMgfHwgbnVsbDtcbiAgICAgICAgQ29uZmlnTWFuYWdlci5vdmVycmlkZXMuc3RhdGljVGhlbWVzID0gc3RhdGljVGhlbWVzIHx8IG51bGw7XG4gICAgfVxuXG4gICAgcHJpdmF0ZSBzdGF0aWMgYXN5bmMgZ2V0U2F2ZWREeW5hbWljVGhlbWVGaXhlcygpIHtcbiAgICAgICAgcmV0dXJuIERldlRvb2xzLnN0b3JlLmdldChEZXZUb29scy5LRVlfRFlOQU1JQyk7XG4gICAgfVxuXG4gICAgcHJpdmF0ZSBzdGF0aWMgc2F2ZUR5bmFtaWNUaGVtZUZpeGVzKHRleHQ6IHN0cmluZykge1xuICAgICAgICBEZXZUb29scy5zdG9yZS5zZXQoRGV2VG9vbHMuS0VZX0RZTkFNSUMsIHRleHQpO1xuICAgIH1cblxuICAgIHN0YXRpYyBhc3luYyBnZXREeW5hbWljVGhlbWVGaXhlc1RleHQoKTogUHJvbWlzZTxzdHJpbmc+IHtcbiAgICAgICAgbGV0IHJhd0ZpeGVzID0gYXdhaXQgRGV2VG9vbHMuZ2V0U2F2ZWREeW5hbWljVGhlbWVGaXhlcygpO1xuICAgICAgICBpZiAoIXJhd0ZpeGVzKSB7XG4gICAgICAgICAgICBhd2FpdCBDb25maWdNYW5hZ2VyLmxvYWQoKTtcbiAgICAgICAgICAgIHJhd0ZpeGVzID0gQ29uZmlnTWFuYWdlci5EWU5BTUlDX1RIRU1FX0ZJWEVTX1JBVyB8fCAnJztcbiAgICAgICAgfVxuICAgICAgICBjb25zdCBmaXhlcyA9IHBhcnNlRHluYW1pY1RoZW1lRml4ZXMocmF3Rml4ZXMpO1xuICAgICAgICByZXR1cm4gZm9ybWF0RHluYW1pY1RoZW1lRml4ZXMoZml4ZXMpO1xuICAgIH1cblxuICAgIHN0YXRpYyByZXNldER5bmFtaWNUaGVtZUZpeGVzKCk6IHZvaWQge1xuICAgICAgICBEZXZUb29scy5zdG9yZS5yZW1vdmUoRGV2VG9vbHMuS0VZX0RZTkFNSUMpO1xuICAgICAgICBDb25maWdNYW5hZ2VyLm92ZXJyaWRlcy5keW5hbWljVGhlbWVGaXhlcyA9IG51bGw7XG4gICAgICAgIENvbmZpZ01hbmFnZXIuaGFuZGxlRHluYW1pY1RoZW1lRml4ZXMoKTtcbiAgICAgICAgRGV2VG9vbHMub25DaGFuZ2UoKTtcbiAgICB9XG5cbiAgICAvLyBUT0RPKEFudG9uKTogcmVtb3ZlIGFueVxuICAgIHN0YXRpYyBhcHBseUR5bmFtaWNUaGVtZUZpeGVzKHRleHQ6IHN0cmluZyk6IGFueSB7XG4gICAgICAgIHRyeSB7XG4gICAgICAgICAgICBjb25zdCBmb3JtYXR0ZWQgPSBmb3JtYXREeW5hbWljVGhlbWVGaXhlcyhwYXJzZUR5bmFtaWNUaGVtZUZpeGVzKHRleHQpKTtcbiAgICAgICAgICAgIENvbmZpZ01hbmFnZXIub3ZlcnJpZGVzLmR5bmFtaWNUaGVtZUZpeGVzID0gZm9ybWF0dGVkO1xuICAgICAgICAgICAgQ29uZmlnTWFuYWdlci5oYW5kbGVEeW5hbWljVGhlbWVGaXhlcygpO1xuICAgICAgICAgICAgRGV2VG9vbHMuc2F2ZUR5bmFtaWNUaGVtZUZpeGVzKGZvcm1hdHRlZCk7XG4gICAgICAgICAgICBEZXZUb29scy5vbkNoYW5nZSgpO1xuICAgICAgICAgICAgcmV0dXJuIG51bGw7XG4gICAgICAgIH0gY2F0Y2ggKGVycikge1xuICAgICAgICAgICAgcmV0dXJuIGVycjtcbiAgICAgICAgfVxuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIGFzeW5jIGdldFNhdmVkSW52ZXJzaW9uRml4ZXMoKTogUHJvbWlzZTxzdHJpbmcgfCBudWxsPiB7XG4gICAgICAgIHJldHVybiB0aGlzLnN0b3JlLmdldChEZXZUb29scy5LRVlfRklMVEVSKTtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBzYXZlSW52ZXJzaW9uRml4ZXModGV4dDogc3RyaW5nKTogdm9pZCB7XG4gICAgICAgIHRoaXMuc3RvcmUuc2V0KERldlRvb2xzLktFWV9GSUxURVIsIHRleHQpO1xuICAgIH1cblxuICAgIHN0YXRpYyBhc3luYyBnZXRJbnZlcnNpb25GaXhlc1RleHQoKTogUHJvbWlzZTxzdHJpbmc+IHtcbiAgICAgICAgbGV0IHJhd0ZpeGVzID0gYXdhaXQgRGV2VG9vbHMuZ2V0U2F2ZWRJbnZlcnNpb25GaXhlcygpO1xuICAgICAgICBpZiAoIXJhd0ZpeGVzKSB7XG4gICAgICAgICAgICBhd2FpdCBDb25maWdNYW5hZ2VyLmxvYWQoKTtcbiAgICAgICAgICAgIHJhd0ZpeGVzID0gQ29uZmlnTWFuYWdlci5JTlZFUlNJT05fRklYRVNfUkFXIHx8ICcnO1xuICAgICAgICB9XG4gICAgICAgIGNvbnN0IGZpeGVzID0gcGFyc2VJbnZlcnNpb25GaXhlcyhyYXdGaXhlcyk7XG4gICAgICAgIHJldHVybiBmb3JtYXRJbnZlcnNpb25GaXhlcyhmaXhlcyk7XG4gICAgfVxuXG4gICAgc3RhdGljIHJlc2V0SW52ZXJzaW9uRml4ZXMoKTogdm9pZCB7XG4gICAgICAgIERldlRvb2xzLnN0b3JlLnJlbW92ZShEZXZUb29scy5LRVlfRklMVEVSKTtcbiAgICAgICAgQ29uZmlnTWFuYWdlci5vdmVycmlkZXMuaW52ZXJzaW9uRml4ZXMgPSBudWxsO1xuICAgICAgICBDb25maWdNYW5hZ2VyLmhhbmRsZUludmVyc2lvbkZpeGVzKCk7XG4gICAgICAgIERldlRvb2xzLm9uQ2hhbmdlKCk7XG4gICAgfVxuXG4gICAgLy8gVE9ETyhBbnRvbik6IHJlbW92ZSBhbnlcbiAgICBzdGF0aWMgYXBwbHlJbnZlcnNpb25GaXhlcyh0ZXh0OiBzdHJpbmcpOiBhbnkge1xuICAgICAgICB0cnkge1xuICAgICAgICAgICAgY29uc3QgZm9ybWF0dGVkID0gZm9ybWF0SW52ZXJzaW9uRml4ZXMocGFyc2VJbnZlcnNpb25GaXhlcyh0ZXh0KSk7XG4gICAgICAgICAgICBDb25maWdNYW5hZ2VyLm92ZXJyaWRlcy5pbnZlcnNpb25GaXhlcyA9IGZvcm1hdHRlZDtcbiAgICAgICAgICAgIENvbmZpZ01hbmFnZXIuaGFuZGxlSW52ZXJzaW9uRml4ZXMoKTtcbiAgICAgICAgICAgIERldlRvb2xzLnNhdmVJbnZlcnNpb25GaXhlcyhmb3JtYXR0ZWQpO1xuICAgICAgICAgICAgRGV2VG9vbHMub25DaGFuZ2UoKTtcbiAgICAgICAgICAgIHJldHVybiBudWxsO1xuICAgICAgICB9IGNhdGNoIChlcnIpIHtcbiAgICAgICAgICAgIHJldHVybiBlcnI7XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBhc3luYyBnZXRTYXZlZFN0YXRpY1RoZW1lcygpOiBQcm9taXNlPHN0cmluZyB8IG51bGw+IHtcbiAgICAgICAgcmV0dXJuIERldlRvb2xzLnN0b3JlLmdldChEZXZUb29scy5LRVlfU1RBVElDKTtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBzYXZlU3RhdGljVGhlbWVzKHRleHQ6IHN0cmluZyk6IHZvaWQge1xuICAgICAgICBEZXZUb29scy5zdG9yZS5zZXQoRGV2VG9vbHMuS0VZX1NUQVRJQywgdGV4dCk7XG4gICAgfVxuXG4gICAgc3RhdGljIGFzeW5jIGdldFN0YXRpY1RoZW1lc1RleHQoKTogUHJvbWlzZTxzdHJpbmc+IHtcbiAgICAgICAgbGV0IHJhd1RoZW1lcyA9IGF3YWl0IERldlRvb2xzLmdldFNhdmVkU3RhdGljVGhlbWVzKCk7XG4gICAgICAgIGlmICghcmF3VGhlbWVzKSB7XG4gICAgICAgICAgICBhd2FpdCBDb25maWdNYW5hZ2VyLmxvYWQoKTtcbiAgICAgICAgICAgIHJhd1RoZW1lcyA9IENvbmZpZ01hbmFnZXIuU1RBVElDX1RIRU1FU19SQVcgfHwgJyc7XG4gICAgICAgIH1cbiAgICAgICAgY29uc3QgdGhlbWVzID0gcGFyc2VTdGF0aWNUaGVtZXMocmF3VGhlbWVzKTtcbiAgICAgICAgcmV0dXJuIGZvcm1hdFN0YXRpY1RoZW1lcyh0aGVtZXMpO1xuICAgIH1cblxuICAgIHN0YXRpYyByZXNldFN0YXRpY1RoZW1lcygpOiB2b2lkIHtcbiAgICAgICAgRGV2VG9vbHMuc3RvcmUucmVtb3ZlKERldlRvb2xzLktFWV9TVEFUSUMpO1xuICAgICAgICBDb25maWdNYW5hZ2VyLm92ZXJyaWRlcy5zdGF0aWNUaGVtZXMgPSBudWxsO1xuICAgICAgICBDb25maWdNYW5hZ2VyLmhhbmRsZVN0YXRpY1RoZW1lcygpO1xuICAgICAgICBEZXZUb29scy5vbkNoYW5nZSgpO1xuICAgIH1cblxuICAgIC8vIFRPRE8oQW50b24pOiByZW1vdmUgYW55XG4gICAgc3RhdGljIGFwcGx5U3RhdGljVGhlbWVzKHRleHQ6IHN0cmluZyk6IGFueSB7XG4gICAgICAgIHRyeSB7XG4gICAgICAgICAgICBjb25zdCBmb3JtYXR0ZWQgPSBmb3JtYXRTdGF0aWNUaGVtZXMocGFyc2VTdGF0aWNUaGVtZXModGV4dCkpO1xuICAgICAgICAgICAgQ29uZmlnTWFuYWdlci5vdmVycmlkZXMuc3RhdGljVGhlbWVzID0gZm9ybWF0dGVkO1xuICAgICAgICAgICAgQ29uZmlnTWFuYWdlci5oYW5kbGVTdGF0aWNUaGVtZXMoKTtcbiAgICAgICAgICAgIERldlRvb2xzLnNhdmVTdGF0aWNUaGVtZXMoZm9ybWF0dGVkKTtcbiAgICAgICAgICAgIERldlRvb2xzLm9uQ2hhbmdlKCk7XG4gICAgICAgICAgICByZXR1cm4gbnVsbDtcbiAgICAgICAgfSBjYXRjaCAoZXJyKSB7XG4gICAgICAgICAgICByZXR1cm4gZXJyO1xuICAgICAgICB9XG4gICAgfVxufVxuIiwiaW1wb3J0IHtpc05vblBlcnNpc3RlbnR9IGZyb20gJy4uL3V0aWxzL3BsYXRmb3JtJztcblxuZGVjbGFyZSBjb25zdCBfX1RIVU5ERVJCSVJEX186IGJvb2xlYW47XG5cbmludGVyZmFjZSBJY29uU3RhdGUge1xuICAgIGJhZGdlVGV4dDogc3RyaW5nO1xuICAgIGFjdGl2ZTogYm9vbGVhbjtcbn1cblxuaW50ZXJmYWNlIEljb25PcHRpb25zIHtcbiAgICBjb2xvclNjaGVtZT86ICdkYXJrJyB8ICdsaWdodCc7XG4gICAgaXNBY3RpdmU/OiBib29sZWFuO1xuICAgIHRhYklkPzogbnVtYmVyO1xufVxuXG5leHBvcnQgZGVmYXVsdCBjbGFzcyBJY29uTWFuYWdlciB7XG4gICAgcHJpdmF0ZSBzdGF0aWMgcmVhZG9ubHkgSUNPTl9QQVRIUyA9IHtcbiAgICAgICAgYWN0aXZlRGFyazoge1xuICAgICAgICAgICAgMTk6ICcuLi9pY29ucy9kcl9hY3RpdmVfMTkucG5nJyxcbiAgICAgICAgICAgIDM4OiAnLi4vaWNvbnMvZHJfYWN0aXZlXzM4LnBuZycsXG4gICAgICAgIH0sXG4gICAgICAgIGFjdGl2ZUxpZ2h0OiB7XG4gICAgICAgICAgICAxOTogJy4uL2ljb25zL2RyX2FjdGl2ZV9saWdodF8xOS5wbmcnLFxuICAgICAgICAgICAgMzg6ICcuLi9pY29ucy9kcl9hY3RpdmVfbGlnaHRfMzgucG5nJyxcbiAgICAgICAgfSxcbiAgICAgICAgLy8gVGVtcG9yYXJ5IGRpc2FibGUgdGhlIGdyYXkgaWNvblxuICAgICAgICAvKlxuICAgICAgICBpbmFjdGl2ZURhcms6IHtcbiAgICAgICAgICAgIDE5OiAnLi4vaWNvbnMvZHJfaW5hY3RpdmVfZGFya18xOS5wbmcnLFxuICAgICAgICAgICAgMzg6ICcuLi9pY29ucy9kcl9pbmFjdGl2ZV9kYXJrXzM4LnBuZycsXG4gICAgICAgIH0sXG4gICAgICAgIGluYWN0aXZlTGlnaHQ6IHtcbiAgICAgICAgICAgIDE5OiAnLi4vaWNvbnMvZHJfaW5hY3RpdmVfbGlnaHRfMTkucG5nJyxcbiAgICAgICAgICAgIDM4OiAnLi4vaWNvbnMvZHJfaW5hY3RpdmVfbGlnaHRfMzgucG5nJyxcbiAgICAgICAgfSxcbiAgICAgICAgKi9cbiAgICB9O1xuXG4gICAgcHJpdmF0ZSBzdGF0aWMgcmVhZG9ubHkgaWNvblN0YXRlOiBJY29uU3RhdGUgPSB7XG4gICAgICAgIGJhZGdlVGV4dDogJycsXG4gICAgICAgIGFjdGl2ZTogdHJ1ZSxcbiAgICB9O1xuXG4gICAgcHJpdmF0ZSBzdGF0aWMgb25TdGFydHVwKCkge1xuICAgICAgICAvKipcbiAgICAgICAgICogVGhpcyBlbXB0eSBsaXN0ZW5lciBpbnZva2VzIGV4dGVuc2lvbiBiYWNrZ3JvdW5kIGlmIGV4dGVuc2lvbiBoYXMgbm9uLWRlZmF1bHRcbiAgICAgICAgICogaWNvbiBvciBiYWRnZS4gSXQgaXMgZW1wdHkgYmVjYXVzZSBhbGwgaWNvbiBjdXN0b21pemF0aW9ucyB3aWxsIGJlIGluaXRpYXRlZCBieVxuICAgICAgICAgKiBFeHRlbnNpb24gY2xhc3MuXG4gICAgICAgICAqIFRPRE86IGV2ZW50dWFsbHksIGF2b2lkIHJ1bm5pbmcgdGhlIHdob2xlIEV4dGVuc2lvbiBjbGFzcyBvbiBzdGFydHVwLlxuICAgICAgICAgKi9cbiAgICB9XG5cbiAgICAvKipcbiAgICAgKiBUaGlzIG1ldGhvZCByZWdpc3RlcnMgb25TdGFydHVwIGxpc3RlbmVyIG9ubHkgaWYgd2UgYXJlIGluIG5vbi1wZXJzaXN0ZW50IHdvcmxkIGFuZFxuICAgICAqIGljb24gaXMgaW4gbm9uLWRlZmF1bHQgY29uZmlndXJhdGlvbi5cbiAgICAgKi9cbiAgICBwcml2YXRlIHN0YXRpYyBoYW5kbGVVcGRhdGUoKSB7XG4gICAgICAgIGlmICghaXNOb25QZXJzaXN0ZW50KSB7XG4gICAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cbiAgICAgICAgaWYgKEljb25NYW5hZ2VyLmljb25TdGF0ZS5iYWRnZVRleHQgIT09ICcnIHx8ICFJY29uTWFuYWdlci5pY29uU3RhdGUuYWN0aXZlKSB7XG4gICAgICAgICAgICBjaHJvbWUucnVudGltZS5vblN0YXJ0dXAuYWRkTGlzdGVuZXIoSWNvbk1hbmFnZXIub25TdGFydHVwKTtcbiAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgIGNocm9tZS5ydW50aW1lLm9uU3RhcnR1cC5yZW1vdmVMaXN0ZW5lcihJY29uTWFuYWdlci5vblN0YXJ0dXApO1xuICAgICAgICB9XG4gICAgfVxuXG4gICAgc3RhdGljIHNldEljb24oe2lzQWN0aXZlID0gdGhpcy5pY29uU3RhdGUuYWN0aXZlLCBjb2xvclNjaGVtZSA9ICdkYXJrJywgdGFiSWR9OiBJY29uT3B0aW9ucyk6IHZvaWQge1xuICAgICAgICBpZiAoX19USFVOREVSQklSRF9fIHx8ICFjaHJvbWUuYnJvd3NlckFjdGlvbi5zZXRJY29uKSB7XG4gICAgICAgICAgICAvLyBGaXggZm9yIEZpcmVmb3ggQW5kcm9pZCBhbmQgVGh1bmRlcmJpcmQuXG4gICAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cbiAgICAgICAgLy8gVGVtcG9yYXJ5IGRpc2FibGUgcGVyLXNpdGUgaWNvbnNcbiAgICAgICAgLy8gZXNsaW50LWRpc2FibGUtbmV4dC1saW5lIG5vLWVtcHR5XG4gICAgICAgIGlmIChjb2xvclNjaGVtZSA9PT0gJ2RhcmsnKSB7XG4gICAgICAgIH1cbiAgICAgICAgaWYgKHRhYklkKSB7XG4gICAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cblxuICAgICAgICB0aGlzLmljb25TdGF0ZS5hY3RpdmUgPSBpc0FjdGl2ZTtcblxuICAgICAgICBsZXQgcGF0aCA9IHRoaXMuSUNPTl9QQVRIUy5hY3RpdmVEYXJrO1xuICAgICAgICBpZiAoaXNBY3RpdmUpIHtcbiAgICAgICAgICAgIC8vIFRlbXBvcmFyeSBkaXNhYmxlIHRoZSBncmF5IGljb25cbiAgICAgICAgICAgIC8vIHBhdGggPSBjb2xvclNjaGVtZSA9PT0gJ2RhcmsnID8gSWNvbk1hbmFnZXIuSUNPTl9QQVRIUy5hY3RpdmVEYXJrIDogSWNvbk1hbmFnZXIuSUNPTl9QQVRIUy5hY3RpdmVMaWdodDtcbiAgICAgICAgICAgIHBhdGggPSBJY29uTWFuYWdlci5JQ09OX1BBVEhTLmFjdGl2ZURhcms7XG4gICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAvLyBUZW1wb3JhcnkgZGlzYWJsZSB0aGUgZ3JheSBpY29uXG4gICAgICAgICAgICAvLyBwYXRoID0gY29sb3JTY2hlbWUgPT09ICdkYXJrJyA/IEljb25NYW5hZ2VyLklDT05fUEFUSFMuaW5hY3RpdmVEYXJrIDogSWNvbk1hbmFnZXIuSUNPTl9QQVRIUy5pbmFjdGl2ZUxpZ2h0O1xuICAgICAgICAgICAgcGF0aCA9IEljb25NYW5hZ2VyLklDT05fUEFUSFMuYWN0aXZlTGlnaHQ7XG4gICAgICAgIH1cblxuICAgICAgICAvLyBUZW1wb3JhcnkgZGlzYWJsZSBwZXItc2l0ZSBpY29uc1xuICAgICAgICAvKlxuICAgICAgICBpZiAodGFiSWQpIHtcbiAgICAgICAgICAgIGNocm9tZS5icm93c2VyQWN0aW9uLnNldEljb24oe3RhYklkLCBwYXRofSk7XG4gICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICBjaHJvbWUuYnJvd3NlckFjdGlvbi5zZXRJY29uKHtwYXRofSk7XG4gICAgICAgICAgICBJY29uTWFuYWdlci5oYW5kbGVVcGRhdGUoKTtcbiAgICAgICAgfVxuICAgICAgICAqL1xuICAgICAgICBjaHJvbWUuYnJvd3NlckFjdGlvbi5zZXRJY29uKHtwYXRofSk7XG4gICAgICAgIEljb25NYW5hZ2VyLmhhbmRsZVVwZGF0ZSgpO1xuICAgIH1cblxuICAgIHN0YXRpYyBzaG93QmFkZ2UodGV4dDogc3RyaW5nKTogdm9pZCB7XG4gICAgICAgIEljb25NYW5hZ2VyLmljb25TdGF0ZS5iYWRnZVRleHQgPSB0ZXh0O1xuICAgICAgICBjaHJvbWUuYnJvd3NlckFjdGlvbi5zZXRCYWRnZUJhY2tncm91bmRDb2xvcih7Y29sb3I6ICcjZTk2YzRjJ30pO1xuICAgICAgICBjaHJvbWUuYnJvd3NlckFjdGlvbi5zZXRCYWRnZVRleHQoe3RleHR9KTtcbiAgICAgICAgSWNvbk1hbmFnZXIuaGFuZGxlVXBkYXRlKCk7XG4gICAgfVxuXG4gICAgc3RhdGljIGhpZGVCYWRnZSgpOiB2b2lkIHtcbiAgICAgICAgSWNvbk1hbmFnZXIuaWNvblN0YXRlLmJhZGdlVGV4dCA9ICcnO1xuICAgICAgICBjaHJvbWUuYnJvd3NlckFjdGlvbi5zZXRCYWRnZVRleHQoe3RleHQ6ICcnfSk7XG4gICAgICAgIEljb25NYW5hZ2VyLmhhbmRsZVVwZGF0ZSgpO1xuICAgIH1cbn1cbiIsImltcG9ydCB0eXBlIHtFeHRlbnNpb25EYXRhLCBUaGVtZSwgVGFiSW5mbywgTWVzc2FnZVVJdG9CRywgVXNlclNldHRpbmdzLCBEZXZUb29sc0RhdGEsIE1lc3NhZ2VDU3RvQkcsIE1lc3NhZ2VCR3RvVUl9IGZyb20gJy4uL2RlZmluaXRpb25zJztcbmltcG9ydCB7TWVzc2FnZVR5cGVCR3RvVUksIE1lc3NhZ2VUeXBlVUl0b0JHfSBmcm9tICcuLi91dGlscy9tZXNzYWdlJztcbmltcG9ydCB7SE9NRVBBR0VfVVJMfSBmcm9tICcuLi91dGlscy9saW5rcyc7XG5pbXBvcnQge2lzRmlyZWZveH0gZnJvbSAnLi4vdXRpbHMvcGxhdGZvcm0nO1xuXG5pbXBvcnQge21ha2VGaXJlZm94SGFwcHl9IGZyb20gJy4vbWFrZS1maXJlZm94LWhhcHB5JztcbmltcG9ydCB7QVNTRVJUfSBmcm9tICcuL3V0aWxzL2xvZyc7XG5cbmRlY2xhcmUgY29uc3QgX19QTFVTX186IGJvb2xlYW47XG5cbmV4cG9ydCBpbnRlcmZhY2UgRXh0ZW5zaW9uQWRhcHRlciB7XG4gICAgY29sbGVjdDogKCkgPT4gUHJvbWlzZTxFeHRlbnNpb25EYXRhPjtcbiAgICBjb2xsZWN0RGV2VG9vbHNEYXRhOiAoKSA9PiBQcm9taXNlPERldlRvb2xzRGF0YT47XG4gICAgY2hhbmdlU2V0dGluZ3M6IChzZXR0aW5nczogUGFydGlhbDxVc2VyU2V0dGluZ3M+KSA9PiB2b2lkO1xuICAgIHNldFRoZW1lOiAodGhlbWU6IFBhcnRpYWw8VGhlbWU+KSA9PiB2b2lkO1xuICAgIG1hcmtOZXdzQXNSZWFkOiAoaWRzOiBzdHJpbmdbXSkgPT4gUHJvbWlzZTx2b2lkPjtcbiAgICBtYXJrTmV3c0FzRGlzcGxheWVkOiAoaWRzOiBzdHJpbmdbXSkgPT4gUHJvbWlzZTx2b2lkPjtcbiAgICB0b2dnbGVBY3RpdmVUYWI6ICgpID0+IHZvaWQ7XG4gICAgbG9hZENvbmZpZzogKG9wdGlvbnM6IHtsb2NhbDogYm9vbGVhbn0pID0+IFByb21pc2U8dm9pZD47XG4gICAgYXBwbHlEZXZEeW5hbWljVGhlbWVGaXhlczogKGpzb246IHN0cmluZykgPT4gRXJyb3I7XG4gICAgcmVzZXREZXZEeW5hbWljVGhlbWVGaXhlczogKCkgPT4gdm9pZDtcbiAgICBhcHBseURldkludmVyc2lvbkZpeGVzOiAoanNvbjogc3RyaW5nKSA9PiBFcnJvcjtcbiAgICByZXNldERldkludmVyc2lvbkZpeGVzOiAoKSA9PiB2b2lkO1xuICAgIGFwcGx5RGV2U3RhdGljVGhlbWVzOiAodGV4dDogc3RyaW5nKSA9PiBFcnJvcjtcbiAgICByZXNldERldlN0YXRpY1RoZW1lczogKCkgPT4gdm9pZDtcbiAgICBzdGFydEFjdGl2YXRpb246IChlbWFpbDogc3RyaW5nLCBrZXk6IHN0cmluZykgPT4gUHJvbWlzZTx2b2lkPjtcbiAgICByZXNldEFjdGl2YXRpb246ICgpID0+IFByb21pc2U8dm9pZD47XG4gICAgaGlkZUhpZ2hsaWdodHM6IChpZHM6IHN0cmluZ1tdKSA9PiBQcm9taXNlPHZvaWQ+O1xufVxuXG5leHBvcnQgZGVmYXVsdCBjbGFzcyBNZXNzZW5nZXIge1xuICAgIHByaXZhdGUgc3RhdGljIGFkYXB0ZXI6IEV4dGVuc2lvbkFkYXB0ZXI7XG4gICAgcHJpdmF0ZSBzdGF0aWMgY2hhbmdlTGlzdGVuZXJDb3VudDogbnVtYmVyO1xuXG4gICAgc3RhdGljIGluaXQoYWRhcHRlcjogRXh0ZW5zaW9uQWRhcHRlcik6IHZvaWQge1xuICAgICAgICBNZXNzZW5nZXIuYWRhcHRlciA9IGFkYXB0ZXI7XG4gICAgICAgIE1lc3Nlbmdlci5jaGFuZ2VMaXN0ZW5lckNvdW50ID0gMDtcblxuICAgICAgICBjaHJvbWUucnVudGltZS5vbk1lc3NhZ2UuYWRkTGlzdGVuZXIoTWVzc2VuZ2VyLm1lc3NhZ2VMaXN0ZW5lcik7XG5cbiAgICAgICAgLy8gVGhpcyBpcyBhIHdvcmstYXJvdW5kIGZvciBGaXJlZm94IGJ1ZyB3aGljaCBkb2VzIG5vdCBwZXJtaXQgcmVzcG9uZGluZyB0byBvbk1lc3NhZ2UgaGFuZGxlciBhYm92ZS5cbiAgICAgICAgaWYgKGlzRmlyZWZveCkge1xuICAgICAgICAgICAgY2hyb21lLnJ1bnRpbWUub25Db25uZWN0LmFkZExpc3RlbmVyKE1lc3Nlbmdlci5maXJlZm94UG9ydExpc3RlbmVyKTtcbiAgICAgICAgfVxuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIG1lc3NhZ2VMaXN0ZW5lcihtZXNzYWdlOiBNZXNzYWdlVUl0b0JHIHwgTWVzc2FnZUNTdG9CRywgc2VuZGVyOiBjaHJvbWUucnVudGltZS5NZXNzYWdlU2VuZGVyLCBzZW5kUmVzcG9uc2U6IChyZXNwb25zZToge2RhdGE/OiBFeHRlbnNpb25EYXRhIHwgRGV2VG9vbHNEYXRhIHwgVGFiSW5mbzsgZXJyb3I/OiBzdHJpbmd9IHwgJ3Vuc3VwcG9ydGVkU2VuZGVyJykgPT4gdm9pZCkge1xuICAgICAgICBpZiAoaXNGaXJlZm94ICYmIG1ha2VGaXJlZm94SGFwcHkobWVzc2FnZSwgc2VuZGVyLCBzZW5kUmVzcG9uc2UpKSB7XG4gICAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cbiAgICAgICAgY29uc3QgYWxsb3dlZFNlbmRlclVSTCA9IFtcbiAgICAgICAgICAgIGNocm9tZS5ydW50aW1lLmdldFVSTCgnL3VpL3BvcHVwL2luZGV4Lmh0bWwnKSxcbiAgICAgICAgICAgIGNocm9tZS5ydW50aW1lLmdldFVSTCgnL3VpL2RldnRvb2xzL2luZGV4Lmh0bWwnKSxcbiAgICAgICAgICAgIGNocm9tZS5ydW50aW1lLmdldFVSTCgnL3VpL29wdGlvbnMvaW5kZXguaHRtbCcpLFxuICAgICAgICAgICAgY2hyb21lLnJ1bnRpbWUuZ2V0VVJMKCcvdWkvc3R5bGVzaGVldC1lZGl0b3IvaW5kZXguaHRtbCcpLFxuICAgICAgICBdO1xuICAgICAgICBpZiAoXG4gICAgICAgICAgICBhbGxvd2VkU2VuZGVyVVJMLmluY2x1ZGVzKHNlbmRlci51cmwhKSB8fCAoXG4gICAgICAgICAgICAgICAgX19QTFVTX18gJiZcbiAgICAgICAgICAgICAgICBtZXNzYWdlLnR5cGUgPT09IE1lc3NhZ2VUeXBlVUl0b0JHLkNIQU5HRV9TRVRUSU5HUyAmJlxuICAgICAgICAgICAgICAgIHNlbmRlci51cmw/LnN0YXJ0c1dpdGgoYCR7SE9NRVBBR0VfVVJMfS9wbHVzL2FjdGl2YXRlL2ApXG4gICAgICAgICAgICApXG4gICAgICAgICkge1xuICAgICAgICAgICAgTWVzc2VuZ2VyLm9uVUlNZXNzYWdlKG1lc3NhZ2UgYXMgTWVzc2FnZVVJdG9CRywgc2VuZFJlc3BvbnNlKTtcbiAgICAgICAgICAgIHJldHVybiAoW1xuICAgICAgICAgICAgICAgIE1lc3NhZ2VUeXBlVUl0b0JHLkdFVF9EQVRBLFxuICAgICAgICAgICAgICAgIE1lc3NhZ2VUeXBlVUl0b0JHLkdFVF9ERVZUT09MU19EQVRBLFxuICAgICAgICAgICAgXS5pbmNsdWRlcyhtZXNzYWdlLnR5cGUgYXMgTWVzc2FnZVR5cGVVSXRvQkcpKTtcbiAgICAgICAgfVxuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIGZpcmVmb3hQb3J0TGlzdGVuZXIocG9ydDogY2hyb21lLnJ1bnRpbWUuUG9ydCkge1xuICAgICAgICBBU1NFUlQoJ01lc3Nlbmdlci5maXJlZm94UG9ydExpc3RlbmVyKCkgaXMgdXNlZCBvbmx5IG9uIEZpcmVmb3gnLCBpc0ZpcmVmb3gpO1xuXG4gICAgICAgIGlmICghaXNGaXJlZm94KSB7XG4gICAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cblxuICAgICAgICBsZXQgcHJvbWlzZTogUHJvbWlzZTxFeHRlbnNpb25EYXRhIHwgRGV2VG9vbHNEYXRhIHwgVGFiSW5mbyB8IG51bGw+O1xuICAgICAgICBzd2l0Y2ggKHBvcnQubmFtZSkge1xuICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5HRVRfREFUQTpcbiAgICAgICAgICAgICAgICBwcm9taXNlID0gTWVzc2VuZ2VyLmFkYXB0ZXIuY29sbGVjdCgpO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5HRVRfREVWVE9PTFNfREFUQTpcbiAgICAgICAgICAgICAgICBwcm9taXNlID0gTWVzc2VuZ2VyLmFkYXB0ZXIuY29sbGVjdERldlRvb2xzRGF0YSgpO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgLy8gVGhlc2UgdHlwZXMgcmVxdWlyZSBkYXRhLCBzbyB3ZSBuZWVkIHRvIGFkZCBhIGxpc3RlbmVyIHRvIHRoZSBwb3J0LlxuICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5BUFBMWV9ERVZfRFlOQU1JQ19USEVNRV9GSVhFUzpcbiAgICAgICAgICAgIGNhc2UgTWVzc2FnZVR5cGVVSXRvQkcuQVBQTFlfREVWX0lOVkVSU0lPTl9GSVhFUzpcbiAgICAgICAgICAgIGNhc2UgTWVzc2FnZVR5cGVVSXRvQkcuQVBQTFlfREVWX1NUQVRJQ19USEVNRVM6XG4gICAgICAgICAgICAgICAgcHJvbWlzZSA9IG5ldyBQcm9taXNlKChyZXNvbHZlLCByZWplY3QpID0+IHtcbiAgICAgICAgICAgICAgICAgICAgcG9ydC5vbk1lc3NhZ2UuYWRkTGlzdGVuZXIoKG1lc3NhZ2U6IE1lc3NhZ2VVSXRvQkcgfCBNZXNzYWdlQ1N0b0JHKSA9PiB7XG4gICAgICAgICAgICAgICAgICAgICAgICBjb25zdCB7ZGF0YX0gPSBtZXNzYWdlO1xuICAgICAgICAgICAgICAgICAgICAgICAgbGV0IGVycm9yOiBFcnJvcjtcbiAgICAgICAgICAgICAgICAgICAgICAgIHN3aXRjaCAocG9ydC5uYW1lKSB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5BUFBMWV9ERVZfRFlOQU1JQ19USEVNRV9GSVhFUzpcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgZXJyb3IgPSBNZXNzZW5nZXIuYWRhcHRlci5hcHBseURldkR5bmFtaWNUaGVtZUZpeGVzKGRhdGEpO1xuICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBjYXNlIE1lc3NhZ2VUeXBlVUl0b0JHLkFQUExZX0RFVl9JTlZFUlNJT05fRklYRVM6XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGVycm9yID0gTWVzc2VuZ2VyLmFkYXB0ZXIuYXBwbHlEZXZJbnZlcnNpb25GaXhlcyhkYXRhKTtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5BUFBMWV9ERVZfU1RBVElDX1RIRU1FUzpcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgZXJyb3IgPSBNZXNzZW5nZXIuYWRhcHRlci5hcHBseURldlN0YXRpY1RoZW1lcyhkYXRhKTtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgZGVmYXVsdDpcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdGhyb3cgbmV3IEVycm9yKGBVbmtub3duIHBvcnQgbmFtZTogJHtwb3J0Lm5hbWV9YCk7XG4gICAgICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgICAgICBpZiAoZXJyb3IpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICByZWplY3QoZXJyb3IpO1xuICAgICAgICAgICAgICAgICAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICByZXNvbHZlKG51bGwpO1xuICAgICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICB9KTtcbiAgICAgICAgICAgICAgICB9KTtcbiAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgIGRlZmF1bHQ6XG4gICAgICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICB9XG4gICAgICAgIHByb21pc2UudGhlbigoZGF0YSkgPT4gcG9ydC5wb3N0TWVzc2FnZSh7ZGF0YX0pKVxuICAgICAgICAgICAgLmNhdGNoKChlcnJvcikgPT4gcG9ydC5wb3N0TWVzc2FnZSh7ZXJyb3J9KSk7XG4gICAgfVxuXG4gICAgcHJpdmF0ZSBzdGF0aWMgb25VSU1lc3NhZ2Uoe3R5cGUsIGRhdGF9OiBNZXNzYWdlVUl0b0JHLCBzZW5kUmVzcG9uc2U6IChyZXNwb25zZToge2RhdGE/OiBFeHRlbnNpb25EYXRhIHwgRGV2VG9vbHNEYXRhIHwgVGFiSW5mbzsgZXJyb3I/OiBzdHJpbmd9KSA9PiB2b2lkKSB7XG4gICAgICAgIHN3aXRjaCAodHlwZSkge1xuICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5HRVRfREFUQTpcbiAgICAgICAgICAgICAgICBNZXNzZW5nZXIuYWRhcHRlci5jb2xsZWN0KCkudGhlbigoZGF0YSkgPT4gc2VuZFJlc3BvbnNlKHtkYXRhfSkpO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5HRVRfREVWVE9PTFNfREFUQTpcbiAgICAgICAgICAgICAgICBNZXNzZW5nZXIuYWRhcHRlci5jb2xsZWN0RGV2VG9vbHNEYXRhKCkudGhlbigoZGF0YSkgPT4gc2VuZFJlc3BvbnNlKHtkYXRhfSkpO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5TVUJTQ1JJQkVfVE9fQ0hBTkdFUzpcbiAgICAgICAgICAgICAgICBNZXNzZW5nZXIuY2hhbmdlTGlzdGVuZXJDb3VudCsrO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5VTlNVQlNDUklCRV9GUk9NX0NIQU5HRVM6XG4gICAgICAgICAgICAgICAgTWVzc2VuZ2VyLmNoYW5nZUxpc3RlbmVyQ291bnQtLTtcbiAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgIGNhc2UgTWVzc2FnZVR5cGVVSXRvQkcuQ0hBTkdFX1NFVFRJTkdTOlxuICAgICAgICAgICAgICAgIE1lc3Nlbmdlci5hZGFwdGVyLmNoYW5nZVNldHRpbmdzKGRhdGEpO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5TRVRfVEhFTUU6XG4gICAgICAgICAgICAgICAgTWVzc2VuZ2VyLmFkYXB0ZXIuc2V0VGhlbWUoZGF0YSk7XG4gICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICBjYXNlIE1lc3NhZ2VUeXBlVUl0b0JHLlRPR0dMRV9BQ1RJVkVfVEFCOlxuICAgICAgICAgICAgICAgIE1lc3Nlbmdlci5hZGFwdGVyLnRvZ2dsZUFjdGl2ZVRhYigpO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5NQVJLX05FV1NfQVNfUkVBRDpcbiAgICAgICAgICAgICAgICBNZXNzZW5nZXIuYWRhcHRlci5tYXJrTmV3c0FzUmVhZChkYXRhKTtcbiAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgIGNhc2UgTWVzc2FnZVR5cGVVSXRvQkcuTUFSS19ORVdTX0FTX0RJU1BMQVlFRDpcbiAgICAgICAgICAgICAgICBNZXNzZW5nZXIuYWRhcHRlci5tYXJrTmV3c0FzRGlzcGxheWVkKGRhdGEpO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5MT0FEX0NPTkZJRzpcbiAgICAgICAgICAgICAgICBNZXNzZW5nZXIuYWRhcHRlci5sb2FkQ29uZmlnKGRhdGEpO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5BUFBMWV9ERVZfRFlOQU1JQ19USEVNRV9GSVhFUzoge1xuICAgICAgICAgICAgICAgIGNvbnN0IGVycm9yID0gTWVzc2VuZ2VyLmFkYXB0ZXIuYXBwbHlEZXZEeW5hbWljVGhlbWVGaXhlcyhkYXRhKTtcbiAgICAgICAgICAgICAgICBzZW5kUmVzcG9uc2Uoe2Vycm9yOiAoZXJyb3IgPyBlcnJvci5tZXNzYWdlIDogdW5kZWZpbmVkKX0pO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5SRVNFVF9ERVZfRFlOQU1JQ19USEVNRV9GSVhFUzpcbiAgICAgICAgICAgICAgICBNZXNzZW5nZXIuYWRhcHRlci5yZXNldERldkR5bmFtaWNUaGVtZUZpeGVzKCk7XG4gICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICBjYXNlIE1lc3NhZ2VUeXBlVUl0b0JHLkFQUExZX0RFVl9JTlZFUlNJT05fRklYRVM6IHtcbiAgICAgICAgICAgICAgICBjb25zdCBlcnJvciA9IE1lc3Nlbmdlci5hZGFwdGVyLmFwcGx5RGV2SW52ZXJzaW9uRml4ZXMoZGF0YSk7XG4gICAgICAgICAgICAgICAgc2VuZFJlc3BvbnNlKHtlcnJvcjogKGVycm9yID8gZXJyb3IubWVzc2FnZSA6IHVuZGVmaW5lZCl9KTtcbiAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGNhc2UgTWVzc2FnZVR5cGVVSXRvQkcuUkVTRVRfREVWX0lOVkVSU0lPTl9GSVhFUzpcbiAgICAgICAgICAgICAgICBNZXNzZW5nZXIuYWRhcHRlci5yZXNldERldkludmVyc2lvbkZpeGVzKCk7XG4gICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICBjYXNlIE1lc3NhZ2VUeXBlVUl0b0JHLkFQUExZX0RFVl9TVEFUSUNfVEhFTUVTOiB7XG4gICAgICAgICAgICAgICAgY29uc3QgZXJyb3IgPSBNZXNzZW5nZXIuYWRhcHRlci5hcHBseURldlN0YXRpY1RoZW1lcyhkYXRhKTtcbiAgICAgICAgICAgICAgICBzZW5kUmVzcG9uc2Uoe2Vycm9yOiBlcnJvciA/IGVycm9yLm1lc3NhZ2UgOiB1bmRlZmluZWR9KTtcbiAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGNhc2UgTWVzc2FnZVR5cGVVSXRvQkcuUkVTRVRfREVWX1NUQVRJQ19USEVNRVM6XG4gICAgICAgICAgICAgICAgTWVzc2VuZ2VyLmFkYXB0ZXIucmVzZXREZXZTdGF0aWNUaGVtZXMoKTtcbiAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgIGNhc2UgTWVzc2FnZVR5cGVVSXRvQkcuU1RBUlRfQUNUSVZBVElPTjpcbiAgICAgICAgICAgICAgICBNZXNzZW5nZXIuYWRhcHRlci5zdGFydEFjdGl2YXRpb24oZGF0YS5lbWFpbCwgZGF0YS5rZXkpO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5SRVNFVF9BQ1RJVkFUSU9OOlxuICAgICAgICAgICAgICAgIE1lc3Nlbmdlci5hZGFwdGVyLnJlc2V0QWN0aXZhdGlvbigpO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5ISURFX0hJR0hMSUdIVFM6XG4gICAgICAgICAgICAgICAgTWVzc2VuZ2VyLmFkYXB0ZXIuaGlkZUhpZ2hsaWdodHMoZGF0YSk7XG4gICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICBkZWZhdWx0OlxuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICB9XG4gICAgfVxuXG4gICAgc3RhdGljIHJlcG9ydENoYW5nZXMoZGF0YTogRXh0ZW5zaW9uRGF0YSk6IHZvaWQge1xuICAgICAgICBpZiAoTWVzc2VuZ2VyLmNoYW5nZUxpc3RlbmVyQ291bnQgPiAwKSB7XG4gICAgICAgICAgICBjaHJvbWUucnVudGltZS5zZW5kTWVzc2FnZTxNZXNzYWdlQkd0b1VJPih7XG4gICAgICAgICAgICAgICAgdHlwZTogTWVzc2FnZVR5cGVCR3RvVUkuQ0hBTkdFUyxcbiAgICAgICAgICAgICAgICBkYXRhLFxuICAgICAgICAgICAgfSk7XG4gICAgICAgIH1cbiAgICB9XG59XG4iLCJpbXBvcnQgdHlwZSB7TmV3c30gZnJvbSAnLi4vZGVmaW5pdGlvbnMnO1xuaW1wb3J0IHtnZXRCbG9nUG9zdFVSTCwgTkVXU19VUkx9IGZyb20gJy4uL3V0aWxzL2xpbmtzJztcbmltcG9ydCB7U3RhdGVNYW5hZ2VyfSBmcm9tICcuLi91dGlscy9zdGF0ZS1tYW5hZ2VyJztcbmltcG9ydCB7Z2V0RHVyYXRpb25Jbk1pbnV0ZXN9IGZyb20gJy4uL3V0aWxzL3RpbWUnO1xuXG5pbXBvcnQgSWNvbk1hbmFnZXIgZnJvbSAnLi9pY29uLW1hbmFnZXInO1xuaW1wb3J0IHtyZWFkU3luY1N0b3JhZ2UsIHJlYWRMb2NhbFN0b3JhZ2UsIHdyaXRlU3luY1N0b3JhZ2UsIHdyaXRlTG9jYWxTdG9yYWdlfSBmcm9tICcuL3V0aWxzL2V4dGVuc2lvbi1hcGknO1xuaW1wb3J0IHtsb2dXYXJufSBmcm9tICcuL3V0aWxzL2xvZyc7XG5cbmRlY2xhcmUgY29uc3QgX19URVNUX186IGJvb2xlYW47XG5cbmludGVyZmFjZSBOZXdzbWFrZXJTdGF0ZSBleHRlbmRzIFJlY29yZDxzdHJpbmcsIHVua25vd24+IHtcbiAgICBsYXRlc3Q6IE5ld3NbXTtcbiAgICBsYXRlc3RUaW1lc3RhbXA6IG51bWJlciB8IG51bGw7XG59XG5cbmxldCBuZXdzRm9yVGVzdGluZzogTmV3c1tdIHwgbnVsbCA9IFt7XG4gICAgaWQ6ICdzb21lJyxcbiAgICBkYXRlOiAnMTAnLFxuICAgIHVybDogJy8nLFxuICAgIGhlYWRsaW5lOiAnTmV3cycsXG59XTtcblxuZXhwb3J0IGRlZmF1bHQgY2xhc3MgTmV3c21ha2VyIHtcbiAgICBwcml2YXRlIHN0YXRpYyByZWFkb25seSBVUERBVEVfSU5URVJWQUwgPSBnZXREdXJhdGlvbkluTWludXRlcyh7aG91cnM6IDR9KTtcbiAgICBwcml2YXRlIHN0YXRpYyByZWFkb25seSBBTEFSTV9OQU1FID0gJ25ld3NtYWtlcic7XG4gICAgcHJpdmF0ZSBzdGF0aWMgcmVhZG9ubHkgTE9DQUxfU1RPUkFHRV9LRVkgPSAnTmV3c21ha2VyLXN0YXRlJztcblxuICAgIHByaXZhdGUgc3RhdGljIGluaXRpYWxpemVkOiBib29sZWFuO1xuICAgIHByaXZhdGUgc3RhdGljIHN0YXRlTWFuYWdlcjogU3RhdGVNYW5hZ2VyPE5ld3NtYWtlclN0YXRlPjtcbiAgICBwcml2YXRlIHN0YXRpYyBsYXRlc3Q6IE5ld3NbXTtcbiAgICBwcml2YXRlIHN0YXRpYyBsYXRlc3RUaW1lc3RhbXA6IG51bWJlciB8IG51bGw7XG5cbiAgICBwcml2YXRlIHN0YXRpYyBpbml0KCkge1xuICAgICAgICBpZiAoTmV3c21ha2VyLmluaXRpYWxpemVkKSB7XG4gICAgICAgICAgICAvLyBUaGlzIHBhdGggaXMgbmV2ZXIgdGFrZW4gc2luY2UgRXh0ZW5zaW9uLmNvbnN0cnVjdG9yKCkgZXZlciBjcmVhdGVzIG9uZSBpbnN0YW5jZS5cbiAgICAgICAgICAgIGxvZ1dhcm4oJ0F0dGVtcHRpbmcgdG8gcmUtaW5pdGlhbGl6ZSBOZXdzbWFrZXIuIERvaW5nIG5vdGhpbmcuJyk7XG4gICAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cbiAgICAgICAgTmV3c21ha2VyLmluaXRpYWxpemVkID0gdHJ1ZTtcblxuICAgICAgICBOZXdzbWFrZXIuc3RhdGVNYW5hZ2VyID0gbmV3IFN0YXRlTWFuYWdlcjxOZXdzbWFrZXJTdGF0ZT4oTmV3c21ha2VyLkxPQ0FMX1NUT1JBR0VfS0VZLCB0aGlzLCB7bGF0ZXN0OiBbXSwgbGF0ZXN0VGltZXN0YW1wOiBudWxsfSwgbG9nV2Fybik7XG4gICAgICAgIE5ld3NtYWtlci5sYXRlc3QgPSBbXTtcbiAgICAgICAgTmV3c21ha2VyLmxhdGVzdFRpbWVzdGFtcCA9IG51bGw7XG4gICAgfVxuXG4gICAgcHJpdmF0ZSBzdGF0aWMgb25VcGRhdGUoKSB7XG4gICAgICAgIE5ld3NtYWtlci5pbml0KCk7XG4gICAgICAgIGNvbnN0IGxhdGVzdE5ld3MgPSBOZXdzbWFrZXIubGF0ZXN0Lmxlbmd0aCA+IDAgJiYgTmV3c21ha2VyLmxhdGVzdFswXTtcbiAgICAgICAgaWYgKGxhdGVzdE5ld3MgJiYgbGF0ZXN0TmV3cy5iYWRnZSAmJiAhbGF0ZXN0TmV3cy5yZWFkICYmICFsYXRlc3ROZXdzLmRpc3BsYXllZCkge1xuICAgICAgICAgICAgSWNvbk1hbmFnZXIuc2hvd0JhZGdlKGxhdGVzdE5ld3MuYmFkZ2UpO1xuICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICB9XG5cbiAgICAgICAgSWNvbk1hbmFnZXIuaGlkZUJhZGdlKCk7XG4gICAgfVxuXG4gICAgc3RhdGljIGFzeW5jIGdldExhdGVzdCgpOiBQcm9taXNlPE5ld3NbXT4ge1xuICAgICAgICBOZXdzbWFrZXIuaW5pdCgpO1xuICAgICAgICBhd2FpdCBOZXdzbWFrZXIuc3RhdGVNYW5hZ2VyLmxvYWRTdGF0ZSgpO1xuICAgICAgICByZXR1cm4gTmV3c21ha2VyLmxhdGVzdDtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBhbGFybUxpc3RlbmVyID0gKGFsYXJtOiBjaHJvbWUuYWxhcm1zLkFsYXJtKTogdm9pZCA9PiB7XG4gICAgICAgIE5ld3NtYWtlci5pbml0KCk7XG4gICAgICAgIGlmIChhbGFybS5uYW1lID09PSBOZXdzbWFrZXIuQUxBUk1fTkFNRSkge1xuICAgICAgICAgICAgTmV3c21ha2VyLnVwZGF0ZU5ld3MoKTtcbiAgICAgICAgfVxuICAgIH07XG5cbiAgICBzdGF0aWMgc3Vic2NyaWJlKCk6IHZvaWQge1xuICAgICAgICBOZXdzbWFrZXIuaW5pdCgpO1xuICAgICAgICBpZiAoKE5ld3NtYWtlci5sYXRlc3RUaW1lc3RhbXAgPT09IG51bGwpIHx8IChOZXdzbWFrZXIubGF0ZXN0VGltZXN0YW1wICsgTmV3c21ha2VyLlVQREFURV9JTlRFUlZBTCA8IERhdGUubm93KCkpKSB7XG4gICAgICAgICAgICBOZXdzbWFrZXIudXBkYXRlTmV3cygpO1xuICAgICAgICB9XG4gICAgICAgIGNocm9tZS5hbGFybXMub25BbGFybS5hZGRMaXN0ZW5lcihOZXdzbWFrZXIuYWxhcm1MaXN0ZW5lcik7XG4gICAgICAgIGNocm9tZS5hbGFybXMuY3JlYXRlKE5ld3NtYWtlci5BTEFSTV9OQU1FLCB7cGVyaW9kSW5NaW51dGVzOiBOZXdzbWFrZXIuVVBEQVRFX0lOVEVSVkFMfSk7XG4gICAgfVxuXG4gICAgc3RhdGljIHVuU3Vic2NyaWJlKCk6IHZvaWQge1xuICAgICAgICAvLyBObyBuZWVkIHRvIGNhbGwgTmV3c21ha2VyLmluaXQoKVxuICAgICAgICBjaHJvbWUuYWxhcm1zLm9uQWxhcm0ucmVtb3ZlTGlzdGVuZXIoTmV3c21ha2VyLmFsYXJtTGlzdGVuZXIpO1xuICAgICAgICBjaHJvbWUuYWxhcm1zLmNsZWFyKE5ld3NtYWtlci5BTEFSTV9OQU1FKTtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBhc3luYyB1cGRhdGVOZXdzKCk6IFByb21pc2U8dm9pZD4ge1xuICAgICAgICBOZXdzbWFrZXIuaW5pdCgpO1xuICAgICAgICBjb25zdCBuZXdzID0gYXdhaXQgTmV3c21ha2VyLmdldE5ld3MoKTtcbiAgICAgICAgaWYgKEFycmF5LmlzQXJyYXkobmV3cykpIHtcbiAgICAgICAgICAgIE5ld3NtYWtlci5sYXRlc3QgPSBuZXdzO1xuICAgICAgICAgICAgTmV3c21ha2VyLmxhdGVzdFRpbWVzdGFtcCA9IERhdGUubm93KCk7XG4gICAgICAgICAgICBOZXdzbWFrZXIub25VcGRhdGUoKTtcbiAgICAgICAgICAgIGF3YWl0IE5ld3NtYWtlci5zdGF0ZU1hbmFnZXIuc2F2ZVN0YXRlKCk7XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBhc3luYyBnZXRSZWFkTmV3cygpOiBQcm9taXNlPHN0cmluZ1tdPiB7XG4gICAgICAgIE5ld3NtYWtlci5pbml0KCk7XG4gICAgICAgIGNvbnN0IFtcbiAgICAgICAgICAgIHN5bmMsXG4gICAgICAgICAgICBsb2NhbCxcbiAgICAgICAgXSA9IGF3YWl0IFByb21pc2UuYWxsKFtcbiAgICAgICAgICAgIHJlYWRTeW5jU3RvcmFnZSh7cmVhZE5ld3M6IFtdfSksXG4gICAgICAgICAgICByZWFkTG9jYWxTdG9yYWdlKHtyZWFkTmV3czogW119KSxcbiAgICAgICAgXSk7XG4gICAgICAgIHJldHVybiBBcnJheS5mcm9tKG5ldyBTZXQoW1xuICAgICAgICAgICAgLi4uc3luYyA/IHN5bmMucmVhZE5ld3MgOiBbXSxcbiAgICAgICAgICAgIC4uLmxvY2FsID8gbG9jYWwucmVhZE5ld3MgOiBbXSxcbiAgICAgICAgXSkpO1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIGFzeW5jIGdldERpc3BsYXllZE5ld3MoKTogUHJvbWlzZTxzdHJpbmdbXT4ge1xuICAgICAgICBOZXdzbWFrZXIuaW5pdCgpO1xuICAgICAgICBjb25zdCBbXG4gICAgICAgICAgICBzeW5jLFxuICAgICAgICAgICAgbG9jYWwsXG4gICAgICAgIF0gPSBhd2FpdCBQcm9taXNlLmFsbChbXG4gICAgICAgICAgICByZWFkU3luY1N0b3JhZ2Uoe2Rpc3BsYXllZE5ld3M6IFtdfSksXG4gICAgICAgICAgICByZWFkTG9jYWxTdG9yYWdlKHtkaXNwbGF5ZWROZXdzOiBbXX0pLFxuICAgICAgICBdKTtcbiAgICAgICAgcmV0dXJuIEFycmF5LmZyb20obmV3IFNldChbXG4gICAgICAgICAgICAuLi5zeW5jID8gc3luYy5kaXNwbGF5ZWROZXdzIDogW10sXG4gICAgICAgICAgICAuLi5sb2NhbCA/IGxvY2FsLmRpc3BsYXllZE5ld3MgOiBbXSxcbiAgICAgICAgXSkpO1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIGFzeW5jIGdldE5ld3MoKTogUHJvbWlzZTxOZXdzW10gfCBudWxsPiB7XG4gICAgICAgIE5ld3NtYWtlci5pbml0KCk7XG4gICAgICAgIGlmIChfX1RFU1RfXykge1xuICAgICAgICAgICAgcmV0dXJuIG5ld3NGb3JUZXN0aW5nO1xuICAgICAgICB9XG4gICAgICAgIHRyeSB7XG4gICAgICAgICAgICBjb25zdCByZXNwb25zZSA9IGF3YWl0IGZldGNoKE5FV1NfVVJMLCB7Y2FjaGU6ICduby1jYWNoZSd9KTtcbiAgICAgICAgICAgIGNvbnN0ICRuZXdzOiBBcnJheTxPbWl0PE5ld3MsICdyZWFkJyB8ICd1cmwnPiAmIHtkYXRlOiBzdHJpbmd9PiA9IGF3YWl0IHJlc3BvbnNlLmpzb24oKTtcbiAgICAgICAgICAgIGNvbnN0IHJlYWROZXdzID0gYXdhaXQgTmV3c21ha2VyLmdldFJlYWROZXdzKCk7XG4gICAgICAgICAgICBjb25zdCBkaXNwbGF5ZWROZXdzID0gYXdhaXQgTmV3c21ha2VyLmdldERpc3BsYXllZE5ld3MoKTtcbiAgICAgICAgICAgIGNvbnN0IG5ld3M6IE5ld3NbXSA9ICRuZXdzLm1hcCgobikgPT4ge1xuICAgICAgICAgICAgICAgIGNvbnN0IHVybCA9IGdldEJsb2dQb3N0VVJMKG4uaWQpO1xuICAgICAgICAgICAgICAgIGNvbnN0IHJlYWQgPSBOZXdzbWFrZXIud2FzUmVhZChuLmlkLCByZWFkTmV3cyk7XG4gICAgICAgICAgICAgICAgY29uc3QgZGlzcGxheWVkID0gTmV3c21ha2VyLndhc0Rpc3BsYXllZChuLmlkLCBkaXNwbGF5ZWROZXdzKTtcbiAgICAgICAgICAgICAgICByZXR1cm4gey4uLm4sIHVybCwgcmVhZCwgZGlzcGxheWVkfTtcbiAgICAgICAgICAgIH0pO1xuICAgICAgICAgICAgZm9yIChsZXQgaSA9IDA7IGkgPCBuZXdzLmxlbmd0aDsgaSsrKSB7XG4gICAgICAgICAgICAgICAgY29uc3QgZGF0ZSA9IG5ldyBEYXRlKG5ld3NbaV0uZGF0ZSk7XG4gICAgICAgICAgICAgICAgaWYgKGlzTmFOKGRhdGUuZ2V0VGltZSgpKSkge1xuICAgICAgICAgICAgICAgICAgICB0aHJvdyBuZXcgRXJyb3IoYFVuYWJsZSB0byBwYXJzZSBkYXRlICR7ZGF0ZX1gKTtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICByZXR1cm4gbmV3cztcbiAgICAgICAgfSBjYXRjaCAoZXJyKSB7XG4gICAgICAgICAgICBjb25zb2xlLmVycm9yKGVycik7XG4gICAgICAgICAgICByZXR1cm4gbnVsbDtcbiAgICAgICAgfVxuICAgIH1cblxuICAgIHN0YXRpYyBhc3luYyBtYXJrQXNSZWFkKGlkczogc3RyaW5nW10pOiBQcm9taXNlPHZvaWQ+IHtcbiAgICAgICAgTmV3c21ha2VyLmluaXQoKTtcbiAgICAgICAgY29uc3QgcmVhZE5ld3MgPSBhd2FpdCBOZXdzbWFrZXIuZ2V0UmVhZE5ld3MoKTtcbiAgICAgICAgY29uc3QgcmVzdWx0cyA9IHJlYWROZXdzLnNsaWNlKCk7XG4gICAgICAgIGxldCBjaGFuZ2VkID0gZmFsc2U7XG4gICAgICAgIGlkcy5mb3JFYWNoKChpZCkgPT4ge1xuICAgICAgICAgICAgaWYgKHJlYWROZXdzLmluZGV4T2YoaWQpIDwgMCkge1xuICAgICAgICAgICAgICAgIHJlc3VsdHMucHVzaChpZCk7XG4gICAgICAgICAgICAgICAgY2hhbmdlZCA9IHRydWU7XG4gICAgICAgICAgICB9XG4gICAgICAgIH0pO1xuICAgICAgICBpZiAoY2hhbmdlZCkge1xuICAgICAgICAgICAgTmV3c21ha2VyLmxhdGVzdCA9IE5ld3NtYWtlci5sYXRlc3QubWFwKChuKSA9PiB7XG4gICAgICAgICAgICAgICAgY29uc3QgcmVhZCA9IE5ld3NtYWtlci53YXNSZWFkKG4uaWQsIHJlc3VsdHMpO1xuICAgICAgICAgICAgICAgIHJldHVybiB7Li4ubiwgcmVhZH07XG4gICAgICAgICAgICB9KTtcbiAgICAgICAgICAgIE5ld3NtYWtlci5vblVwZGF0ZSgpO1xuICAgICAgICAgICAgY29uc3Qgb2JqID0ge3JlYWROZXdzOiByZXN1bHRzfTtcbiAgICAgICAgICAgIGF3YWl0IFByb21pc2UuYWxsKFtcbiAgICAgICAgICAgICAgICB3cml0ZUxvY2FsU3RvcmFnZShvYmopLFxuICAgICAgICAgICAgICAgIHdyaXRlU3luY1N0b3JhZ2Uob2JqKSxcbiAgICAgICAgICAgICAgICBOZXdzbWFrZXIuc3RhdGVNYW5hZ2VyLnNhdmVTdGF0ZSgpLFxuICAgICAgICAgICAgXSk7XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBzdGF0aWMgYXN5bmMgbWFya0FzRGlzcGxheWVkKGlkczogc3RyaW5nW10pOiBQcm9taXNlPHZvaWQ+IHtcbiAgICAgICAgTmV3c21ha2VyLmluaXQoKTtcbiAgICAgICAgY29uc3QgZGlzcGxheWVkTmV3cyA9IGF3YWl0IE5ld3NtYWtlci5nZXREaXNwbGF5ZWROZXdzKCk7XG4gICAgICAgIGNvbnN0IHJlc3VsdHMgPSBkaXNwbGF5ZWROZXdzLnNsaWNlKCk7XG4gICAgICAgIGxldCBjaGFuZ2VkID0gZmFsc2U7XG4gICAgICAgIGlkcy5mb3JFYWNoKChpZCkgPT4ge1xuICAgICAgICAgICAgaWYgKGRpc3BsYXllZE5ld3MuaW5kZXhPZihpZCkgPCAwKSB7XG4gICAgICAgICAgICAgICAgcmVzdWx0cy5wdXNoKGlkKTtcbiAgICAgICAgICAgICAgICBjaGFuZ2VkID0gdHJ1ZTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfSk7XG4gICAgICAgIGlmIChjaGFuZ2VkKSB7XG4gICAgICAgICAgICBOZXdzbWFrZXIubGF0ZXN0ID0gTmV3c21ha2VyLmxhdGVzdC5tYXAoKG4pID0+IHtcbiAgICAgICAgICAgICAgICBjb25zdCBkaXNwbGF5ZWQgPSBOZXdzbWFrZXIud2FzRGlzcGxheWVkKG4uaWQsIHJlc3VsdHMpO1xuICAgICAgICAgICAgICAgIHJldHVybiB7Li4ubiwgZGlzcGxheWVkfTtcbiAgICAgICAgICAgIH0pO1xuICAgICAgICAgICAgTmV3c21ha2VyLm9uVXBkYXRlKCk7XG4gICAgICAgICAgICBjb25zdCBvYmogPSB7ZGlzcGxheWVkTmV3czogcmVzdWx0c307XG4gICAgICAgICAgICBhd2FpdCBQcm9taXNlLmFsbChbXG4gICAgICAgICAgICAgICAgd3JpdGVMb2NhbFN0b3JhZ2Uob2JqKSxcbiAgICAgICAgICAgICAgICB3cml0ZVN5bmNTdG9yYWdlKG9iaiksXG4gICAgICAgICAgICAgICAgTmV3c21ha2VyLnN0YXRlTWFuYWdlci5zYXZlU3RhdGUoKSxcbiAgICAgICAgICAgIF0pO1xuICAgICAgICB9XG4gICAgfVxuXG4gICAgcHJpdmF0ZSBzdGF0aWMgd2FzUmVhZChpZDogc3RyaW5nLCByZWFkTmV3czogc3RyaW5nW10pOiBib29sZWFuIHtcbiAgICAgICAgcmV0dXJuIHJlYWROZXdzLmluY2x1ZGVzKGlkKTtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyB3YXNEaXNwbGF5ZWQoaWQ6IHN0cmluZywgZGlzcGxheWVkTmV3czogc3RyaW5nW10pOiBib29sZWFuIHtcbiAgICAgICAgcmV0dXJuIGRpc3BsYXllZE5ld3MuaW5jbHVkZXMoaWQpO1xuICAgIH1cbn1cblxuZXhwb3J0IGZ1bmN0aW9uIHNldE5ld3NGb3JUZXN0aW5nKG5ld3M6IE5ld3NbXSk6IHZvaWQge1xuICAgIGlmIChfX1RFU1RfXykge1xuICAgICAgICBuZXdzRm9yVGVzdGluZyA9IG5ld3M7XG4gICAgfVxufVxuIiwiaW1wb3J0IHtpc09wZXJhfSBmcm9tICcuLi8uLi91dGlscy9wbGF0Zm9ybSc7XG5cbi8vIE9uIFRodW5kZXJiaXJkLCBzb21ldGltZXMgc2VuZGVyLnRhYiBpcyB1bmRlZmluZWQgYnV0IGFjY2Vzc2luZyBpdCB3aWxsIHRocm93IGEgdmVyeSBuaWNlIGVycm9yLlxuLy8gT24gVml2YWxkaSwgc29tZXRpbWVzIHNlbmRlci50YWIgaXMgdW5kZWZpbmVkIGFzIHdlbGwsIGJ1dCBlcnJvciBpcyBub3QgdmVyeSBoZWxwZnVsLlxuLy8gT24gT3BlcmEsIHNlbmRlci50YWIuaW5kZXggPT09IC0xLlxuZXhwb3J0IGZ1bmN0aW9uIGlzUGFuZWwoc2VuZGVyOiBjaHJvbWUucnVudGltZS5NZXNzYWdlU2VuZGVyKTogYm9vbGVhbiB7XG4gICAgcmV0dXJuIHR5cGVvZiBzZW5kZXIgPT09ICd1bmRlZmluZWQnIHx8IHR5cGVvZiBzZW5kZXIudGFiID09PSAndW5kZWZpbmVkJyB8fCAoaXNPcGVyYSAmJiBzZW5kZXIudGFiLmluZGV4ID09PSAtMSk7XG59XG4iLCJpbXBvcnQge2NhbkluamVjdFNjcmlwdH0gZnJvbSAnLi4vYmFja2dyb3VuZC91dGlscy9leHRlbnNpb24tYXBpJztcbmltcG9ydCB0eXBlIHtNZXNzYWdlQkd0b0NTLCBNZXNzYWdlQ1N0b0JHLCBNZXNzYWdlVUl0b0JHfSBmcm9tICcuLi9kZWZpbml0aW9ucyc7XG5pbXBvcnQge01lc3NhZ2VUeXBlQ1N0b0JHLCBNZXNzYWdlVHlwZUJHdG9DUywgTWVzc2FnZVR5cGVVSXRvQkd9IGZyb20gJy4uL3V0aWxzL21lc3NhZ2UnO1xuaW1wb3J0IHtpc0ZpcmVmb3h9IGZyb20gJy4uL3V0aWxzL3BsYXRmb3JtJztcbmltcG9ydCB7U3RhdGVNYW5hZ2VyfSBmcm9tICcuLi91dGlscy9zdGF0ZS1tYW5hZ2VyJztcbmltcG9ydCB7Z2V0QWN0aXZlVGFiLCBxdWVyeVRhYnN9IGZyb20gJy4uL3V0aWxzL3RhYnMnO1xuaW1wb3J0IHtnZXRVUkxIb3N0T3JQcm90b2NvbH0gZnJvbSAnLi4vdXRpbHMvdXJsJztcbmltcG9ydCBJY29uTWFuYWdlciBmcm9tICcuL2ljb24tbWFuYWdlcic7XG5cbmltcG9ydCB7bWFrZUZpcmVmb3hIYXBweX0gZnJvbSAnLi9tYWtlLWZpcmVmb3gtaGFwcHknO1xuaW1wb3J0IHtBU1NFUlQsIGxvZ0luZm8sIGxvZ1dhcm59IGZyb20gJy4vdXRpbHMvbG9nJztcbmltcG9ydCB0eXBlIHtGaWxlTG9hZGVyfSBmcm9tICcuL3V0aWxzL25ldHdvcmsnO1xuaW1wb3J0IHtjcmVhdGVGaWxlTG9hZGVyfSBmcm9tICcuL3V0aWxzL25ldHdvcmsnO1xuaW1wb3J0IHtpc1BhbmVsfSBmcm9tICcuL3V0aWxzL3RhYic7XG5cbmRlY2xhcmUgY29uc3QgX19DSFJPTUlVTV9NVjJfXzogYm9vbGVhbjtcbmRlY2xhcmUgY29uc3QgX19DSFJPTUlVTV9NVjNfXzogYm9vbGVhbjtcbmRlY2xhcmUgY29uc3QgX19USFVOREVSQklSRF9fOiBib29sZWFuO1xuXG5pbnRlcmZhY2UgVGFiTWFuYWdlck9wdGlvbnMge1xuICAgIGdldENvbm5lY3Rpb25NZXNzYWdlOiAodGFiVVJsOiBzdHJpbmcsIHVybDogc3RyaW5nLCBpc1RvcEZyYW1lOiBib29sZWFuLCB0b3BGcmFtZUhhc0RhcmtUaGVtZT86IGJvb2xlYW4pID0+IFByb21pc2U8TWVzc2FnZUJHdG9DUz47XG4gICAgZ2V0VGFiTWVzc2FnZTogKHRhYlVSTDogc3RyaW5nLCB1cmw6IHN0cmluZywgaXNUb3BGcmFtZTogYm9vbGVhbikgPT4gTWVzc2FnZUJHdG9DUztcbiAgICBvbkNvbG9yU2NoZW1lQ2hhbmdlOiAoaXNEYXJrOiBib29sZWFuKSA9PiB2b2lkO1xufVxuXG5pbnRlcmZhY2UgRG9jdW1lbnRJbmZvIHtcbiAgICBzY3JpcHRJZDogc3RyaW5nO1xuICAgIGRvY3VtZW50SWQ6IHN0cmluZyB8IG51bGw7XG4gICAgaXNUb3A6IHRydWUgfCB1bmRlZmluZWQ7XG4gICAgdXJsOiBzdHJpbmcgfCBudWxsO1xuICAgIHN0YXRlOiBEb2N1bWVudFN0YXRlO1xuICAgIHRpbWVzdGFtcDogbnVtYmVyO1xuICAgIGRhcmtUaGVtZURldGVjdGVkOiBib29sZWFuO1xufVxuXG5pbnRlcmZhY2UgVGFiTWFuYWdlclN0YXRlIGV4dGVuZHMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4ge1xuICAgIHRhYnM6IHtbdGFiSWQ6IG51bWJlcl06IHtbZnJhbWVJZDogbnVtYmVyXTogRG9jdW1lbnRJbmZvfX07XG4gICAgdGltZXN0YW1wOiBudW1iZXI7XG59XG5cbi8qKlxuICogVGhlc2Ugc3RhdGVzIGNvcnJlc3BvbmQgdG8gcG9zc2libGUgZG9jdW1lbnQgc3RhdGVzIGluIFBhZ2UgTGlmZWN5Y2xlIEFQSTpcbiAqIGh0dHBzOi8vZGV2ZWxvcGVycy5nb29nbGUuY29tL3dlYi91cGRhdGVzLzIwMTgvMDcvcGFnZS1saWZlY3ljbGUtYXBpI2RldmVsb3Blci1yZWNvbW1lbmRhdGlvbnMtZm9yLWVhY2gtc3RhdGVcbiAqIFNvbWUgc3RhdGVzIGFyZSBub3QgY3VycmVudGx5IHVzZWQgKHRoZXkgYXJlIGRlY2xhcmVkIGZvciBmdXR1cmUtcHJvb2ZpbmcpLlxuICovXG5lbnVtIERvY3VtZW50U3RhdGUge1xuICAgIEFDVElWRSA9IDAsXG4gICAgUEFTU0lWRSA9IDEsXG4gICAgSElEREVOID0gMixcbiAgICBGUk9aRU4gPSAzLFxuICAgIFRFUk1JTkFURUQgPSA0LFxuICAgIERJU0NBUkRFRCA9IDVcbn1cblxuLyoqXG4gKiBOb3RlOiBPbiBDaHJvbWl1bSBidWlsZHMsIHdlIHVzZSBkb2N1bWVudElkIGlmIGl0IGlzIGF2YWlsYWJsZS5cbiAqIFdlIGF2b2lkIG1lc3NhZ2luZyB1c2luZyBmcmFtZUlkIGVudGlyZWx5IHNpbmNlIHdoZW4gZG9jdW1lbnQgaXMgcHJlLXJlbmRlcmVkLCBpdCBnZXRzIGEgdGVtcG9yYXJ5IGZyYW1lSWRcbiAqIGFuZCBpZiB3ZSBhdHRlbXB0IHRvIHNlbmQgdG8ge2ZyYW1lSWQsIGRvY3VtZW50SWR9IHdpdGggb2xkIGZyYW1lSWQsIHRoZW4gdGhlIG1lc3NhZ2Ugd2lsbCBiZSBkcm9wcGVkLlxuICovXG5leHBvcnQgZGVmYXVsdCBjbGFzcyBUYWJNYW5hZ2VyIHtcbiAgICBwcml2YXRlIHN0YXRpYyB0YWJzOiBUYWJNYW5hZ2VyU3RhdGVbJ3RhYnMnXTtcbiAgICBwcml2YXRlIHN0YXRpYyBzdGF0ZU1hbmFnZXI6IFN0YXRlTWFuYWdlcjxUYWJNYW5hZ2VyU3RhdGU+O1xuICAgIHByaXZhdGUgc3RhdGljIGZpbGVMb2FkZXI6IEZpbGVMb2FkZXIgfCBudWxsID0gbnVsbDtcbiAgICBwcml2YXRlIHN0YXRpYyBvbkNvbG9yU2NoZW1lQ2hhbmdlOiBUYWJNYW5hZ2VyT3B0aW9uc1snb25Db2xvclNjaGVtZUNoYW5nZSddO1xuICAgIHByaXZhdGUgc3RhdGljIGdldFRhYk1lc3NhZ2U6IFRhYk1hbmFnZXJPcHRpb25zWydnZXRUYWJNZXNzYWdlJ107XG4gICAgcHJpdmF0ZSBzdGF0aWMgdGltZXN0YW1wOiBUYWJNYW5hZ2VyU3RhdGVbJ3RpbWVzdGFtcCddO1xuICAgIHByaXZhdGUgc3RhdGljIHJlYWRvbmx5IExPQ0FMX1NUT1JBR0VfS0VZID0gJ1RhYk1hbmFnZXItc3RhdGUnO1xuXG4gICAgc3RhdGljIGluaXQoe2dldENvbm5lY3Rpb25NZXNzYWdlLCBvbkNvbG9yU2NoZW1lQ2hhbmdlLCBnZXRUYWJNZXNzYWdlfTogVGFiTWFuYWdlck9wdGlvbnMpOiB2b2lkIHtcbiAgICAgICAgVGFiTWFuYWdlci5zdGF0ZU1hbmFnZXIgPSBuZXcgU3RhdGVNYW5hZ2VyPFRhYk1hbmFnZXJTdGF0ZT4oVGFiTWFuYWdlci5MT0NBTF9TVE9SQUdFX0tFWSwgdGhpcywge3RhYnM6IHt9LCB0aW1lc3RhbXA6IDB9LCBsb2dXYXJuKTtcbiAgICAgICAgVGFiTWFuYWdlci50YWJzID0ge307XG4gICAgICAgIFRhYk1hbmFnZXIub25Db2xvclNjaGVtZUNoYW5nZSA9IG9uQ29sb3JTY2hlbWVDaGFuZ2U7XG4gICAgICAgIFRhYk1hbmFnZXIuZ2V0VGFiTWVzc2FnZSA9IGdldFRhYk1lc3NhZ2U7XG5cbiAgICAgICAgY2hyb21lLnJ1bnRpbWUub25NZXNzYWdlLmFkZExpc3RlbmVyKChtZXNzYWdlOiBNZXNzYWdlQ1N0b0JHIHwgTWVzc2FnZVVJdG9CRywgc2VuZGVyLCBzZW5kUmVzcG9uc2UpOiBib29sZWFuID0+IHtcbiAgICAgICAgICAgIGlmIChpc0ZpcmVmb3ggJiYgbWFrZUZpcmVmb3hIYXBweShtZXNzYWdlLCBzZW5kZXIsIHNlbmRSZXNwb25zZSkpIHtcbiAgICAgICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICBzd2l0Y2ggKG1lc3NhZ2UudHlwZSkge1xuICAgICAgICAgICAgICAgIGNhc2UgTWVzc2FnZVR5cGVDU3RvQkcuRE9DVU1FTlRfQ09OTkVDVDoge1xuICAgICAgICAgICAgICAgICAgICBpZiAoX19DSFJPTUlVTV9NVjNfXyAmJiBpc1BhbmVsKHNlbmRlcikpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgIHNlbmRSZXNwb25zZSh7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgdHlwZTogTWVzc2FnZVR5cGVCR3RvQ1MuVU5TVVBQT1JURURfU0VOREVSLFxuICAgICAgICAgICAgICAgICAgICAgICAgfSk7XG4gICAgICAgICAgICAgICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgVGFiTWFuYWdlci5vbkNvbG9yU2NoZW1lTWVzc2FnZShtZXNzYWdlLCBzZW5kZXIpO1xuXG4gICAgICAgICAgICAgICAgICAgIGNvbnN0IHJlcGx5ID0gKHRhYlVSTDogc3RyaW5nLCB1cmw6IHN0cmluZywgaXNUb3BGcmFtZTogYm9vbGVhbiwgdG9wRnJhbWVIYXNEYXJrVGhlbWU/OiBib29sZWFuKSA9PiB7XG4gICAgICAgICAgICAgICAgICAgICAgICBnZXRDb25uZWN0aW9uTWVzc2FnZSh0YWJVUkwsIHVybCwgaXNUb3BGcmFtZSwgdG9wRnJhbWVIYXNEYXJrVGhlbWUpLnRoZW4oKHJlc3BvbnNlKSA9PiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgaWYgKCFyZXNwb25zZSkge1xuICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICByZXR1cm47XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICAgICAgICAgIHJlc3BvbnNlLnNjcmlwdElkID0gbWVzc2FnZS5zY3JpcHRJZCE7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgVGFiTWFuYWdlci5zZW5kRG9jdW1lbnRNZXNzYWdlKHNlbmRlci50YWIhLmlkISwgc2VuZGVyLmRvY3VtZW50SWQhLCByZXNwb25zZSwgc2VuZGVyLmZyYW1lSWQhKTtcbiAgICAgICAgICAgICAgICAgICAgICAgIH0pO1xuICAgICAgICAgICAgICAgICAgICB9O1xuXG4gICAgICAgICAgICAgICAgICAgIGlmIChpc1BhbmVsKHNlbmRlcikpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgIC8vIE5PVEU6IFZpdmFsZGkgYW5kIE9wZXJhIGNhbiBzaG93IGEgcGFnZSBpbiBhIHNpZGUgcGFuZWwsXG4gICAgICAgICAgICAgICAgICAgICAgICAvLyBidXQgaXQgaXMgbm90IHBvc3NpYmxlIHRvIGhhbmRsZSBtZXNzYWdpbmcgY29ycmVjdGx5IChubyB0YWIgSUQsIGZyYW1lIElEKS5cbiAgICAgICAgICAgICAgICAgICAgICAgIGlmIChpc0ZpcmVmb3gpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBpZiAoc2VuZGVyICYmIHNlbmRlci50YWIgJiYgdHlwZW9mIHNlbmRlci50YWIuaWQgPT09ICdudW1iZXInKSB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGNocm9tZS50YWJzLnNlbmRNZXNzYWdlPE1lc3NhZ2VCR3RvQ1M+KHNlbmRlci50YWIuaWQsXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdHlwZTogTWVzc2FnZVR5cGVCR3RvQ1MuVU5TVVBQT1JURURfU0VOREVSLFxuICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHNjcmlwdElkOiBtZXNzYWdlLnNjcmlwdElkISxcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgZnJhbWVJZDogc2VuZGVyICYmIHR5cGVvZiBzZW5kZXIuZnJhbWVJZCA9PT0gJ251bWJlcicgPyBzZW5kZXIuZnJhbWVJZCA6IHVuZGVmaW5lZCxcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0pO1xuICAgICAgICAgICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgc2VuZFJlc3BvbnNlKCd1bnN1cHBvcnRlZFNlbmRlcicpO1xuICAgICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgICAgICAgICAgICAgICAgICB9XG5cbiAgICAgICAgICAgICAgICAgICAgY29uc3Qge2ZyYW1lSWR9ID0gc2VuZGVyO1xuICAgICAgICAgICAgICAgICAgICBjb25zdCBpc1RvcEZyYW1lOiBib29sZWFuID0gKF9fQ0hST01JVU1fTVYyX18gfHwgX19DSFJPTUlVTV9NVjNfXykgPyAoZnJhbWVJZCA9PT0gMCB8fCBtZXNzYWdlLmRhdGEuaXNUb3BGcmFtZSkgOiBmcmFtZUlkID09PSAwO1xuICAgICAgICAgICAgICAgICAgICBjb25zdCB1cmwgPSBzZW5kZXIudXJsITtcbiAgICAgICAgICAgICAgICAgICAgY29uc3QgdGFiSWQgPSBzZW5kZXIudGFiIS5pZCE7XG4gICAgICAgICAgICAgICAgICAgIGNvbnN0IHNjcmlwdElkID0gbWVzc2FnZS5zY3JpcHRJZCE7XG4gICAgICAgICAgICAgICAgICAgIC8vIENocm9taXVtIDEwNisgbWF5IHByZXJlbmRlciBmcmFtZXMgcmVzdWx0aW5nIGluIHRvcC1sZXZlbCBmcmFtZXMgd2l0aCBjaHJvbWUucnVudGltZS5NZXNzYWdlU2VuZGVyLnRhYi51cmxcbiAgICAgICAgICAgICAgICAgICAgLy8gc2V0IHRvIGNocm9tZTovL25ld3RhYi8gYW5kIHBvc2l0aXZlIGNocm9tZS5ydW50aW1lLk1lc3NhZ2VTZW5kZXIuZnJhbWVJZFxuICAgICAgICAgICAgICAgICAgICBjb25zdCB0YWJVUkwgPSAoKF9fQ0hST01JVU1fTVYyX18gfHwgX19DSFJPTUlVTV9NVjNfXykgJiYgaXNUb3BGcmFtZSkgPyB1cmwgOiBzZW5kZXIudGFiIS51cmwhO1xuICAgICAgICAgICAgICAgICAgICBjb25zdCBkb2N1bWVudElkOiBzdHJpbmcgfCBudWxsID0gX19DSFJPTUlVTV9NVjNfXyA/IHNlbmRlci5kb2N1bWVudElkISA6IChzZW5kZXIuZG9jdW1lbnRJZCB8fCBudWxsKTtcblxuICAgICAgICAgICAgICAgICAgICBUYWJNYW5hZ2VyLnN0YXRlTWFuYWdlci5sb2FkU3RhdGUoKS50aGVuKCgpID0+IHtcbiAgICAgICAgICAgICAgICAgICAgICAgIFRhYk1hbmFnZXIuYWRkRnJhbWUodGFiSWQsIGZyYW1lSWQhLCBkb2N1bWVudElkLCBzY3JpcHRJZCwgdXJsLCBpc1RvcEZyYW1lKTtcbiAgICAgICAgICAgICAgICAgICAgICAgIGNvbnN0IHRvcEZyYW1lSGFzRGFya1RoZW1lID0gaXNUb3BGcmFtZSA/IGZhbHNlIDogVGFiTWFuYWdlci50YWJzW3RhYklkXT8uWzBdPy5kYXJrVGhlbWVEZXRlY3RlZDtcbiAgICAgICAgICAgICAgICAgICAgICAgIHJlcGx5KHRhYlVSTCwgdXJsLCBpc1RvcEZyYW1lLCB0b3BGcmFtZUhhc0RhcmtUaGVtZSk7XG4gICAgICAgICAgICAgICAgICAgICAgICBUYWJNYW5hZ2VyLnN0YXRlTWFuYWdlci5zYXZlU3RhdGUoKTtcbiAgICAgICAgICAgICAgICAgICAgfSk7XG4gICAgICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgICAgIH1cblxuICAgICAgICAgICAgICAgIGNhc2UgTWVzc2FnZVR5cGVDU3RvQkcuRE9DVU1FTlRfRk9SR0VUOlxuICAgICAgICAgICAgICAgICAgICBpZiAoIXNlbmRlci50YWIpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgIGxvZ1dhcm4oJ1VuZXhwZWN0ZWQgbWVzc2FnZScsIG1lc3NhZ2UsIHNlbmRlcik7XG4gICAgICAgICAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICBBU1NFUlQoJ0hhcyBhIHNjcmlwdElkJywgKCkgPT4gQm9vbGVhbihtZXNzYWdlLnNjcmlwdElkKSk7XG4gICAgICAgICAgICAgICAgICAgIFRhYk1hbmFnZXIucmVtb3ZlRnJhbWUoc2VuZGVyLnRhYiEuaWQhLCBzZW5kZXIuZnJhbWVJZCEpO1xuICAgICAgICAgICAgICAgICAgICBicmVhaztcblxuICAgICAgICAgICAgICAgIGNhc2UgTWVzc2FnZVR5cGVDU3RvQkcuRE9DVU1FTlRfRlJFRVpFOiB7XG4gICAgICAgICAgICAgICAgICAgIFRhYk1hbmFnZXIuc3RhdGVNYW5hZ2VyLmxvYWRTdGF0ZSgpLnRoZW4oKCkgPT4ge1xuICAgICAgICAgICAgICAgICAgICAgICAgY29uc3QgaW5mbyA9IFRhYk1hbmFnZXIudGFic1tzZW5kZXIudGFiIS5pZCFdW3NlbmRlci5mcmFtZUlkIV07XG4gICAgICAgICAgICAgICAgICAgICAgICBpbmZvLnN0YXRlID0gRG9jdW1lbnRTdGF0ZS5GUk9aRU47XG4gICAgICAgICAgICAgICAgICAgICAgICBpbmZvLnVybCA9IG51bGw7XG4gICAgICAgICAgICAgICAgICAgICAgICBUYWJNYW5hZ2VyLnN0YXRlTWFuYWdlci5zYXZlU3RhdGUoKTtcbiAgICAgICAgICAgICAgICAgICAgfSk7XG4gICAgICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgICAgIH1cblxuICAgICAgICAgICAgICAgIGNhc2UgTWVzc2FnZVR5cGVDU3RvQkcuRE9DVU1FTlRfUkVTVU1FOiB7XG4gICAgICAgICAgICAgICAgICAgIFRhYk1hbmFnZXIub25Db2xvclNjaGVtZU1lc3NhZ2UobWVzc2FnZSwgc2VuZGVyKTtcbiAgICAgICAgICAgICAgICAgICAgY29uc3QgdGFiSWQgPSBzZW5kZXIudGFiIS5pZCE7XG4gICAgICAgICAgICAgICAgICAgIGNvbnN0IHRhYlVSTCA9IHNlbmRlci50YWIhLnVybCE7XG4gICAgICAgICAgICAgICAgICAgIGNvbnN0IGZyYW1lSWQgPSBzZW5kZXIuZnJhbWVJZCE7XG4gICAgICAgICAgICAgICAgICAgIGNvbnN0IHVybCA9IHNlbmRlci51cmwhO1xuICAgICAgICAgICAgICAgICAgICBjb25zdCBkb2N1bWVudElkOiBzdHJpbmcgfCBudWxsID0gX19DSFJPTUlVTV9NVjNfXyA/IHNlbmRlci5kb2N1bWVudElkISA6IChzZW5kZXIuZG9jdW1lbnRJZCEgfHwgbnVsbCk7XG4gICAgICAgICAgICAgICAgICAgIGNvbnN0IGlzVG9wRnJhbWU6IGJvb2xlYW4gPSAoX19DSFJPTUlVTV9NVjJfXyB8fCBfX0NIUk9NSVVNX01WM19fKSA/IChmcmFtZUlkID09PSAwIHx8IG1lc3NhZ2UuZGF0YS5pc1RvcEZyYW1lKSA6IGZyYW1lSWQgPT09IDA7XG4gICAgICAgICAgICAgICAgICAgIFRhYk1hbmFnZXIuc3RhdGVNYW5hZ2VyLmxvYWRTdGF0ZSgpLnRoZW4oKCkgPT4ge1xuICAgICAgICAgICAgICAgICAgICAgICAgaWYgKFRhYk1hbmFnZXIudGFic1t0YWJJZF1bZnJhbWVJZF0udGltZXN0YW1wIDwgVGFiTWFuYWdlci50aW1lc3RhbXApIHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb25zdCByZXNwb25zZSA9IFRhYk1hbmFnZXIuZ2V0VGFiTWVzc2FnZSh0YWJVUkwsIHVybCwgaXNUb3BGcmFtZSk7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgcmVzcG9uc2Uuc2NyaXB0SWQgPSBtZXNzYWdlLnNjcmlwdElkITtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBUYWJNYW5hZ2VyLnNlbmREb2N1bWVudE1lc3NhZ2UodGFiSWQsIGRvY3VtZW50SWQhLCByZXNwb25zZSwgZnJhbWVJZCEpO1xuICAgICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICAgICAgVGFiTWFuYWdlci50YWJzW3NlbmRlci50YWIhLmlkIV1bc2VuZGVyLmZyYW1lSWQhXSA9IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBkb2N1bWVudElkLFxuICAgICAgICAgICAgICAgICAgICAgICAgICAgIHNjcmlwdElkOiBtZXNzYWdlLnNjcmlwdElkISxcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICB1cmwsXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgaXNUb3A6IGlzVG9wRnJhbWUgfHwgdW5kZWZpbmVkLFxuICAgICAgICAgICAgICAgICAgICAgICAgICAgIHN0YXRlOiBEb2N1bWVudFN0YXRlLkFDVElWRSxcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBkYXJrVGhlbWVEZXRlY3RlZDogZmFsc2UsXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgdGltZXN0YW1wOiBUYWJNYW5hZ2VyLnRpbWVzdGFtcCxcbiAgICAgICAgICAgICAgICAgICAgICAgIH07XG4gICAgICAgICAgICAgICAgICAgICAgICBUYWJNYW5hZ2VyLnN0YXRlTWFuYWdlci5zYXZlU3RhdGUoKTtcbiAgICAgICAgICAgICAgICAgICAgfSk7XG4gICAgICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgICAgIH1cblxuICAgICAgICAgICAgICAgIGNhc2UgTWVzc2FnZVR5cGVDU3RvQkcuREFSS19USEVNRV9ERVRFQ1RFRDoge1xuICAgICAgICAgICAgICAgICAgICBjb25zdCB0YWJJZCA9IHNlbmRlci50YWIhLmlkITtcbiAgICAgICAgICAgICAgICAgICAgY29uc3QgZnJhbWVzID0gVGFiTWFuYWdlci50YWJzW3RhYklkXTtcbiAgICAgICAgICAgICAgICAgICAgaWYgKCFmcmFtZXMpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgIGZvciAoY29uc3QgZW50cnkgb2YgT2JqZWN0LmVudHJpZXMoZnJhbWVzKSkge1xuICAgICAgICAgICAgICAgICAgICAgICAgY29uc3QgZnJhbWVJZCA9IE51bWJlcihlbnRyeVswXSk7XG4gICAgICAgICAgICAgICAgICAgICAgICBjb25zdCBmcmFtZSA9IGVudHJ5WzFdO1xuICAgICAgICAgICAgICAgICAgICAgICAgZnJhbWUuZGFya1RoZW1lRGV0ZWN0ZWQgPSB0cnVlO1xuICAgICAgICAgICAgICAgICAgICAgICAgY29uc3Qge2RvY3VtZW50SWQsIHNjcmlwdElkfSA9IGZyYW1lO1xuICAgICAgICAgICAgICAgICAgICAgICAgaWYgKGRvY3VtZW50SWQpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb25zdCBtZXNzYWdlID0ge1xuICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICB0eXBlOiBNZXNzYWdlVHlwZUJHdG9DUy5DTEVBTl9VUCxcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgc2NyaXB0SWQsXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgfTtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBUYWJNYW5hZ2VyLnNlbmREb2N1bWVudE1lc3NhZ2UodGFiSWQsIGRvY3VtZW50SWQsIG1lc3NhZ2UsIGZyYW1lSWQpO1xuICAgICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICAgICAgaWYgKGZyYW1lSWQgPT09IDApIHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBJY29uTWFuYWdlci5zZXRJY29uKHt0YWJJZCwgaXNBY3RpdmU6IGZhbHNlfSk7XG4gICAgICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICAgICAgfVxuXG4gICAgICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZUNTdG9CRy5GRVRDSDoge1xuICAgICAgICAgICAgICAgICAgICAvLyBVc2luZyBjdXN0b20gcmVzcG9uc2UgZHVlIHRvIENocm9tZSBhbmQgRmlyZWZveCBpbmNvbXBhdGliaWxpdHlcbiAgICAgICAgICAgICAgICAgICAgLy8gU29tZXRpbWVzIGZldGNoIGVycm9yIGJlaGF2ZXMgbGlrZSBzeW5jaHJvbm91cyBhbmQgc2VuZHMgYHVuZGVmaW5lZGBcbiAgICAgICAgICAgICAgICAgICAgY29uc3QgaWQgPSBtZXNzYWdlLmlkO1xuICAgICAgICAgICAgICAgICAgICAvLyBXZSBkbyBub3QgbmVlZCB0byB1c2Ugc2NyaXB0SWQgaGVyZSBzaW5jZSBldmVyeSByZXF1ZXN0IGhhcyBhIHVuaXF1ZSBpZCBhbHJlYWR5XG4gICAgICAgICAgICAgICAgICAgIGNvbnN0IHNlbmRSZXNwb25zZSA9IChyZXNwb25zZTogUGFydGlhbDxNZXNzYWdlQkd0b0NTPikgPT4ge1xuICAgICAgICAgICAgICAgICAgICAgICAgVGFiTWFuYWdlci5zZW5kRG9jdW1lbnRNZXNzYWdlKHNlbmRlci50YWIhLmlkISwgc2VuZGVyLmRvY3VtZW50SWQhLCB7dHlwZTogTWVzc2FnZVR5cGVCR3RvQ1MuRkVUQ0hfUkVTUE9OU0UsIGlkLCAuLi5yZXNwb25zZX0sIHNlbmRlci5mcmFtZUlkISk7XG4gICAgICAgICAgICAgICAgICAgIH07XG5cbiAgICAgICAgICAgICAgICAgICAgaWYgKF9fVEhVTkRFUkJJUkRfXykge1xuICAgICAgICAgICAgICAgICAgICAgICAgLy8gSW4gdGh1bmRlcmJpcmQgc29tZSBDU1MgaXMgbG9hZGVkIG9uIGEgY2hyb21lOi8vIFVSTC5cbiAgICAgICAgICAgICAgICAgICAgICAgIC8vIFRodW5kZXJiaXJkIHJlc3RyaWN0ZWQgQWRkLW9ucyB0byBsb2FkIHRob3NlIFVSTCdzLlxuICAgICAgICAgICAgICAgICAgICAgICAgaWYgKChtZXNzYWdlLmRhdGEudXJsIGFzIHN0cmluZykuc3RhcnRzV2l0aCgnY2hyb21lOi8vJykpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBzZW5kUmVzcG9uc2Uoe2RhdGE6IG51bGx9KTtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgY29uc3Qge3VybCwgcmVzcG9uc2VUeXBlLCBtaW1lVHlwZSwgb3JpZ2lufSA9IG1lc3NhZ2UuZGF0YTtcbiAgICAgICAgICAgICAgICAgICAgaWYgKCFUYWJNYW5hZ2VyLmZpbGVMb2FkZXIpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgIFRhYk1hbmFnZXIuZmlsZUxvYWRlciA9IGNyZWF0ZUZpbGVMb2FkZXIoKTtcbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICBUYWJNYW5hZ2VyLmZpbGVMb2FkZXIuZ2V0KHt1cmwsIHJlc3BvbnNlVHlwZSwgbWltZVR5cGUsIG9yaWdpbn0pLnRoZW4oKHJlc3BvbnNlKSA9PiB7XG4gICAgICAgICAgICAgICAgICAgICAgICBpZiAocmVzcG9uc2UuZXJyb3IpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb25zdCBlcnIgPSByZXNwb25zZS5lcnJvcjtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBzZW5kUmVzcG9uc2Uoe2Vycm9yOiBlcnI/Lm1lc3NhZ2UgPz8gZXJyfSk7XG4gICAgICAgICAgICAgICAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgICAgICAgICAgICAgICAgIHNlbmRSZXNwb25zZSh7ZGF0YTogcmVzcG9uc2UuZGF0YX0pO1xuICAgICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICB9KTtcbiAgICAgICAgICAgICAgICAgICAgcmV0dXJuIHRydWU7XG4gICAgICAgICAgICAgICAgfVxuXG4gICAgICAgICAgICAgICAgY2FzZSBNZXNzYWdlVHlwZVVJdG9CRy5DT0xPUl9TQ0hFTUVfQ0hBTkdFOlxuICAgICAgICAgICAgICAgICAgICAvLyBmYWxsdGhyb3VnaFxuICAgICAgICAgICAgICAgIGNhc2UgTWVzc2FnZVR5cGVDU3RvQkcuQ09MT1JfU0NIRU1FX0NIQU5HRTpcbiAgICAgICAgICAgICAgICAgICAgVGFiTWFuYWdlci5vbkNvbG9yU2NoZW1lTWVzc2FnZShtZXNzYWdlIGFzIE1lc3NhZ2VDU3RvQkcsIHNlbmRlcik7XG4gICAgICAgICAgICAgICAgICAgIGJyZWFrO1xuXG4gICAgICAgICAgICAgICAgZGVmYXVsdDpcbiAgICAgICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICB9XG5cbiAgICAgICAgICAgIHJldHVybiBmYWxzZTtcbiAgICAgICAgfSk7XG5cbiAgICAgICAgY2hyb21lLnRhYnMub25SZW1vdmVkLmFkZExpc3RlbmVyKGFzeW5jICh0YWJJZCkgPT4gVGFiTWFuYWdlci5yZW1vdmVGcmFtZSh0YWJJZCwgMCkpO1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIHNlbmREb2N1bWVudE1lc3NhZ2UodGFiSWQ6IG51bWJlciwgZG9jdW1lbnRJZDogc3RyaW5nLCBtZXNzYWdlOiBNZXNzYWdlQkd0b0NTLCBmcmFtZUlkOiBudW1iZXIpIHtcbiAgICAgICAgaWYgKGZyYW1lSWQgPT09IDApIHtcbiAgICAgICAgICAgIGNvbnN0IHRoZW1lTWVzc2FnZVR5cGVzOiBNZXNzYWdlVHlwZUJHdG9DU1tdID0gW1xuICAgICAgICAgICAgICAgIE1lc3NhZ2VUeXBlQkd0b0NTLkFERF9DU1NfRklMVEVSLFxuICAgICAgICAgICAgICAgIE1lc3NhZ2VUeXBlQkd0b0NTLkFERF9EWU5BTUlDX1RIRU1FLFxuICAgICAgICAgICAgICAgIE1lc3NhZ2VUeXBlQkd0b0NTLkFERF9TVEFUSUNfVEhFTUUsXG4gICAgICAgICAgICAgICAgTWVzc2FnZVR5cGVCR3RvQ1MuQUREX1NWR19GSUxURVIsXG4gICAgICAgICAgICBdO1xuICAgICAgICAgICAgaWYgKHRoZW1lTWVzc2FnZVR5cGVzLmluY2x1ZGVzKG1lc3NhZ2UudHlwZSkpIHtcbiAgICAgICAgICAgICAgICBJY29uTWFuYWdlci5zZXRJY29uKHt0YWJJZCwgaXNBY3RpdmU6IHRydWUsIGNvbG9yU2NoZW1lOiBtZXNzYWdlLmRhdGE/LnRoZW1lPy5tb2RlID8gJ2RhcmsnIDogJ2xpZ2h0J30pO1xuICAgICAgICAgICAgfSBlbHNlIGlmIChtZXNzYWdlLnR5cGUgPT09IE1lc3NhZ2VUeXBlQkd0b0NTLkNMRUFOX1VQKSB7XG4gICAgICAgICAgICAgICAgY29uc3QgaXNBY3RpdmUgPSBUYWJNYW5hZ2VyLnRhYnNbdGFiSWRdPy5bMF0/LnVybD8uc3RhcnRzV2l0aCgnaHR0cHM6Ly9kYXJrcmVhZGVyLm9yZy8nKTtcbiAgICAgICAgICAgICAgICBJY29uTWFuYWdlci5zZXRJY29uKHt0YWJJZCwgaXNBY3RpdmV9KTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfVxuXG4gICAgICAgIGlmIChfX0NIUk9NSVVNX01WM19fKSB7XG4gICAgICAgICAgICAvLyBPbiBNVjMsIENocm9taXVtIGhhcyBhIGJ1ZyB3aGljaCBwcmV2ZW50cyBzZW5kaW5nIG1lc3NhZ2VzIHRvIHByZS1yZW5kZXJlZCBmcmFtZXMgd2l0aG91dCBzcGVjaWZ5aW5nIGZyYW1lSWRcbiAgICAgICAgICAgIC8vIEZ1cnRoZXJtb3JlLCBpZiB3ZSBzZW5kIGEgbWVzc2FnZSBhZGRyZXNzZWQgdG8gYSB0ZW1wb3JhcnkgZnJhbWVJZCBhZnRlciB0aGUgZG9jdW1lbnQgZXhpdHMgcHJlcmVuZGVyIHN0YXRlLFxuICAgICAgICAgICAgLy8gdGhlIG1lc3NhZ2Ugd2lsbCBhbHNvIGZhaWwgdG8gYmUgZGVsaXZlcmVkLlxuICAgICAgICAgICAgLy9cbiAgICAgICAgICAgIC8vIFRvIHdvcmsgYXJvdW5kIHRoaXM6XG4gICAgICAgICAgICAvLyAgMS4gQXR0ZW1wdCB0byBzZW5kIHRoZSBtZXNzYWdlIGJ5IGRvY3VtZW50SWQuIElmIHRoaXMgZmFpbHMsIHRoaXMgbWVhbnMgdGhlIGRvY3VtZW50IGlzIGluIHByZXJlbmRlciBzdGF0ZS5cbiAgICAgICAgICAgIC8vICAyLiBBdHRlbXB0IHRvIHNlbmQgdGhlIG1lc3NhZ2UgYnkgZG9jdW1lbnRJZCBhbmQgdGVtcG9yYXJ5IGZyYW1lSWQuIElmIHRoaXMgZmFpbHMsIHRoaXMgbWVhbnMgdGhlIGRvY3VtZW50XG4gICAgICAgICAgICAvLyAgICAgZWl0aGVyIGFscmVhZHkgZXhpdGVkIHByZS1yZW5kZXJlZCBzdGF0ZSBvciB3YXMgZGlzY2FyZGVkLlxuICAgICAgICAgICAgLy8gIDMuIEF0dGVtcHQgdG8gc2VuZCB0aGUgbWVzc2FnZSBieSBkb2N1bWVudElkIChvbWl0dGluZyB0aGUgcGVybWFuZW50IGZyYW1lSWQgd2hpY2ggaXMgMCkuSWYgdGhpcyBmYWlscywgdGhpc1xuICAgICAgICAgICAgLy8gICAgIG1lYW5zIHRoZSBkb2N1bWVudCB3YXMgYWxyZWFkeSBkaXNjYXJkZWQuXG4gICAgICAgICAgICAvL1xuICAgICAgICAgICAgLy8gTW9yZSBpbmZvOiBodHRwczovL2NyYnVnLmNvbS8xNDU1ODE3XG5cbiAgICAgICAgICAgIGNocm9tZS50YWJzLnNlbmRNZXNzYWdlPE1lc3NhZ2VCR3RvQ1M+KHRhYklkLCBtZXNzYWdlLCB7ZG9jdW1lbnRJZH0pLmNhdGNoKCgpID0+XG4gICAgICAgICAgICAgICAgY2hyb21lLnRhYnMuc2VuZE1lc3NhZ2U8TWVzc2FnZUJHdG9DUz4odGFiSWQsIG1lc3NhZ2UsIHtmcmFtZUlkLCBkb2N1bWVudElkfSkuY2F0Y2goKCkgPT5cbiAgICAgICAgICAgICAgICAgICAgY2hyb21lLnRhYnMuc2VuZE1lc3NhZ2U8TWVzc2FnZUJHdG9DUz4odGFiSWQsIG1lc3NhZ2UsIHtkb2N1bWVudElkfSkuY2F0Y2goKCkgPT4geyAvKiBub29wICovIH0pXG4gICAgICAgICAgICAgICAgKVxuICAgICAgICAgICAgKTtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuICAgICAgICBpZiAoX19DSFJPTUlVTV9NVjJfXykge1xuICAgICAgICAgICAgY2hyb21lLnRhYnMuc2VuZE1lc3NhZ2U8TWVzc2FnZUJHdG9DUz4odGFiSWQsIG1lc3NhZ2UsIGRvY3VtZW50SWQgPyB7ZG9jdW1lbnRJZH0gOiB7ZnJhbWVJZH0pO1xuICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICB9XG4gICAgICAgIGNocm9tZS50YWJzLnNlbmRNZXNzYWdlPE1lc3NhZ2VCR3RvQ1M+KHRhYklkLCBtZXNzYWdlLCB7ZnJhbWVJZH0pO1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIG9uQ29sb3JTY2hlbWVNZXNzYWdlKG1lc3NhZ2U6IE1lc3NhZ2VDU3RvQkcsIHNlbmRlcjogY2hyb21lLnJ1bnRpbWUuTWVzc2FnZVNlbmRlcikge1xuICAgICAgICBBU1NFUlQoJ1RhYk1hbmFnZXIub25Db2xvclNjaGVtZU1lc3NhZ2UgaXMgc2V0JywgKCkgPT4gQm9vbGVhbihUYWJNYW5hZ2VyLm9uQ29sb3JTY2hlbWVDaGFuZ2UpKTtcblxuICAgICAgICAvLyBXZSBob25vciBvbmx5IG1lc3NhZ2VzIHdoaWNoIGNvbWUgZnJvbSB0YWIncyB0b3AgZnJhbWVcbiAgICAgICAgLy8gYmVjYXVzZSBzdWItZnJhbWVzIGNvbG9yIHNjaGVtZSBjYW4gYmUgb3ZlcnJpZGRlbiBieSBzdHlsZSB3aXRoIHByZWZlcnMtY29sb3Itc2NoZW1lXG4gICAgICAgIC8vIFRPRE8oTVYzKTogaW5zdGVhZCBvZiBkcm9wcGluZyB0aGVzZSBtZXNzYWdlcywgY29uc2lkZXIgbWFraW5nIGEgcXVlcnkgdG8gYW4gYXV0aG9yaXRhdGl2ZSBzb3VyY2VcbiAgICAgICAgLy8gbGlrZSBvZmZzY3JlZW4gZG9jdW1lbnRcbiAgICAgICAgaWYgKHNlbmRlciAmJiBzZW5kZXIuZnJhbWVJZCA9PT0gMCkge1xuICAgICAgICAgICAgVGFiTWFuYWdlci5vbkNvbG9yU2NoZW1lQ2hhbmdlKG1lc3NhZ2UuZGF0YS5pc0RhcmspO1xuICAgICAgICB9XG4gICAgfVxuXG4gICAgcHJpdmF0ZSBzdGF0aWMgYWRkRnJhbWUodGFiSWQ6IG51bWJlciwgZnJhbWVJZDogbnVtYmVyLCBkb2N1bWVudElkOiBzdHJpbmcgfCBudWxsLCBzY3JpcHRJZDogc3RyaW5nLCB1cmw6IHN0cmluZywgaXNUb3A6IGJvb2xlYW4pIHtcbiAgICAgICAgbGV0IGZyYW1lczoge1tmcmFtZUlkOiBudW1iZXJdOiBEb2N1bWVudEluZm99O1xuICAgICAgICBpZiAoVGFiTWFuYWdlci50YWJzW3RhYklkXSkge1xuICAgICAgICAgICAgZnJhbWVzID0gVGFiTWFuYWdlci50YWJzW3RhYklkXTtcbiAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgIGZyYW1lcyA9IHt9O1xuICAgICAgICAgICAgVGFiTWFuYWdlci50YWJzW3RhYklkXSA9IGZyYW1lcztcbiAgICAgICAgfVxuICAgICAgICBmcmFtZXNbZnJhbWVJZF0gPSB7XG4gICAgICAgICAgICBkb2N1bWVudElkLFxuICAgICAgICAgICAgc2NyaXB0SWQsXG4gICAgICAgICAgICB1cmwsXG4gICAgICAgICAgICBpc1RvcDogaXNUb3AgfHwgdW5kZWZpbmVkLFxuICAgICAgICAgICAgc3RhdGU6IERvY3VtZW50U3RhdGUuQUNUSVZFLFxuICAgICAgICAgICAgZGFya1RoZW1lRGV0ZWN0ZWQ6IGZhbHNlLFxuICAgICAgICAgICAgdGltZXN0YW1wOiBUYWJNYW5hZ2VyLnRpbWVzdGFtcCxcbiAgICAgICAgfTtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBhc3luYyByZW1vdmVGcmFtZSh0YWJJZDogbnVtYmVyLCBmcmFtZUlkOiBudW1iZXIpIHtcbiAgICAgICAgYXdhaXQgVGFiTWFuYWdlci5zdGF0ZU1hbmFnZXIubG9hZFN0YXRlKCk7XG5cbiAgICAgICAgaWYgKGZyYW1lSWQgPT09IDApIHtcbiAgICAgICAgICAgIGRlbGV0ZSBUYWJNYW5hZ2VyLnRhYnNbdGFiSWRdO1xuICAgICAgICB9XG5cbiAgICAgICAgaWYgKFRhYk1hbmFnZXIudGFic1t0YWJJZF0gJiYgVGFiTWFuYWdlci50YWJzW3RhYklkXVtmcmFtZUlkXSkge1xuICAgICAgICAgICAgLy8gV2UgbmVlZCB0byB1c2UgZGVsZXRlIGhlcmUgYmVjYXVzZSBPYmplY3QuZW50cmllcygpXG4gICAgICAgICAgICAvLyBpbiBzZW5kTWVzc2FnZSgpIHdvdWxkIGVudW1lcmF0ZSB1bmRlZmluZWQgYXMgd2VsbC5cbiAgICAgICAgICAgIGRlbGV0ZSBUYWJNYW5hZ2VyLnRhYnNbdGFiSWRdW2ZyYW1lSWRdO1xuICAgICAgICB9XG5cbiAgICAgICAgVGFiTWFuYWdlci5zdGF0ZU1hbmFnZXIuc2F2ZVN0YXRlKCk7XG4gICAgfVxuXG4gICAgc3RhdGljIGFzeW5jIGNsZWFuU3RhdGUoKSB7XG4gICAgICAgIGF3YWl0IFRhYk1hbmFnZXIuc3RhdGVNYW5hZ2VyLmxvYWRTdGF0ZSgpO1xuXG4gICAgICAgIGNvbnN0IGFjdHVhbFRhYnMgPSBhd2FpdCBxdWVyeVRhYnMoe30pO1xuICAgICAgICBjb25zdCB0YWJJZHMgPSBPYmplY3Qua2V5cyhUYWJNYW5hZ2VyLnRhYnMpLm1hcCgoaWQpID0+IE51bWJlcihpZCkpO1xuICAgICAgICBjb25zdCBzdGFsZVRhYnMgPSBuZXcgU2V0KHRhYklkcyk7XG4gICAgICAgIGFjdHVhbFRhYnMuZm9yRWFjaCgoYWN0dWFsVGFiKSA9PiB7XG4gICAgICAgICAgICBjb25zdCB0YWJJZCA9IGFjdHVhbFRhYi5pZDtcbiAgICAgICAgICAgIGlmICh0YWJJZCkge1xuICAgICAgICAgICAgICAgIHN0YWxlVGFicy5kZWxldGUodGFiSWQpO1xuICAgICAgICAgICAgfVxuICAgICAgICB9KTtcbiAgICAgICAgc3RhbGVUYWJzLmZvckVhY2goKHN0YWxlVGFiSWQpID0+IHtcbiAgICAgICAgICAgIGlmIChUYWJNYW5hZ2VyLnRhYnNbc3RhbGVUYWJJZF0pIHtcbiAgICAgICAgICAgICAgICBkZWxldGUgVGFiTWFuYWdlci50YWJzW3N0YWxlVGFiSWRdO1xuICAgICAgICAgICAgfVxuICAgICAgICB9KTtcblxuICAgICAgICBUYWJNYW5hZ2VyLnN0YXRlTWFuYWdlci5zYXZlU3RhdGUoKTtcbiAgICB9XG5cbiAgICBzdGF0aWMgYXN5bmMgZ2V0VGFiVVJMKHRhYjogY2hyb21lLnRhYnMuVGFiIHwgbnVsbCk6IFByb21pc2U8c3RyaW5nPiB7XG4gICAgICAgIGlmIChfX0NIUk9NSVVNX01WM19fKSB7XG4gICAgICAgICAgICBpZiAoIXRhYikge1xuICAgICAgICAgICAgICAgIHJldHVybiAnYWJvdXQ6YmxhbmsnO1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgdHJ5IHtcbiAgICAgICAgICAgICAgICByZXR1cm4gKGF3YWl0IGNocm9tZS50YWJzLmdldCh0YWIuaWQhKSkudXJsIHx8ICdhYm91dDpibGFuayc7XG4gICAgICAgICAgICB9IGNhdGNoIChlKSB7XG4gICAgICAgICAgICAgICAgdHJ5IHtcbiAgICAgICAgICAgICAgICAgICAgcmV0dXJuIChhd2FpdCBjaHJvbWUuc2NyaXB0aW5nLmV4ZWN1dGVTY3JpcHQoe1xuICAgICAgICAgICAgICAgICAgICAgICAgdGFyZ2V0OiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgdGFiSWQ6IHRhYi5pZCEsXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgZnJhbWVJZHM6IFswXSxcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICB3b3JsZDogJ01BSU4nLFxuICAgICAgICAgICAgICAgICAgICAgICAgaW5qZWN0SW1tZWRpYXRlbHk6IHRydWUsXG4gICAgICAgICAgICAgICAgICAgICAgICBmdW5jOiAoKSA9PiB3aW5kb3cubG9jYXRpb24uaHJlZixcbiAgICAgICAgICAgICAgICAgICAgfSkpWzBdLnJlc3VsdCB8fCAnYWJvdXQ6YmxhbmsnO1xuICAgICAgICAgICAgICAgIH0gY2F0Y2ggKGUpIHtcbiAgICAgICAgICAgICAgICAgICAgY29uc3QgZXJyTWVzc2FnZSA9IFN0cmluZyhlKTtcbiAgICAgICAgICAgICAgICAgICAgaWYgKFxuICAgICAgICAgICAgICAgICAgICAgICAgZXJyTWVzc2FnZS5pbmNsdWRlcygnY2hyb21lOi8vJykgfHxcbiAgICAgICAgICAgICAgICAgICAgICAgIGVyck1lc3NhZ2UuaW5jbHVkZXMoJ2Nocm9tZS1leHRlbnNpb246Ly8nKSB8fFxuICAgICAgICAgICAgICAgICAgICAgICAgZXJyTWVzc2FnZS5pbmNsdWRlcygnZ2FsbGVyeScpXG4gICAgICAgICAgICAgICAgICAgICkge1xuICAgICAgICAgICAgICAgICAgICAgICAgcmV0dXJuICdjaHJvbWU6Ly9wcm90ZWN0ZWQnO1xuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgIHJldHVybiAnYWJvdXQ6YmxhbmsnO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgICAvLyBJdCBjYW4gaGFwcGVuIGluIGNhc2VzIHdoZXJlYnkgdGhlIHRhYi51cmwgaXMgZW1wdHkuXG4gICAgICAgIC8vIEx1Y2tpbHkgdGhpcyBvbmx5IGFuZCB3aWxsIG9ubHkgaGFwcGVuIG9uIGBhYm91dDpibGFua2AtbGlrZSBwYWdlcy5cbiAgICAgICAgLy8gRHVlIHRvIHRoaXMgd2UgY2FuIHNhZmVseSB1c2UgYGFib3V0OmJsYW5rYCBhcyBmYWxsYmFjayB2YWx1ZS5cbiAgICAgICAgLy8gSW4gc29tZSBleHRyYW9yZGluYXJ5IGNpcmN1bXN0YW5jZXMgdGFiIG1heSBiZSB1bmRlZmluZWQuXG4gICAgICAgIHJldHVybiB0YWIgJiYgdGFiLnVybCB8fCAnYWJvdXQ6YmxhbmsnO1xuICAgIH1cblxuICAgIHN0YXRpYyBhc3luYyB1cGRhdGVDb250ZW50U2NyaXB0KG9wdGlvbnM6IHtydW5PblByb3RlY3RlZFBhZ2VzOiBib29sZWFufSk6IFByb21pc2U8dm9pZD4ge1xuICAgICAgICAoYXdhaXQgcXVlcnlUYWJzKHtkaXNjYXJkZWQ6IGZhbHNlfSkpXG4gICAgICAgICAgICAuZmlsdGVyKCh0YWIpID0+IF9fQ0hST01JVU1fTVYzX18gfHwgb3B0aW9ucy5ydW5PblByb3RlY3RlZFBhZ2VzIHx8IGNhbkluamVjdFNjcmlwdCh0YWIudXJsKSlcbiAgICAgICAgICAgIC5maWx0ZXIoKHRhYikgPT4gIVRhYk1hbmFnZXIudGFic1t0YWIuaWQhXSlcbiAgICAgICAgICAgIC5mb3JFYWNoKCh0YWIpID0+IHtcbiAgICAgICAgICAgICAgICBpZiAoX19DSFJPTUlVTV9NVjNfXykge1xuICAgICAgICAgICAgICAgICAgICBjaHJvbWUuc2NyaXB0aW5nLmV4ZWN1dGVTY3JpcHQoe1xuICAgICAgICAgICAgICAgICAgICAgICAgdGFyZ2V0OiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgdGFiSWQ6IHRhYi5pZCEsXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgYWxsRnJhbWVzOiB0cnVlLFxuICAgICAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgICAgIGZpbGVzOiBbJy9pbmplY3QvaW5kZXguanMnXSxcbiAgICAgICAgICAgICAgICAgICAgfSwgKCkgPT4gbG9nSW5mbygnQ291bGQgbm90IHVwZGF0ZSBjb250ZW50IHNjcmlwdCBpbiB0YWInLCB0YWIsIGNocm9tZS5ydW50aW1lLmxhc3RFcnJvcikpO1xuICAgICAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgICAgIGNocm9tZS50YWJzLmV4ZWN1dGVTY3JpcHQodGFiLmlkISwge1xuICAgICAgICAgICAgICAgICAgICAgICAgcnVuQXQ6ICdkb2N1bWVudF9zdGFydCcsXG4gICAgICAgICAgICAgICAgICAgICAgICBmaWxlOiAnL2luamVjdC9pbmRleC5qcycsXG4gICAgICAgICAgICAgICAgICAgICAgICBhbGxGcmFtZXM6IHRydWUsXG4gICAgICAgICAgICAgICAgICAgICAgICBtYXRjaEFib3V0Qmxhbms6IHRydWUsXG4gICAgICAgICAgICAgICAgICAgIH0pO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0pO1xuICAgIH1cblxuICAgIHN0YXRpYyBhc3luYyByZWdpc3Rlck1haWxEaXNwbGF5U2NyaXB0KCk6IFByb21pc2U8dm9pZD4ge1xuICAgICAgICBhd2FpdCAoY2hyb21lIGFzIGFueSkubWVzc2FnZURpc3BsYXlTY3JpcHRzLnJlZ2lzdGVyKHtcbiAgICAgICAgICAgIGpzOiBbXG4gICAgICAgICAgICAgICAge2ZpbGU6ICcvaW5qZWN0L2ZhbGxiYWNrLmpzJ30sXG4gICAgICAgICAgICAgICAge2ZpbGU6ICcvaW5qZWN0L2luZGV4LmpzJ30sXG4gICAgICAgICAgICBdLFxuICAgICAgICB9KTtcbiAgICB9XG5cbiAgICAvLyBzZW5kTWVzc2FnZSB3aWxsIHNlbmQgYSB0YWIgbWVzc2FnZXMgdG8gYWxsIGFjdGl2ZSB0YWJzIGFuZCB0aGVpciBmcmFtZXMuXG4gICAgLy8gSWYgb25seVVwZGF0ZUFjdGl2ZVRhYiBpcyBzcGVjaWZpZWQsIGl0IHdpbGwgb25seSBzZW5kIGEgbmV3IG1lc3NhZ2UgdG8gYW55XG4gICAgLy8gdGFiIHRoYXQgbWF0Y2hlcyB0aGUgYWN0aXZlIHRhYidzIGhvc3RuYW1lLiBUaGlzIGlzIHRvIGVuc3VyZSB0aGF0IHdoZW4gYSB1c2VyXG4gICAgLy8gaGFzIG11bHRpcGxlIHRhYnMgb2YgdGhlIHNhbWUgd2Vic2l0ZSwgZXZlcnkgdGFiIHdpbGwgcmVjZWl2ZSB0aGUgbmV3IG1lc3NhZ2VcbiAgICAvLyBhbmQgbm90IGp1c3QgdGhhdCB0YWIgYXMgRGFyayBSZWFkZXIgY3VycmVudGx5IGRvZXNuJ3QgaGF2ZSBwZXItdGFiIG9wZXJhdGlvbnMsXG4gICAgLy8gdGhpcyBzaG91bGQgYmUgdGhlIGV4cGVjdGVkIGJlaGF2aW9yLlxuICAgIHN0YXRpYyBhc3luYyBzZW5kTWVzc2FnZShvbmx5VXBkYXRlQWN0aXZlVGFiID0gZmFsc2UpOiBQcm9taXNlPHZvaWQ+IHtcbiAgICAgICAgVGFiTWFuYWdlci50aW1lc3RhbXArKztcblxuICAgICAgICBjb25zdCBhY3RpdmVUYWJIb3N0bmFtZSA9IG9ubHlVcGRhdGVBY3RpdmVUYWIgPyBnZXRVUkxIb3N0T3JQcm90b2NvbChhd2FpdCBUYWJNYW5hZ2VyLmdldEFjdGl2ZVRhYlVSTCgpKSA6IG51bGw7XG5cbiAgICAgICAgKGF3YWl0IHF1ZXJ5VGFicyh7ZGlzY2FyZGVkOiBmYWxzZX0pKVxuICAgICAgICAgICAgLmZpbHRlcigodGFiKSA9PiBCb29sZWFuKFRhYk1hbmFnZXIudGFic1t0YWIuaWQhXSkpXG4gICAgICAgICAgICAuZm9yRWFjaCgodGFiKSA9PiB7XG4gICAgICAgICAgICAgICAgY29uc3QgZnJhbWVzID0gVGFiTWFuYWdlci50YWJzW3RhYi5pZCFdO1xuICAgICAgICAgICAgICAgIE9iamVjdC5lbnRyaWVzKGZyYW1lcylcbiAgICAgICAgICAgICAgICAgICAgLmZpbHRlcigoWywge3N0YXRlfV0pID0+IHN0YXRlID09PSBEb2N1bWVudFN0YXRlLkFDVElWRSB8fCBzdGF0ZSA9PT0gRG9jdW1lbnRTdGF0ZS5QQVNTSVZFKVxuICAgICAgICAgICAgICAgICAgICAuZm9yRWFjaChhc3luYyAoW2lkLCB7dXJsLCBkb2N1bWVudElkLCBzY3JpcHRJZCwgaXNUb3B9XSkgPT4ge1xuICAgICAgICAgICAgICAgICAgICAgICAgY29uc3QgZnJhbWVJZCA9IE51bWJlcihpZCk7XG4gICAgICAgICAgICAgICAgICAgICAgICBjb25zdCB0YWJVUkwgPSBhd2FpdCBUYWJNYW5hZ2VyLmdldFRhYlVSTCh0YWIpO1xuXG4gICAgICAgICAgICAgICAgICAgICAgICAvLyBDaGVjayBpZiBob3N0bmFtZSBhcmUgZXF1YWwgd2hlbiB3ZSBvbmx5IHdhbnQgdG8gdXBkYXRlIGFjdGl2ZSB0YWIuXG4gICAgICAgICAgICAgICAgICAgICAgICBpZiAob25seVVwZGF0ZUFjdGl2ZVRhYiAmJiBnZXRVUkxIb3N0T3JQcm90b2NvbCh0YWJVUkwpICE9PSBhY3RpdmVUYWJIb3N0bmFtZSkge1xuICAgICAgICAgICAgICAgICAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgICAgICAgICAgICAgICAgIH1cblxuICAgICAgICAgICAgICAgICAgICAgICAgY29uc3QgbWVzc2FnZSA9IFRhYk1hbmFnZXIuZ2V0VGFiTWVzc2FnZSh0YWJVUkwsIHVybCEsIGlzVG9wIHx8IGZhbHNlKTtcbiAgICAgICAgICAgICAgICAgICAgICAgIG1lc3NhZ2Uuc2NyaXB0SWQgPSBzY3JpcHRJZDtcblxuICAgICAgICAgICAgICAgICAgICAgICAgaWYgKHRhYi5hY3RpdmUgJiYgaXNUb3ApIHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBUYWJNYW5hZ2VyLnNlbmREb2N1bWVudE1lc3NhZ2UodGFiIS5pZCEsIGRvY3VtZW50SWQhLCBtZXNzYWdlLCBmcmFtZUlkKTtcbiAgICAgICAgICAgICAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgc2V0VGltZW91dCgoKSA9PiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIFRhYk1hbmFnZXIuc2VuZERvY3VtZW50TWVzc2FnZSh0YWIhLmlkISwgZG9jdW1lbnRJZCEsIG1lc3NhZ2UsIGZyYW1lSWQpO1xuICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0pO1xuICAgICAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICAgICAgaWYgKFRhYk1hbmFnZXIudGFic1t0YWIuaWQhXVtmcmFtZUlkXSkge1xuICAgICAgICAgICAgICAgICAgICAgICAgICAgIFRhYk1hbmFnZXIudGFic1t0YWIuaWQhXVtmcmFtZUlkXS50aW1lc3RhbXAgPSBUYWJNYW5hZ2VyLnRpbWVzdGFtcDtcbiAgICAgICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgfSk7XG4gICAgICAgICAgICB9KTtcbiAgICB9XG5cbiAgICBzdGF0aWMgY2FuQWNjZXNzVGFiKHRhYjogY2hyb21lLnRhYnMuVGFiIHwgbnVsbCk6IGJvb2xlYW4ge1xuICAgICAgICByZXR1cm4gdGFiICYmIEJvb2xlYW4oVGFiTWFuYWdlci50YWJzW3RhYi5pZCFdKSB8fCBmYWxzZTtcbiAgICB9XG5cbiAgICBzdGF0aWMgZ2V0VGFiRG9jdW1lbnRJZCh0YWI6IGNocm9tZS50YWJzLlRhYiB8IG51bGwpOiBzdHJpbmcgfCBudWxsIHtcbiAgICAgICAgcmV0dXJuIHRhYiAmJiBUYWJNYW5hZ2VyLnRhYnNbdGFiLmlkIV0gJiYgVGFiTWFuYWdlci50YWJzW3RhYi5pZCFdWzBdICYmIFRhYk1hbmFnZXIudGFic1t0YWIuaWQhXVswXS5kb2N1bWVudElkO1xuICAgIH1cblxuICAgIHN0YXRpYyBpc1RhYkRhcmtUaGVtZURldGVjdGVkKHRhYjogY2hyb21lLnRhYnMuVGFiIHwgbnVsbCk6IGJvb2xlYW4gfCBudWxsIHtcbiAgICAgICAgcmV0dXJuIHRhYiAmJiBUYWJNYW5hZ2VyLnRhYnNbdGFiLmlkIV0gJiYgVGFiTWFuYWdlci50YWJzW3RhYi5pZCFdWzBdICYmIFRhYk1hbmFnZXIudGFic1t0YWIuaWQhXVswXS5kYXJrVGhlbWVEZXRlY3RlZCB8fCBudWxsO1xuICAgIH1cblxuICAgIHN0YXRpYyBhc3luYyBnZXRBY3RpdmVUYWJVUkwoKTogUHJvbWlzZTxzdHJpbmc+IHtcbiAgICAgICAgcmV0dXJuIFRhYk1hbmFnZXIuZ2V0VGFiVVJMKGF3YWl0IGdldEFjdGl2ZVRhYigpKTtcbiAgICB9XG59XG4iLCJpbXBvcnQge3JlYWRMb2NhbFN0b3JhZ2UsIHdyaXRlTG9jYWxTdG9yYWdlfSBmcm9tICcuL3V0aWxzL2V4dGVuc2lvbi1hcGknO1xuXG5jb25zdCBwcm9wb3NlZEhpZ2hsaWdodHM6IHN0cmluZ1tdID0gW1xuICAgICdhbm5pdmVyc2FyeScsXG5dO1xuXG5jb25zdCBLRVlfVUlfSElEREVOX0hJR0hMSUdIVFMgPSAndWktaGlkZGVuLWhpZ2hsaWdodHMnO1xuXG5hc3luYyBmdW5jdGlvbiBnZXRIaWRkZW5IaWdobGlnaHRzKCkge1xuICAgIGNvbnN0IG9wdGlvbnMgPSBhd2FpdCByZWFkTG9jYWxTdG9yYWdlKHtbS0VZX1VJX0hJRERFTl9ISUdITElHSFRTXTogW10gYXMgc3RyaW5nW119KTtcbiAgICByZXR1cm4gb3B0aW9uc1tLRVlfVUlfSElEREVOX0hJR0hMSUdIVFNdO1xufVxuXG5hc3luYyBmdW5jdGlvbiBnZXRIaWdobGlnaHRzVG9TaG93KCk6IFByb21pc2U8c3RyaW5nW10+IHtcbiAgICBjb25zdCBoaWRkZW5IaWdobGlnaHRzID0gYXdhaXQgZ2V0SGlkZGVuSGlnaGxpZ2h0cygpO1xuICAgIHJldHVybiBwcm9wb3NlZEhpZ2hsaWdodHMuZmlsdGVyKChoKSA9PiAhaGlkZGVuSGlnaGxpZ2h0cy5pbmNsdWRlcyhoKSk7XG59XG5cbmFzeW5jIGZ1bmN0aW9uIGhpZGVIaWdobGlnaHRzKGtleXM6IHN0cmluZ1tdKTogUHJvbWlzZTx2b2lkPiB7XG4gICAgY29uc3QgaGlkZGVuSGlnaGxpZ2h0cyA9IGF3YWl0IGdldEhpZGRlbkhpZ2hsaWdodHMoKTtcbiAgICBjb25zdCB1cGRhdGUgPSBBcnJheS5mcm9tKG5ldyBTZXQoWy4uLmhpZGRlbkhpZ2hsaWdodHMsIC4uLmtleXNdKSk7XG4gICAgYXdhaXQgd3JpdGVMb2NhbFN0b3JhZ2Uoe1tLRVlfVUlfSElEREVOX0hJR0hMSUdIVFNdOiB1cGRhdGV9KTtcbn1cblxuYXN5bmMgZnVuY3Rpb24gcmVzdG9yZUhpZ2hsaWdodHMoa2V5czogc3RyaW5nW10pOiBQcm9taXNlPHZvaWQ+IHtcbiAgICBjb25zdCBoaWRkZW5IaWdobGlnaHRzID0gYXdhaXQgZ2V0SGlkZGVuSGlnaGxpZ2h0cygpO1xuICAgIGNvbnN0IHVwZGF0ZSA9IEFycmF5LmZyb20obmV3IFNldChbLi4uaGlkZGVuSGlnaGxpZ2h0cy5maWx0ZXIoKGgpID0+ICFrZXlzLmluY2x1ZGVzKGgpKV0pKTtcbiAgICBhd2FpdCB3cml0ZUxvY2FsU3RvcmFnZSh7W0tFWV9VSV9ISURERU5fSElHSExJR0hUU106IHVwZGF0ZX0pO1xufVxuXG5leHBvcnQgZGVmYXVsdCB7XG4gICAgZ2V0SGlnaGxpZ2h0c1RvU2hvdyxcbiAgICBoaWRlSGlnaGxpZ2h0cyxcbiAgICByZXN0b3JlSGlnaGxpZ2h0cyxcbn07XG4iLCIvLyBldmFsTWF0aCBpcyBhIGZ1bmN0aW9uIHRoYXQncyBhYmxlIHRvIGV2YWx1YXRlcyBhIG1hdGhlbWF0aWNhbCBleHByZXNzaW9uIGFuZCByZXR1cm4gaXQncyBvdXRwdXQuXG4vL1xuLy8gSW50ZXJuYWxseSBpdCB1c2VzIHRoZSBTaHVudGluZyBZYXJkIGFsZ29yaXRobS4gRmlyc3QgaXQgcHJvZHVjZXMgYSByZXZlcnNlIHBvbGlzaCBub3RhdGlvbihSUE4pIHN0YWNrLlxuLy8gRXhhbXBsZTogMSArIDIgKiAzIC0+IFsxLCAyLCAzLCAqLCArXSB3aGljaCB3aXRoIHBhcmVudGhlc2VzIG1lYW5zIDEgKDIgMyAqKSArXG4vL1xuLy8gVGhlbiBpdCBldmFsdWF0ZXMgdGhlIFJQTiBzdGFjayBhbmQgcmV0dXJucyB0aGUgb3V0cHV0LlxuZXhwb3J0IGZ1bmN0aW9uIGV2YWxNYXRoKGV4cHJlc3Npb246IHN0cmluZyk6IG51bWJlciB7XG4gICAgLy8gU3RhY2sgd2hlcmUgb3BlcmF0b3JzICYgbnVtYmVycyBhcmUgc3RvcmVkIGluIFJQTi5cbiAgICBjb25zdCBycG5TdGFjazogc3RyaW5nW10gPSBbXTtcbiAgICAvLyBUaGUgd29ya2luZyBzdGFjayB3aGVyZSBuZXcgdG9rZW5zIGFyZSBwdXNoZWQuXG4gICAgY29uc3Qgd29ya2luZ1N0YWNrOiBzdHJpbmdbXSA9IFtdO1xuXG4gICAgbGV0IGxhc3RUb2tlbjogc3RyaW5nIHwgdW5kZWZpbmVkO1xuICAgIC8vIEl0ZXJhdGUgb3ZlciB0aGUgZXhwcmVzc2lvbi5cbiAgICBmb3IgKGxldCBpID0gMCwgbGVuID0gZXhwcmVzc2lvbi5sZW5ndGg7IGkgPCBsZW47IGkrKykge1xuICAgICAgICBjb25zdCB0b2tlbiA9IGV4cHJlc3Npb25baV07XG5cbiAgICAgICAgLy8gU2tpcCBpZiB0aGUgdG9rZW4gaXMgZW1wdHkgb3IgYSB3aGl0ZXNwYWNlLlxuICAgICAgICBpZiAoIXRva2VuIHx8IHRva2VuID09PSAnICcpIHtcbiAgICAgICAgICAgIGNvbnRpbnVlO1xuICAgICAgICB9XG5cbiAgICAgICAgLy8gSXMgdGhlIHRva2VuIGEgb3BlcmF0b3I/XG4gICAgICAgIGlmIChvcGVyYXRvcnMuaGFzKHRva2VuKSkge1xuICAgICAgICAgICAgY29uc3Qgb3AgPSBvcGVyYXRvcnMuZ2V0KHRva2VuKTtcblxuICAgICAgICAgICAgLy8gR28gdHJvdWdoIHRoZSB3b3JraW5nc3RhY2sgYW5kIGRldGVybWluZSBpdCdzIHBsYWNlIGluIHRoZSB3b3JraW5nU3RhY2tcbiAgICAgICAgICAgIHdoaWxlICh3b3JraW5nU3RhY2subGVuZ3RoKSB7XG4gICAgICAgICAgICAgICAgY29uc3QgY3VycmVudE9wID0gb3BlcmF0b3JzLmdldCh3b3JraW5nU3RhY2tbMF0pO1xuICAgICAgICAgICAgICAgIGlmICghY3VycmVudE9wKSB7XG4gICAgICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgICAgIH1cblxuICAgICAgICAgICAgICAgIC8vIElzIHRoZSBjdXJyZW50IG9wZXJhdGlvbiBlcXVhbCBvciBsZXNzIHRoYW4gdGhlIGN1cnJlbnQgb3BlcmF0aW9uP1xuICAgICAgICAgICAgICAgIC8vIFRoZW4gbW92ZSB0aGF0IG9wZXJhdGlvbiB0byB0aGUgcnBuU3RhY2suXG4gICAgICAgICAgICAgICAgaWYgKG9wIS5sZXNzT3JFcXVhbFRoYW4oY3VycmVudE9wKSkge1xuICAgICAgICAgICAgICAgICAgICBycG5TdGFjay5wdXNoKHdvcmtpbmdTdGFjay5zaGlmdCgpISk7XG4gICAgICAgICAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfVxuICAgICAgICAgICAgLy8gQWRkIHRoZSBvcGVyYXRpb24gdG8gdGhlIHdvcmtpbmdTdGFjay5cbiAgICAgICAgICAgIHdvcmtpbmdTdGFjay51bnNoaWZ0KHRva2VuKTtcbiAgICAgICAgLy8gT3RoZXJ3aXNlIHdhcyB0aGUgbGFzdCB0b2tlbiBhIG9wZXJhdG9yP1xuICAgICAgICB9IGVsc2UgaWYgKCFsYXN0VG9rZW4gfHwgb3BlcmF0b3JzLmhhcyhsYXN0VG9rZW4pKSB7XG4gICAgICAgICAgICBycG5TdGFjay5wdXNoKHRva2VuKTtcbiAgICAgICAgLy8gT3RoZXJ3aXNlIGp1c3QgYXBwZW5kIHRoZSByZXN1bHQgdG8gdGhlIGxhc3QgdG9rZW4oZS5nLiBtdWx0aXBsZSBkaWdpdHMgbnVtYmVycykuXG4gICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICBycG5TdGFja1tycG5TdGFjay5sZW5ndGggLSAxXSArPSB0b2tlbjtcbiAgICAgICAgfVxuICAgICAgICAvLyBTZXQgdGhlIGxhc3QgdG9rZW4uXG4gICAgICAgIGxhc3RUb2tlbiA9IHRva2VuO1xuICAgIH1cblxuICAgIC8vIFB1c2ggdGhlIHdvcmtpbmcgc3RhY2sgb24gdG9wIG9mIHRoZSBycG5TdGFjay5cbiAgICBycG5TdGFjay5wdXNoKC4uLndvcmtpbmdTdGFjayk7XG5cbiAgICAvLyBOb3cgZXZhbHVhdGUgdGhlIHJwblN0YWNrLlxuICAgIGNvbnN0IHN0YWNrOiBudW1iZXJbXSA9IFtdO1xuICAgIGZvciAobGV0IGkgPSAwLCBsZW4gPSBycG5TdGFjay5sZW5ndGg7IGkgPCBsZW47IGkrKykge1xuICAgICAgICBjb25zdCBvcCA9IG9wZXJhdG9ycy5nZXQocnBuU3RhY2tbaV0pO1xuICAgICAgICBpZiAob3ApIHtcbiAgICAgICAgICAgIC8vIEdldCB0aGUgYXJndW1lbnRzIG9mIGZvciB0aGUgb3BlcmF0aW9uKGZpcnN0IHR3byBpbiB0aGUgc3RhY2spLlxuICAgICAgICAgICAgY29uc3QgYXJncyA9IHN0YWNrLnNwbGljZSgwLCAyKTtcbiAgICAgICAgICAgIC8vIEV4Y3V0ZSBpdCwgYmVjYXVzZSBvZiByZXZlcnNlIG5vdGF0aW9uIHdlIGZpcnN0IHBhc3Mgc2Vjb25kIGl0ZW0gdGhlbiB0aGUgZmlyc3QgaXRlbS5cbiAgICAgICAgICAgIHN0YWNrLnB1c2gob3AuZXhlYyhhcmdzWzFdLCBhcmdzWzBdKSk7XG4gICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAvLyBBZGQgdGhlIG51bWJlciB0byB0aGUgc3RhY2suXG4gICAgICAgICAgICBzdGFjay51bnNoaWZ0KHBhcnNlRmxvYXQocnBuU3RhY2tbaV0pKTtcbiAgICAgICAgfVxuICAgIH1cblxuICAgIHJldHVybiBzdGFja1swXTtcbn1cblxuLy8gT3BlcmF0b3IgY2xhc3MgIGRlZmluZXMgYSBvcGVyYXRvciB0aGF0IGNhbiBiZSBwYXJzZWQgJiBldmFsdWF0ZWQgYnkgZXZhbE1hdGguXG5jbGFzcyBPcGVyYXRvciB7XG4gICAgcHJpdmF0ZSBwcmVjZW5kY2U6IG51bWJlcjtcbiAgICBwcml2YXRlIGV4ZWNNZXRob2Q6IChsZWZ0OiBudW1iZXIsIHJpZ2h0OiBudW1iZXIpID0+IG51bWJlcjtcblxuICAgIGNvbnN0cnVjdG9yKHByZWNlZGVuY2U6IG51bWJlciwgbWV0aG9kOiAobGVmdDogbnVtYmVyLCByaWdodDogbnVtYmVyKSA9PiBudW1iZXIpIHtcbiAgICAgICAgdGhpcy5wcmVjZW5kY2UgPSBwcmVjZWRlbmNlO1xuICAgICAgICB0aGlzLmV4ZWNNZXRob2QgPSBtZXRob2Q7XG4gICAgfVxuXG4gICAgZXhlYyhsZWZ0OiBudW1iZXIsIHJpZ2h0OiBudW1iZXIpOiBudW1iZXIge1xuICAgICAgICByZXR1cm4gdGhpcy5leGVjTWV0aG9kKGxlZnQsIHJpZ2h0KTtcbiAgICB9XG5cbiAgICBsZXNzT3JFcXVhbFRoYW4ob3A6IE9wZXJhdG9yKSB7XG4gICAgICAgIHJldHVybiB0aGlzLnByZWNlbmRjZSA8PSBvcC5wcmVjZW5kY2U7XG4gICAgfVxufVxuXG5jb25zdCBvcGVyYXRvcnM6IFJlYWRvbmx5PE1hcDxzdHJpbmcsIE9wZXJhdG9yPj4gPSBuZXcgTWFwKFtcbiAgICBbJysnLCBuZXcgT3BlcmF0b3IoMSwgKGxlZnQ6IG51bWJlciwgcmlnaHQ6IG51bWJlcik6IG51bWJlciA9PiBsZWZ0ICsgcmlnaHQpXSxcbiAgICBbJy0nLCBuZXcgT3BlcmF0b3IoMSwgKGxlZnQ6IG51bWJlciwgcmlnaHQ6IG51bWJlcik6IG51bWJlciA9PiBsZWZ0IC0gcmlnaHQpXSxcbiAgICBbJyonLCBuZXcgT3BlcmF0b3IoMiwgKGxlZnQ6IG51bWJlciwgcmlnaHQ6IG51bWJlcik6IG51bWJlciA9PiBsZWZ0ICogcmlnaHQpXSxcbiAgICBbJy8nLCBuZXcgT3BlcmF0b3IoMiwgKGxlZnQ6IG51bWJlciwgcmlnaHQ6IG51bWJlcik6IG51bWJlciA9PiBsZWZ0IC8gcmlnaHQpXSxcbl0pO1xuIiwiaW1wb3J0IHtldmFsTWF0aH0gZnJvbSAnLi9tYXRoLWV2YWwnO1xuaW1wb3J0IHtpc1N5c3RlbURhcmtNb2RlRW5hYmxlZH0gZnJvbSAnLi9tZWRpYS1xdWVyeSc7XG5pbXBvcnQge2dldFBhcmVudGhlc2VzUmFuZ2V9IGZyb20gJy4vdGV4dCc7XG5cbmV4cG9ydCBpbnRlcmZhY2UgUkdCQSB7XG4gICAgcjogbnVtYmVyO1xuICAgIGc6IG51bWJlcjtcbiAgICBiOiBudW1iZXI7XG4gICAgYT86IG51bWJlcjtcbn1cblxuZXhwb3J0IGludGVyZmFjZSBIU0xBIHtcbiAgICBoOiBudW1iZXI7XG4gICAgczogbnVtYmVyO1xuICAgIGw6IG51bWJlcjtcbiAgICBhPzogbnVtYmVyO1xufVxuXG5jb25zdCBoc2xhUGFyc2VDYWNoZSA9IG5ldyBNYXA8c3RyaW5nLCBIU0xBPigpO1xuY29uc3QgcmdiYVBhcnNlQ2FjaGUgPSBuZXcgTWFwPHN0cmluZywgUkdCQT4oKTtcblxuZXhwb3J0IGZ1bmN0aW9uIHBhcnNlQ29sb3JXaXRoQ2FjaGUoJGNvbG9yOiBzdHJpbmcpOiBSR0JBIHwgbnVsbCB7XG4gICAgJGNvbG9yID0gJGNvbG9yLnRyaW0oKTtcbiAgICBpZiAocmdiYVBhcnNlQ2FjaGUuaGFzKCRjb2xvcikpIHtcbiAgICAgICAgcmV0dXJuIHJnYmFQYXJzZUNhY2hlLmdldCgkY29sb3IpITtcbiAgICB9XG4gICAgLy8gV2UgY2Fubm90IF9yZWFsbHlfIHBhcnNlIGFueSBjb2xvciB3aGljaCBoYXMgdGhlIGNhbGMoKSBleHByZXNzaW9uLFxuICAgIC8vIHNvIHdlIHRyeSBvdXIgYmVzdCB0byByZW1vdmUgdGhvc2UgYW5kIHRoZW4gcGFyc2UgdGhlIHZhbHVlLlxuICAgIGlmICgkY29sb3IuaW5jbHVkZXMoJ2NhbGMoJykpIHtcbiAgICAgICAgJGNvbG9yID0gbG93ZXJDYWxjRXhwcmVzc2lvbigkY29sb3IpO1xuICAgIH1cbiAgICBjb25zdCBjb2xvciA9IHBhcnNlKCRjb2xvcik7XG4gICAgaWYgKGNvbG9yKSB7XG4gICAgICAgIHJnYmFQYXJzZUNhY2hlLnNldCgkY29sb3IsIGNvbG9yKTtcbiAgICAgICAgcmV0dXJuIGNvbG9yO1xuICAgIH1cbiAgICByZXR1cm4gbnVsbDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIHBhcnNlVG9IU0xXaXRoQ2FjaGUoY29sb3I6IHN0cmluZyk6IEhTTEEgfCBudWxsIHtcbiAgICBpZiAoaHNsYVBhcnNlQ2FjaGUuaGFzKGNvbG9yKSkge1xuICAgICAgICByZXR1cm4gaHNsYVBhcnNlQ2FjaGUuZ2V0KGNvbG9yKSE7XG4gICAgfVxuICAgIGNvbnN0IHJnYiA9IHBhcnNlQ29sb3JXaXRoQ2FjaGUoY29sb3IpO1xuICAgIGlmICghcmdiKSB7XG4gICAgICAgIHJldHVybiBudWxsO1xuICAgIH1cbiAgICBjb25zdCBoc2wgPSByZ2JUb0hTTChyZ2IpO1xuICAgIGhzbGFQYXJzZUNhY2hlLnNldChjb2xvciwgaHNsKTtcbiAgICByZXR1cm4gaHNsO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY2xlYXJDb2xvckNhY2hlKCk6IHZvaWQge1xuICAgIGhzbGFQYXJzZUNhY2hlLmNsZWFyKCk7XG4gICAgcmdiYVBhcnNlQ2FjaGUuY2xlYXIoKTtcbn1cblxuLy8gaHR0cHM6Ly9lbi53aWtpcGVkaWEub3JnL3dpa2kvSFNMX2FuZF9IU1ZcbmV4cG9ydCBmdW5jdGlvbiBoc2xUb1JHQih7aCwgcywgbCwgYSA9IDF9OiBIU0xBKTogUkdCQSB7XG4gICAgaWYgKHMgPT09IDApIHtcbiAgICAgICAgY29uc3QgW3IsIGIsIGddID0gW2wsIGwsIGxdLm1hcCgoeCkgPT4gTWF0aC5yb3VuZCh4ICogMjU1KSk7XG4gICAgICAgIHJldHVybiB7ciwgZywgYiwgYX07XG4gICAgfVxuXG4gICAgY29uc3QgYyA9ICgxIC0gTWF0aC5hYnMoMiAqIGwgLSAxKSkgKiBzO1xuICAgIGNvbnN0IHggPSBjICogKDEgLSBNYXRoLmFicygoaCAvIDYwKSAlIDIgLSAxKSk7XG4gICAgY29uc3QgbSA9IGwgLSBjIC8gMjtcbiAgICBjb25zdCBbciwgZywgYl0gPSAoXG4gICAgICAgIGggPCA2MCA/IFtjLCB4LCAwXSA6XG4gICAgICAgICAgICBoIDwgMTIwID8gW3gsIGMsIDBdIDpcbiAgICAgICAgICAgICAgICBoIDwgMTgwID8gWzAsIGMsIHhdIDpcbiAgICAgICAgICAgICAgICAgICAgaCA8IDI0MCA/IFswLCB4LCBjXSA6XG4gICAgICAgICAgICAgICAgICAgICAgICBoIDwgMzAwID8gW3gsIDAsIGNdIDpcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBbYywgMCwgeF1cbiAgICApLm1hcCgobikgPT4gTWF0aC5yb3VuZCgobiArIG0pICogMjU1KSk7XG5cbiAgICByZXR1cm4ge3IsIGcsIGIsIGF9O1xufVxuXG4vLyBodHRwczovL2VuLndpa2lwZWRpYS5vcmcvd2lraS9IU0xfYW5kX0hTVlxuZXhwb3J0IGZ1bmN0aW9uIHJnYlRvSFNMKHtyOiByMjU1LCBnOiBnMjU1LCBiOiBiMjU1LCBhID0gMX06IFJHQkEpOiBIU0xBIHtcbiAgICBjb25zdCByID0gcjI1NSAvIDI1NTtcbiAgICBjb25zdCBnID0gZzI1NSAvIDI1NTtcbiAgICBjb25zdCBiID0gYjI1NSAvIDI1NTtcblxuICAgIGNvbnN0IG1heCA9IE1hdGgubWF4KHIsIGcsIGIpO1xuICAgIGNvbnN0IG1pbiA9IE1hdGgubWluKHIsIGcsIGIpO1xuICAgIGNvbnN0IGMgPSBtYXggLSBtaW47XG5cbiAgICBjb25zdCBsID0gKG1heCArIG1pbikgLyAyO1xuXG4gICAgaWYgKGMgPT09IDApIHtcbiAgICAgICAgcmV0dXJuIHtoOiAwLCBzOiAwLCBsLCBhfTtcbiAgICB9XG5cbiAgICBsZXQgaCA9IChcbiAgICAgICAgbWF4ID09PSByID8gKCgoZyAtIGIpIC8gYykgJSA2KSA6XG4gICAgICAgICAgICBtYXggPT09IGcgPyAoKGIgLSByKSAvIGMgKyAyKSA6XG4gICAgICAgICAgICAgICAgKChyIC0gZykgLyBjICsgNClcbiAgICApICogNjA7XG4gICAgaWYgKGggPCAwKSB7XG4gICAgICAgIGggKz0gMzYwO1xuICAgIH1cblxuICAgIGNvbnN0IHMgPSBjIC8gKDEgLSBNYXRoLmFicygyICogbCAtIDEpKTtcblxuICAgIHJldHVybiB7aCwgcywgbCwgYX07XG59XG5cbmZ1bmN0aW9uIHRvRml4ZWQobjogbnVtYmVyLCBkaWdpdHMgPSAwKTogc3RyaW5nIHtcbiAgICBjb25zdCBmaXhlZCA9IG4udG9GaXhlZChkaWdpdHMpO1xuICAgIGlmIChkaWdpdHMgPT09IDApIHtcbiAgICAgICAgcmV0dXJuIGZpeGVkO1xuICAgIH1cbiAgICBjb25zdCBkb3QgPSBmaXhlZC5pbmRleE9mKCcuJyk7XG4gICAgaWYgKGRvdCA+PSAwKSB7XG4gICAgICAgIGNvbnN0IHplcm9zTWF0Y2ggPSBmaXhlZC5tYXRjaCgvMCskLyk7XG4gICAgICAgIGlmICh6ZXJvc01hdGNoKSB7XG4gICAgICAgICAgICBpZiAoemVyb3NNYXRjaC5pbmRleCA9PT0gZG90ICsgMSkge1xuICAgICAgICAgICAgICAgIHJldHVybiBmaXhlZC5zdWJzdHJpbmcoMCwgZG90KTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIHJldHVybiBmaXhlZC5zdWJzdHJpbmcoMCwgemVyb3NNYXRjaC5pbmRleCk7XG4gICAgICAgIH1cbiAgICB9XG4gICAgcmV0dXJuIGZpeGVkO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gcmdiVG9TdHJpbmcocmdiOiBSR0JBKTogc3RyaW5nIHtcbiAgICBjb25zdCB7ciwgZywgYiwgYX0gPSByZ2I7XG4gICAgaWYgKGEgIT0gbnVsbCAmJiBhIDwgMSkge1xuICAgICAgICByZXR1cm4gYHJnYmEoJHt0b0ZpeGVkKHIpfSwgJHt0b0ZpeGVkKGcpfSwgJHt0b0ZpeGVkKGIpfSwgJHt0b0ZpeGVkKGEsIDIpfSlgO1xuICAgIH1cbiAgICByZXR1cm4gYHJnYigke3RvRml4ZWQocil9LCAke3RvRml4ZWQoZyl9LCAke3RvRml4ZWQoYil9KWA7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiByZ2JUb0hleFN0cmluZyh7ciwgZywgYiwgYX06IFJHQkEpOiBzdHJpbmcge1xuICAgIHJldHVybiBgIyR7KGEgIT0gbnVsbCAmJiBhIDwgMSA/IFtyLCBnLCBiLCBNYXRoLnJvdW5kKGEgKiAyNTUpXSA6IFtyLCBnLCBiXSkubWFwKCh4KSA9PiB7XG4gICAgICAgIHJldHVybiBgJHt4IDwgMTYgPyAnMCcgOiAnJ30ke3gudG9TdHJpbmcoMTYpfWA7XG4gICAgfSkuam9pbignJyl9YDtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGhzbFRvU3RyaW5nKGhzbDogSFNMQSk6IHN0cmluZyB7XG4gICAgY29uc3Qge2gsIHMsIGwsIGF9ID0gaHNsO1xuICAgIGlmIChhICE9IG51bGwgJiYgYSA8IDEpIHtcbiAgICAgICAgcmV0dXJuIGBoc2xhKCR7dG9GaXhlZChoKX0sICR7dG9GaXhlZChzICogMTAwKX0lLCAke3RvRml4ZWQobCAqIDEwMCl9JSwgJHt0b0ZpeGVkKGEsIDIpfSlgO1xuICAgIH1cbiAgICByZXR1cm4gYGhzbCgke3RvRml4ZWQoaCl9LCAke3RvRml4ZWQocyAqIDEwMCl9JSwgJHt0b0ZpeGVkKGwgKiAxMDApfSUpYDtcbn1cblxuY29uc3QgcmdiTWF0Y2ggPSAvXnJnYmE/XFwoW15cXChcXCldK1xcKSQvO1xuY29uc3QgaHNsTWF0Y2ggPSAvXmhzbGE/XFwoW15cXChcXCldK1xcKSQvO1xuY29uc3QgaGV4TWF0Y2ggPSAvXiNbMC05YS1mXSskL2k7XG5cbmNvbnN0IHN1cHBvcnRlZENvbG9yRnVuY3MgPSBbXG4gICAgJ2NvbG9yJyxcbiAgICAnY29sb3ItbWl4JyxcbiAgICAnaHdiJyxcbiAgICAnbGFiJyxcbiAgICAnbGNoJyxcbiAgICAnb2tsYWInLFxuICAgICdva2xjaCcsXG5dO1xuXG5leHBvcnQgZnVuY3Rpb24gcGFyc2UoJGNvbG9yOiBzdHJpbmcpOiBSR0JBIHwgbnVsbCB7XG4gICAgY29uc3QgYyA9ICRjb2xvci50cmltKCkudG9Mb3dlckNhc2UoKTtcbiAgICBpZiAoYy5pbmNsdWRlcygnKGZyb20gJykpIHtcbiAgICAgICAgaWYgKGMuaW5kZXhPZignKGZyb20nKSAhPT0gYy5sYXN0SW5kZXhPZignKGZyb20nKSkge1xuICAgICAgICAgICAgcmV0dXJuIG51bGw7XG4gICAgICAgIH1cbiAgICAgICAgcmV0dXJuIGRvbVBhcnNlQ29sb3IoYyk7XG4gICAgfVxuXG4gICAgaWYgKGMubWF0Y2gocmdiTWF0Y2gpKSB7XG4gICAgICAgIGlmIChjLnN0YXJ0c1dpdGgoJ3JnYigjJykgfHwgYy5zdGFydHNXaXRoKCdyZ2JhKCMnKSkge1xuICAgICAgICAgICAgaWYgKGMubGFzdEluZGV4T2YoJ3JnYicpID4gMCkge1xuICAgICAgICAgICAgICAgIHJldHVybiBudWxsO1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgcmV0dXJuIGRvbVBhcnNlQ29sb3IoYyk7XG4gICAgICAgIH1cbiAgICAgICAgcmV0dXJuIHBhcnNlUkdCKGMpO1xuICAgIH1cblxuICAgIGlmIChjLm1hdGNoKGhzbE1hdGNoKSkge1xuICAgICAgICByZXR1cm4gcGFyc2VIU0woYyk7XG4gICAgfVxuXG4gICAgaWYgKGMubWF0Y2goaGV4TWF0Y2gpKSB7XG4gICAgICAgIHJldHVybiBwYXJzZUhleChjKTtcbiAgICB9XG5cbiAgICBpZiAoa25vd25Db2xvcnMuaGFzKGMpKSB7XG4gICAgICAgIHJldHVybiBnZXRDb2xvckJ5TmFtZShjKTtcbiAgICB9XG5cbiAgICBpZiAoc3lzdGVtQ29sb3JzLmhhcyhjKSkge1xuICAgICAgICByZXR1cm4gZ2V0U3lzdGVtQ29sb3IoYyk7XG4gICAgfVxuXG4gICAgaWYgKGMgPT09ICd0cmFuc3BhcmVudCcpIHtcbiAgICAgICAgcmV0dXJuIHtyOiAwLCBnOiAwLCBiOiAwLCBhOiAwfTtcbiAgICB9XG5cbiAgICBpZiAoXG4gICAgICAgIGMuZW5kc1dpdGgoJyknKSAmJlxuICAgICAgICBzdXBwb3J0ZWRDb2xvckZ1bmNzLnNvbWUoXG4gICAgICAgICAgICAoZm4pID0+IGMuc3RhcnRzV2l0aChmbikgJiYgY1tmbi5sZW5ndGhdID09PSAnKCcgJiYgYy5sYXN0SW5kZXhPZihmbikgPT09IDBcbiAgICAgICAgKVxuICAgICkge1xuICAgICAgICByZXR1cm4gZG9tUGFyc2VDb2xvcihjKTtcbiAgICB9XG5cbiAgICBpZiAoYy5zdGFydHNXaXRoKCdsaWdodC1kYXJrKCcpICYmIGMuZW5kc1dpdGgoJyknKSkge1xuICAgICAgICAvLyBsaWdodC1kYXJrKFtjb2xvcigpXSwgW2NvbG9yKCldKVxuICAgICAgICBjb25zdCBtYXRjaCA9IGMubWF0Y2goL15saWdodC1kYXJrXFwoXFxzKihbYS16XSsoXFwoLipcXCkpPyksXFxzKihbYS16XSsoXFwoLipcXCkpPylcXHMqXFwpJC8pO1xuICAgICAgICBpZiAobWF0Y2gpIHtcbiAgICAgICAgICAgIGNvbnN0IHNjaGVtZUNvbG9yID0gaXNTeXN0ZW1EYXJrTW9kZUVuYWJsZWQoKSA/IG1hdGNoWzNdIDogbWF0Y2hbMV07XG4gICAgICAgICAgICByZXR1cm4gcGFyc2Uoc2NoZW1lQ29sb3IpO1xuICAgICAgICB9XG4gICAgfVxuXG4gICAgcmV0dXJuIG51bGw7XG59XG5cbmNvbnN0IENfMCA9ICcwJy5jaGFyQ29kZUF0KDApO1xuY29uc3QgQ185ID0gJzknLmNoYXJDb2RlQXQoMCk7XG5jb25zdCBDX2UgPSAnZScuY2hhckNvZGVBdCgwKTtcbmNvbnN0IENfRE9UID0gJy4nLmNoYXJDb2RlQXQoMCk7XG5jb25zdCBDX1BMVVMgPSAnKycuY2hhckNvZGVBdCgwKTtcbmNvbnN0IENfTUlOVVMgPSAnLScuY2hhckNvZGVBdCgwKTtcbmNvbnN0IENfU1BBQ0UgPSAnICcuY2hhckNvZGVBdCgwKTtcbmNvbnN0IENfQ09NTUEgPSAnLCcuY2hhckNvZGVBdCgwKTtcbmNvbnN0IENfU0xBU0ggPSAnLycuY2hhckNvZGVBdCgwKTtcbmNvbnN0IENfUEVSQ0VOVCA9ICclJy5jaGFyQ29kZUF0KDApO1xuXG5mdW5jdGlvbiBnZXROdW1iZXJzRnJvbVN0cmluZyhpbnB1dDogc3RyaW5nLCByYW5nZTogbnVtYmVyW10sIHVuaXRzOiB7W3VuaXQ6IHN0cmluZ106IG51bWJlcn0pIHtcbiAgICBjb25zdCBudW1iZXJzOiBudW1iZXJbXSA9IFtdO1xuICAgIGNvbnN0IHNlYXJjaFN0YXJ0ID0gaW5wdXQuaW5kZXhPZignKCcpICsgMTtcbiAgICBjb25zdCBzZWFyY2hFbmQgPSBpbnB1dC5sZW5ndGggLSAxO1xuICAgIGxldCBudW1TdGFydCA9IC0xO1xuICAgIGxldCB1bml0U3RhcnQgPSAtMTtcblxuICAgIGNvbnN0IHB1c2ggPSAobWF0Y2hFbmQ6IG51bWJlcikgPT4ge1xuICAgICAgICBjb25zdCBudW1FbmQgPSB1bml0U3RhcnQgPiAtMSA/IHVuaXRTdGFydCA6IG1hdGNoRW5kO1xuICAgICAgICBjb25zdCAkbnVtID0gaW5wdXQuc2xpY2UobnVtU3RhcnQsIG51bUVuZCk7XG4gICAgICAgIGxldCBuID0gcGFyc2VGbG9hdCgkbnVtKTtcbiAgICAgICAgY29uc3QgciA9IHJhbmdlW251bWJlcnMubGVuZ3RoXTtcbiAgICAgICAgaWYgKHVuaXRTdGFydCA+IC0xKSB7XG4gICAgICAgICAgICBjb25zdCB1bml0ID0gaW5wdXQuc2xpY2UodW5pdFN0YXJ0LCBtYXRjaEVuZCk7XG4gICAgICAgICAgICBjb25zdCB1ID0gdW5pdHNbdW5pdF07XG4gICAgICAgICAgICBpZiAodSAhPSBudWxsKSB7XG4gICAgICAgICAgICAgICAgbiAqPSByIC8gdTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgICBpZiAociA+IDEpIHtcbiAgICAgICAgICAgIG4gPSBNYXRoLnJvdW5kKG4pO1xuICAgICAgICB9XG4gICAgICAgIG51bWJlcnMucHVzaChuKTtcbiAgICAgICAgbnVtU3RhcnQgPSAtMTtcbiAgICAgICAgdW5pdFN0YXJ0ID0gLTE7XG4gICAgfTtcblxuICAgIGZvciAobGV0IGkgPSBzZWFyY2hTdGFydDsgaSA8IHNlYXJjaEVuZDsgaSsrKSB7XG4gICAgICAgIGNvbnN0IGMgPSBpbnB1dC5jaGFyQ29kZUF0KGkpO1xuICAgICAgICBjb25zdCBpc051bUNoYXIgPSAoYyA+PSBDXzAgJiYgYyA8PSBDXzkpIHx8IGMgPT09IENfRE9UIHx8IGMgPT09IENfUExVUyB8fCBjID09PSBDX01JTlVTIHx8IGMgPT09IENfZTtcbiAgICAgICAgY29uc3QgaXNEZWxpbWl0ZXIgPSBjID09PSBDX1NQQUNFIHx8IGMgPT09IENfQ09NTUEgfHwgYyA9PT0gQ19TTEFTSDtcbiAgICAgICAgaWYgKGlzTnVtQ2hhcikge1xuICAgICAgICAgICAgaWYgKG51bVN0YXJ0ID09PSAtMSkge1xuICAgICAgICAgICAgICAgIG51bVN0YXJ0ID0gaTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfSBlbHNlIGlmIChudW1TdGFydCA+IC0xKSB7XG4gICAgICAgICAgICBpZiAoaXNEZWxpbWl0ZXIpIHtcbiAgICAgICAgICAgICAgICBwdXNoKGkpO1xuICAgICAgICAgICAgfSBlbHNlIGlmICh1bml0U3RhcnQgPT09IC0xKSB7XG4gICAgICAgICAgICAgICAgdW5pdFN0YXJ0ID0gaTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgIH1cbiAgICBpZiAobnVtU3RhcnQgPiAtMSkge1xuICAgICAgICBwdXNoKHNlYXJjaEVuZCk7XG4gICAgfVxuICAgIHJldHVybiBudW1iZXJzO1xufVxuXG5jb25zdCByZ2JSYW5nZSA9IFsyNTUsIDI1NSwgMjU1LCAxXTtcbmNvbnN0IHJnYlVuaXRzID0geyclJzogMTAwfTtcblxuZXhwb3J0IGZ1bmN0aW9uIGdldFJHQlZhbHVlcyhpbnB1dDogc3RyaW5nKTogbnVtYmVyW10gfCBudWxsIHtcbiAgICBjb25zdCBDSEFSX0NPREVfMCA9IDQ4O1xuICAgIGNvbnN0IGxlbmd0aCA9IGlucHV0Lmxlbmd0aDtcbiAgICBsZXQgaSA9IDA7XG4gICAgbGV0IGRpZ2l0c0NvdW50ID0gMDtcbiAgICBsZXQgZGlnaXRTZXF1ZW5jZSA9IGZhbHNlO1xuICAgIGxldCBmbG9hdERpZ2l0c0NvdW50ID0gLTE7XG4gICAgbGV0IGRlbGltaXRlciA9IENfU1BBQ0U7XG4gICAgbGV0IGNoYW5uZWwgPSAtMTtcbiAgICBsZXQgcmVzdWx0OiBudW1iZXJbXSB8IG51bGwgPSBudWxsO1xuICAgIHdoaWxlIChpIDwgbGVuZ3RoKSB7XG4gICAgICAgIGNvbnN0IGMgPSBpbnB1dC5jaGFyQ29kZUF0KGkpO1xuICAgICAgICBpZiAoKGMgPj0gQ18wICYmIGMgPD0gQ185KSB8fCBjID09PSBDX0RPVCkge1xuICAgICAgICAgICAgaWYgKCFkaWdpdFNlcXVlbmNlKSB7XG4gICAgICAgICAgICAgICAgZGlnaXRTZXF1ZW5jZSA9IHRydWU7XG4gICAgICAgICAgICAgICAgZGlnaXRzQ291bnQgPSAwO1xuICAgICAgICAgICAgICAgIGZsb2F0RGlnaXRzQ291bnQgPSAtMTtcbiAgICAgICAgICAgICAgICBjaGFubmVsKys7XG4gICAgICAgICAgICAgICAgaWYgKGNoYW5uZWwgPT09IDMgJiYgcmVzdWx0KSB7XG4gICAgICAgICAgICAgICAgICAgIHJlc3VsdFszXSA9IDA7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIGlmIChjaGFubmVsID4gMykge1xuICAgICAgICAgICAgICAgICAgICByZXR1cm4gbnVsbDtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICBpZiAoYyA9PT0gQ19ET1QpIHtcbiAgICAgICAgICAgICAgICBpZiAoZmxvYXREaWdpdHNDb3VudCA+IDApIHtcbiAgICAgICAgICAgICAgICAgICAgcmV0dXJuIG51bGw7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIGZsb2F0RGlnaXRzQ291bnQgPSAwO1xuICAgICAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgICAgICBjb25zdCBkID0gYyAtIENIQVJfQ09ERV8wO1xuICAgICAgICAgICAgICAgIGlmICghcmVzdWx0KSB7XG4gICAgICAgICAgICAgICAgICAgIHJlc3VsdCA9IFswLCAwLCAwLCAxXTtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgaWYgKGZsb2F0RGlnaXRzQ291bnQgPiAtMSkge1xuICAgICAgICAgICAgICAgICAgICBmbG9hdERpZ2l0c0NvdW50Kys7XG4gICAgICAgICAgICAgICAgICAgIHJlc3VsdFtjaGFubmVsXSArPSBkIC8gKDEwICoqIGZsb2F0RGlnaXRzQ291bnQpO1xuICAgICAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgICAgIGRpZ2l0c0NvdW50Kys7XG4gICAgICAgICAgICAgICAgICAgIGlmIChkaWdpdHNDb3VudCA+IDMpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgIHJldHVybiBudWxsO1xuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgIHJlc3VsdFtjaGFubmVsXSA9IHJlc3VsdFtjaGFubmVsXSAqIDEwICsgZDtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9XG4gICAgICAgIH0gZWxzZSBpZiAoYyA9PT0gQ19QRVJDRU5UKSB7XG4gICAgICAgICAgICBpZiAoY2hhbm5lbCA8IDAgfHwgY2hhbm5lbCA+IDMgfHwgZGVsaW1pdGVyICE9PSBDX1NQQUNFIHx8ICFyZXN1bHQpIHtcbiAgICAgICAgICAgICAgICByZXR1cm4gbnVsbDtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIHJlc3VsdFtjaGFubmVsXSA9IGNoYW5uZWwgPCAzID8gTWF0aC5yb3VuZChyZXN1bHRbY2hhbm5lbF0gKiAyNTUgLyAxMDApIDogKHJlc3VsdFtjaGFubmVsXSAvIDEwMCk7XG4gICAgICAgICAgICBkaWdpdFNlcXVlbmNlID0gZmFsc2U7XG4gICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICBkaWdpdFNlcXVlbmNlID0gZmFsc2U7XG4gICAgICAgICAgICBpZiAoYyA9PT0gQ19TUEFDRSkge1xuICAgICAgICAgICAgICAgIGlmIChjaGFubmVsID09PSAwKSB7XG4gICAgICAgICAgICAgICAgICAgIGRlbGltaXRlciA9IGM7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSBlbHNlIGlmIChjID09PSBDX0NPTU1BKSB7XG4gICAgICAgICAgICAgICAgaWYgKGNoYW5uZWwgPT09IC0xKSB7XG4gICAgICAgICAgICAgICAgICAgIHJldHVybiBudWxsO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICBkZWxpbWl0ZXIgPSBDX0NPTU1BO1xuICAgICAgICAgICAgfSBlbHNlIGlmIChjID09PSBDX1NMQVNIKSB7XG4gICAgICAgICAgICAgICAgaWYgKGNoYW5uZWwgIT09IDIgfHwgZGVsaW1pdGVyICE9PSBDX1NQQUNFKSB7XG4gICAgICAgICAgICAgICAgICAgIHJldHVybiBudWxsO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgcmV0dXJuIG51bGw7XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgICAgaSsrO1xuICAgIH1cbiAgICBpZiAoY2hhbm5lbCA8IDIgfHwgY2hhbm5lbCA+IDMpIHtcbiAgICAgICAgcmV0dXJuIG51bGw7XG4gICAgfVxuICAgIHJldHVybiByZXN1bHQ7XG59XG5cbmZ1bmN0aW9uIHBhcnNlUkdCKCRyZ2I6IHN0cmluZyk6IFJHQkEgfCBudWxsIHtcbiAgICBjb25zdCBbciwgZywgYiwgYSA9IDFdID0gZ2V0TnVtYmVyc0Zyb21TdHJpbmcoJHJnYiwgcmdiUmFuZ2UsIHJnYlVuaXRzKTtcbiAgICBpZiAociA9PSBudWxsIHx8IGcgPT0gbnVsbCB8fCBiID09IG51bGwgfHwgYSA9PSBudWxsKSB7XG4gICAgICAgIHJldHVybiBudWxsO1xuICAgIH1cbiAgICByZXR1cm4ge3IsIGcsIGIsIGF9O1xufVxuXG5jb25zdCBoc2xSYW5nZSA9IFszNjAsIDEsIDEsIDFdO1xuY29uc3QgaHNsVW5pdHMgPSB7JyUnOiAxMDAsICdkZWcnOiAzNjAsICdyYWQnOiAyICogTWF0aC5QSSwgJ3R1cm4nOiAxfTtcblxuZnVuY3Rpb24gcGFyc2VIU0woJGhzbDogc3RyaW5nKTogUkdCQSB8IG51bGwge1xuICAgIGNvbnN0IFtoLCBzLCBsLCBhID0gMV0gPSBnZXROdW1iZXJzRnJvbVN0cmluZygkaHNsLCBoc2xSYW5nZSwgaHNsVW5pdHMpO1xuICAgIGlmIChoID09IG51bGwgfHwgcyA9PSBudWxsIHx8IGwgPT0gbnVsbCB8fCBhID09IG51bGwpIHtcbiAgICAgICAgcmV0dXJuIG51bGw7XG4gICAgfVxuICAgIHJldHVybiBoc2xUb1JHQih7aCwgcywgbCwgYX0pO1xufVxuXG5jb25zdCBDX0EgPSAnQScuY2hhckNvZGVBdCgwKTtcbmNvbnN0IENfRiA9ICdGJy5jaGFyQ29kZUF0KDApO1xuY29uc3QgQ19hID0gJ2EnLmNoYXJDb2RlQXQoMCk7XG5jb25zdCBDX2YgPSAnZicuY2hhckNvZGVBdCgwKTtcblxuZnVuY3Rpb24gcGFyc2VIZXgoJGhleDogc3RyaW5nKTogUkdCQSB8IG51bGwge1xuICAgIGNvbnN0IGxlbmd0aCA9ICRoZXgubGVuZ3RoO1xuICAgIGNvbnN0IGRpZ2l0Q291bnQgPSBsZW5ndGggLSAxO1xuICAgIGNvbnN0IGlzU2hvcnQgPSBkaWdpdENvdW50ID09PSAzIHx8IGRpZ2l0Q291bnQgPT09IDQ7XG4gICAgY29uc3QgaXNMb25nID0gZGlnaXRDb3VudCA9PT0gNiB8fCBkaWdpdENvdW50ID09PSA4O1xuICAgIGlmICghaXNTaG9ydCAmJiAhaXNMb25nKSB7XG4gICAgICAgIHJldHVybiBudWxsO1xuICAgIH1cblxuICAgIGNvbnN0IGhleCA9IChpOiBudW1iZXIpID0+IHtcbiAgICAgICAgY29uc3QgYyA9ICRoZXguY2hhckNvZGVBdChpKTtcbiAgICAgICAgaWYgKGMgPj0gQ19BICYmIGMgPD0gQ19GKSB7XG4gICAgICAgICAgICByZXR1cm4gYyArIDEwIC0gQ19BO1xuICAgICAgICB9XG4gICAgICAgIGlmIChjID49IENfYSAmJiBjIDw9IENfZikge1xuICAgICAgICAgICAgcmV0dXJuIGMgKyAxMCAtIENfYTtcbiAgICAgICAgfVxuICAgICAgICByZXR1cm4gYyAtIENfMDtcbiAgICB9O1xuXG4gICAgbGV0IHI6IG51bWJlcjtcbiAgICBsZXQgZzogbnVtYmVyO1xuICAgIGxldCBiOiBudW1iZXI7XG4gICAgbGV0IGEgPSAxO1xuICAgIGlmIChpc1Nob3J0KSB7XG4gICAgICAgIHIgPSBoZXgoMSkgKiAxNztcbiAgICAgICAgZyA9IGhleCgyKSAqIDE3O1xuICAgICAgICBiID0gaGV4KDMpICogMTc7XG4gICAgICAgIGlmIChkaWdpdENvdW50ID09PSA0KSB7XG4gICAgICAgICAgICBhID0gaGV4KDQpICogMTcgLyAyNTU7XG4gICAgICAgIH1cbiAgICB9IGVsc2Uge1xuICAgICAgICByID0gaGV4KDEpICogMTYgKyBoZXgoMik7XG4gICAgICAgIGcgPSBoZXgoMykgKiAxNiArIGhleCg0KTtcbiAgICAgICAgYiA9IGhleCg1KSAqIDE2ICsgaGV4KDYpO1xuICAgICAgICBpZiAoZGlnaXRDb3VudCA9PT0gOCkge1xuICAgICAgICAgICAgYSA9IChoZXgoNykgKiAxNiArIGhleCg4KSkgLyAyNTU7XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICByZXR1cm4ge3IsIGcsIGIsIGF9O1xufVxuXG5mdW5jdGlvbiBnZXRDb2xvckJ5TmFtZSgkY29sb3I6IHN0cmluZyk6IFJHQkEge1xuICAgIGNvbnN0IG4gPSBrbm93bkNvbG9ycy5nZXQoJGNvbG9yKSE7XG4gICAgcmV0dXJuIHtcbiAgICAgICAgcjogKG4gPj4gMTYpICYgMjU1LFxuICAgICAgICBnOiAobiA+PiA4KSAmIDI1NSxcbiAgICAgICAgYjogKG4gPj4gMCkgJiAyNTUsXG4gICAgICAgIGE6IDEsXG4gICAgfTtcbn1cblxuZnVuY3Rpb24gZ2V0U3lzdGVtQ29sb3IoJGNvbG9yOiBzdHJpbmcpOiBSR0JBIHtcbiAgICBjb25zdCBuID0gc3lzdGVtQ29sb3JzLmdldCgkY29sb3IpITtcbiAgICByZXR1cm4ge1xuICAgICAgICByOiAobiA+PiAxNikgJiAyNTUsXG4gICAgICAgIGc6IChuID4+IDgpICYgMjU1LFxuICAgICAgICBiOiAobiA+PiAwKSAmIDI1NSxcbiAgICAgICAgYTogMSxcbiAgICB9O1xufVxuXG4vLyBsb3dlckNhbGNFeHByZXNzaW9uIGlzIGEgaGVscGVyIGZ1bmN0aW9uIHRoYXQgdHJpZXMgdG8gcmVtb3ZlIGBjYWxjKC4uLilgXG4vLyBleHByZXNzaW9ucyBmcm9tIHRoZSBnaXZlbiBzdHJpbmcuIEl0IGNhbiBvbmx5IGxvd2VyIGV4cHJlc3Npb25zIHRvIGEgY2VydGFpblxuLy8gZGVncmVlIHNvIHdlIGNhbiBrZWVwIHRoaXMgZnVuY3Rpb24gZWFzeSBhbmQgc2ltcGxlIHRvIHVuZGVyc3RhbmQuXG5leHBvcnQgZnVuY3Rpb24gbG93ZXJDYWxjRXhwcmVzc2lvbihjb2xvcjogc3RyaW5nKTogc3RyaW5nIHtcbiAgICAvLyBzZWFyY2hJbmRleCB3aWxsIGJlIHVzZWQgYXMgc2VhcmNoSW5kZXggYW5kIGFzIGEgXCJjdXJzb3JcIiB3aXRoaW5cbiAgICAvLyB0aGUgY2FsYyguLi4pIGV4cHJlc3Npb24uXG4gICAgbGV0IHNlYXJjaEluZGV4ID0gMDtcblxuICAgIC8vIFJlcGxhY2UgdGhlIGNvbnRlbnQgYmV0d2VlbiB0d28gaW5kaWNlcy5cbiAgICBjb25zdCByZXBsYWNlQmV0d2VlbkluZGljZXMgPSAoc3RhcnQ6IG51bWJlciwgZW5kOiBudW1iZXIsIHJlcGxhY2VtZW50OiBzdHJpbmcpID0+IHtcbiAgICAgICAgY29sb3IgPSBjb2xvci5zdWJzdHJpbmcoMCwgc3RhcnQpICsgcmVwbGFjZW1lbnQgKyBjb2xvci5zdWJzdHJpbmcoZW5kKTtcbiAgICB9O1xuXG4gICAgLy8gUnVuIHRoaXMgY29kZSB1bnRpbCBpdCBkb2Vzbid0IGZpbmQgYW55IGBjYWxjKC4uLilgLlxuICAgIHdoaWxlICgoc2VhcmNoSW5kZXggPSBjb2xvci5pbmRleE9mKCdjYWxjKCcpKSAhPT0gLTEpIHtcbiAgICAgICAgLy8gR2V0IHRoZSBwYXJlbnRoZXNlcyByYW5nZXMgb2YgYGNhbGMoLi4uKWAuXG4gICAgICAgIGNvbnN0IHJhbmdlID0gZ2V0UGFyZW50aGVzZXNSYW5nZShjb2xvciwgc2VhcmNoSW5kZXgpO1xuICAgICAgICBpZiAoIXJhbmdlKSB7XG4gICAgICAgICAgICBicmVhaztcbiAgICAgICAgfVxuXG4gICAgICAgIC8vIEdldCB0aGUgY29udGVudCBiZXR3ZWVuIHRoZSBwYXJlbnRoZXNlcy5cbiAgICAgICAgbGV0IHNsaWNlID0gY29sb3Iuc2xpY2UocmFuZ2Uuc3RhcnQgKyAxLCByYW5nZS5lbmQgLSAxKTtcbiAgICAgICAgLy8gRG9lcyB0aGUgY29udGVudCBpbmNsdWRlIGEgcGVyY2VudGFnZT9cbiAgICAgICAgY29uc3QgaW5jbHVkZXNQZXJjZW50YWdlID0gc2xpY2UuaW5jbHVkZXMoJyUnKTtcbiAgICAgICAgLy8gUmVtb3ZlIGFsbCBwZXJjZW50YWdlcy5cbiAgICAgICAgc2xpY2UgPSBzbGljZS5zcGxpdCgnJScpLmpvaW4oJycpO1xuXG4gICAgICAgIC8vIFBhc3MgdGhlIGNvbnRlbnQgdG8gdGhlIGV2YWxNYXRoIGxpYnJhcnkgYW5kIHJvdW5kIGl0cyBvdXRwdXQuXG4gICAgICAgIGNvbnN0IG91dHB1dCA9IE1hdGgucm91bmQoZXZhbE1hdGgoc2xpY2UpKTtcblxuICAgICAgICAvLyBSZXBsYWNlIGBjYWxjKC4uLilgIHdpdGggdGhlIHJlc3VsdC5cbiAgICAgICAgcmVwbGFjZUJldHdlZW5JbmRpY2VzKHJhbmdlLnN0YXJ0IC0gNCwgcmFuZ2UuZW5kLCBvdXRwdXQgKyAoaW5jbHVkZXNQZXJjZW50YWdlID8gJyUnIDogJycpKTtcbiAgICB9XG4gICAgcmV0dXJuIGNvbG9yO1xufVxuXG5jb25zdCBrbm93bkNvbG9yczogTWFwPHN0cmluZywgbnVtYmVyPiA9IG5ldyBNYXAoT2JqZWN0LmVudHJpZXMoe1xuICAgIGFsaWNlYmx1ZTogMHhmMGY4ZmYsXG4gICAgYW50aXF1ZXdoaXRlOiAweGZhZWJkNyxcbiAgICBhcXVhOiAweDAwZmZmZixcbiAgICBhcXVhbWFyaW5lOiAweDdmZmZkNCxcbiAgICBhenVyZTogMHhmMGZmZmYsXG4gICAgYmVpZ2U6IDB4ZjVmNWRjLFxuICAgIGJpc3F1ZTogMHhmZmU0YzQsXG4gICAgYmxhY2s6IDB4MDAwMDAwLFxuICAgIGJsYW5jaGVkYWxtb25kOiAweGZmZWJjZCxcbiAgICBibHVlOiAweDAwMDBmZixcbiAgICBibHVldmlvbGV0OiAweDhhMmJlMixcbiAgICBicm93bjogMHhhNTJhMmEsXG4gICAgYnVybHl3b29kOiAweGRlYjg4NyxcbiAgICBjYWRldGJsdWU6IDB4NWY5ZWEwLFxuICAgIGNoYXJ0cmV1c2U6IDB4N2ZmZjAwLFxuICAgIGNob2NvbGF0ZTogMHhkMjY5MWUsXG4gICAgY29yYWw6IDB4ZmY3ZjUwLFxuICAgIGNvcm5mbG93ZXJibHVlOiAweDY0OTVlZCxcbiAgICBjb3Juc2lsazogMHhmZmY4ZGMsXG4gICAgY3JpbXNvbjogMHhkYzE0M2MsXG4gICAgY3lhbjogMHgwMGZmZmYsXG4gICAgZGFya2JsdWU6IDB4MDAwMDhiLFxuICAgIGRhcmtjeWFuOiAweDAwOGI4YixcbiAgICBkYXJrZ29sZGVucm9kOiAweGI4ODYwYixcbiAgICBkYXJrZ3JheTogMHhhOWE5YTksXG4gICAgZGFya2dyZXk6IDB4YTlhOWE5LFxuICAgIGRhcmtncmVlbjogMHgwMDY0MDAsXG4gICAgZGFya2toYWtpOiAweGJkYjc2YixcbiAgICBkYXJrbWFnZW50YTogMHg4YjAwOGIsXG4gICAgZGFya29saXZlZ3JlZW46IDB4NTU2YjJmLFxuICAgIGRhcmtvcmFuZ2U6IDB4ZmY4YzAwLFxuICAgIGRhcmtvcmNoaWQ6IDB4OTkzMmNjLFxuICAgIGRhcmtyZWQ6IDB4OGIwMDAwLFxuICAgIGRhcmtzYWxtb246IDB4ZTk5NjdhLFxuICAgIGRhcmtzZWFncmVlbjogMHg4ZmJjOGYsXG4gICAgZGFya3NsYXRlYmx1ZTogMHg0ODNkOGIsXG4gICAgZGFya3NsYXRlZ3JheTogMHgyZjRmNGYsXG4gICAgZGFya3NsYXRlZ3JleTogMHgyZjRmNGYsXG4gICAgZGFya3R1cnF1b2lzZTogMHgwMGNlZDEsXG4gICAgZGFya3Zpb2xldDogMHg5NDAwZDMsXG4gICAgZGVlcHBpbms6IDB4ZmYxNDkzLFxuICAgIGRlZXBza3libHVlOiAweDAwYmZmZixcbiAgICBkaW1ncmF5OiAweDY5Njk2OSxcbiAgICBkaW1ncmV5OiAweDY5Njk2OSxcbiAgICBkb2RnZXJibHVlOiAweDFlOTBmZixcbiAgICBmaXJlYnJpY2s6IDB4YjIyMjIyLFxuICAgIGZsb3JhbHdoaXRlOiAweGZmZmFmMCxcbiAgICBmb3Jlc3RncmVlbjogMHgyMjhiMjIsXG4gICAgZnVjaHNpYTogMHhmZjAwZmYsXG4gICAgZ2FpbnNib3JvOiAweGRjZGNkYyxcbiAgICBnaG9zdHdoaXRlOiAweGY4ZjhmZixcbiAgICBnb2xkOiAweGZmZDcwMCxcbiAgICBnb2xkZW5yb2Q6IDB4ZGFhNTIwLFxuICAgIGdyYXk6IDB4ODA4MDgwLFxuICAgIGdyZXk6IDB4ODA4MDgwLFxuICAgIGdyZWVuOiAweDAwODAwMCxcbiAgICBncmVlbnllbGxvdzogMHhhZGZmMmYsXG4gICAgaG9uZXlkZXc6IDB4ZjBmZmYwLFxuICAgIGhvdHBpbms6IDB4ZmY2OWI0LFxuICAgIGluZGlhbnJlZDogMHhjZDVjNWMsXG4gICAgaW5kaWdvOiAweDRiMDA4MixcbiAgICBpdm9yeTogMHhmZmZmZjAsXG4gICAga2hha2k6IDB4ZjBlNjhjLFxuICAgIGxhdmVuZGVyOiAweGU2ZTZmYSxcbiAgICBsYXZlbmRlcmJsdXNoOiAweGZmZjBmNSxcbiAgICBsYXduZ3JlZW46IDB4N2NmYzAwLFxuICAgIGxlbW9uY2hpZmZvbjogMHhmZmZhY2QsXG4gICAgbGlnaHRibHVlOiAweGFkZDhlNixcbiAgICBsaWdodGNvcmFsOiAweGYwODA4MCxcbiAgICBsaWdodGN5YW46IDB4ZTBmZmZmLFxuICAgIGxpZ2h0Z29sZGVucm9keWVsbG93OiAweGZhZmFkMixcbiAgICBsaWdodGdyYXk6IDB4ZDNkM2QzLFxuICAgIGxpZ2h0Z3JleTogMHhkM2QzZDMsXG4gICAgbGlnaHRncmVlbjogMHg5MGVlOTAsXG4gICAgbGlnaHRwaW5rOiAweGZmYjZjMSxcbiAgICBsaWdodHNhbG1vbjogMHhmZmEwN2EsXG4gICAgbGlnaHRzZWFncmVlbjogMHgyMGIyYWEsXG4gICAgbGlnaHRza3libHVlOiAweDg3Y2VmYSxcbiAgICBsaWdodHNsYXRlZ3JheTogMHg3Nzg4OTksXG4gICAgbGlnaHRzbGF0ZWdyZXk6IDB4Nzc4ODk5LFxuICAgIGxpZ2h0c3RlZWxibHVlOiAweGIwYzRkZSxcbiAgICBsaWdodHllbGxvdzogMHhmZmZmZTAsXG4gICAgbGltZTogMHgwMGZmMDAsXG4gICAgbGltZWdyZWVuOiAweDMyY2QzMixcbiAgICBsaW5lbjogMHhmYWYwZTYsXG4gICAgbWFnZW50YTogMHhmZjAwZmYsXG4gICAgbWFyb29uOiAweDgwMDAwMCxcbiAgICBtZWRpdW1hcXVhbWFyaW5lOiAweDY2Y2RhYSxcbiAgICBtZWRpdW1ibHVlOiAweDAwMDBjZCxcbiAgICBtZWRpdW1vcmNoaWQ6IDB4YmE1NWQzLFxuICAgIG1lZGl1bXB1cnBsZTogMHg5MzcwZGIsXG4gICAgbWVkaXVtc2VhZ3JlZW46IDB4M2NiMzcxLFxuICAgIG1lZGl1bXNsYXRlYmx1ZTogMHg3YjY4ZWUsXG4gICAgbWVkaXVtc3ByaW5nZ3JlZW46IDB4MDBmYTlhLFxuICAgIG1lZGl1bXR1cnF1b2lzZTogMHg0OGQxY2MsXG4gICAgbWVkaXVtdmlvbGV0cmVkOiAweGM3MTU4NSxcbiAgICBtaWRuaWdodGJsdWU6IDB4MTkxOTcwLFxuICAgIG1pbnRjcmVhbTogMHhmNWZmZmEsXG4gICAgbWlzdHlyb3NlOiAweGZmZTRlMSxcbiAgICBtb2NjYXNpbjogMHhmZmU0YjUsXG4gICAgbmF2YWpvd2hpdGU6IDB4ZmZkZWFkLFxuICAgIG5hdnk6IDB4MDAwMDgwLFxuICAgIG9sZGxhY2U6IDB4ZmRmNWU2LFxuICAgIG9saXZlOiAweDgwODAwMCxcbiAgICBvbGl2ZWRyYWI6IDB4NmI4ZTIzLFxuICAgIG9yYW5nZTogMHhmZmE1MDAsXG4gICAgb3JhbmdlcmVkOiAweGZmNDUwMCxcbiAgICBvcmNoaWQ6IDB4ZGE3MGQ2LFxuICAgIHBhbGVnb2xkZW5yb2Q6IDB4ZWVlOGFhLFxuICAgIHBhbGVncmVlbjogMHg5OGZiOTgsXG4gICAgcGFsZXR1cnF1b2lzZTogMHhhZmVlZWUsXG4gICAgcGFsZXZpb2xldHJlZDogMHhkYjcwOTMsXG4gICAgcGFwYXlhd2hpcDogMHhmZmVmZDUsXG4gICAgcGVhY2hwdWZmOiAweGZmZGFiOSxcbiAgICBwZXJ1OiAweGNkODUzZixcbiAgICBwaW5rOiAweGZmYzBjYixcbiAgICBwbHVtOiAweGRkYTBkZCxcbiAgICBwb3dkZXJibHVlOiAweGIwZTBlNixcbiAgICBwdXJwbGU6IDB4ODAwMDgwLFxuICAgIHJlYmVjY2FwdXJwbGU6IDB4NjYzMzk5LFxuICAgIHJlZDogMHhmZjAwMDAsXG4gICAgcm9zeWJyb3duOiAweGJjOGY4ZixcbiAgICByb3lhbGJsdWU6IDB4NDE2OWUxLFxuICAgIHNhZGRsZWJyb3duOiAweDhiNDUxMyxcbiAgICBzYWxtb246IDB4ZmE4MDcyLFxuICAgIHNhbmR5YnJvd246IDB4ZjRhNDYwLFxuICAgIHNlYWdyZWVuOiAweDJlOGI1NyxcbiAgICBzZWFzaGVsbDogMHhmZmY1ZWUsXG4gICAgc2llbm5hOiAweGEwNTIyZCxcbiAgICBzaWx2ZXI6IDB4YzBjMGMwLFxuICAgIHNreWJsdWU6IDB4ODdjZWViLFxuICAgIHNsYXRlYmx1ZTogMHg2YTVhY2QsXG4gICAgc2xhdGVncmF5OiAweDcwODA5MCxcbiAgICBzbGF0ZWdyZXk6IDB4NzA4MDkwLFxuICAgIHNub3c6IDB4ZmZmYWZhLFxuICAgIHNwcmluZ2dyZWVuOiAweDAwZmY3ZixcbiAgICBzdGVlbGJsdWU6IDB4NDY4MmI0LFxuICAgIHRhbjogMHhkMmI0OGMsXG4gICAgdGVhbDogMHgwMDgwODAsXG4gICAgdGhpc3RsZTogMHhkOGJmZDgsXG4gICAgdG9tYXRvOiAweGZmNjM0NyxcbiAgICB0dXJxdW9pc2U6IDB4NDBlMGQwLFxuICAgIHZpb2xldDogMHhlZTgyZWUsXG4gICAgd2hlYXQ6IDB4ZjVkZWIzLFxuICAgIHdoaXRlOiAweGZmZmZmZixcbiAgICB3aGl0ZXNtb2tlOiAweGY1ZjVmNSxcbiAgICB5ZWxsb3c6IDB4ZmZmZjAwLFxuICAgIHllbGxvd2dyZWVuOiAweDlhY2QzMixcbn0pKTtcblxuY29uc3Qgc3lzdGVtQ29sb3JzOiBNYXA8c3RyaW5nLCBudW1iZXI+ID0gbmV3IE1hcChPYmplY3QuZW50cmllcyh7XG4gICAgQWN0aXZlQm9yZGVyOiAweDNiOTlmYyxcbiAgICBBY3RpdmVDYXB0aW9uOiAweDAwMDAwMCxcbiAgICBBcHBXb3Jrc3BhY2U6IDB4YWFhYWFhLFxuICAgIEJhY2tncm91bmQ6IDB4NjM2M2NlLFxuICAgIEJ1dHRvbkZhY2U6IDB4ZmZmZmZmLFxuICAgIEJ1dHRvbkhpZ2hsaWdodDogMHhlOWU5ZTksXG4gICAgQnV0dG9uU2hhZG93OiAweDlmYTA5ZixcbiAgICBCdXR0b25UZXh0OiAweDAwMDAwMCxcbiAgICBDYXB0aW9uVGV4dDogMHgwMDAwMDAsXG4gICAgR3JheVRleHQ6IDB4N2Y3ZjdmLFxuICAgIEhpZ2hsaWdodDogMHhiMmQ3ZmYsXG4gICAgSGlnaGxpZ2h0VGV4dDogMHgwMDAwMDAsXG4gICAgSW5hY3RpdmVCb3JkZXI6IDB4ZmZmZmZmLFxuICAgIEluYWN0aXZlQ2FwdGlvbjogMHhmZmZmZmYsXG4gICAgSW5hY3RpdmVDYXB0aW9uVGV4dDogMHgwMDAwMDAsXG4gICAgSW5mb0JhY2tncm91bmQ6IDB4ZmJmY2M1LFxuICAgIEluZm9UZXh0OiAweDAwMDAwMCxcbiAgICBNZW51OiAweGY2ZjZmNixcbiAgICBNZW51VGV4dDogMHhmZmZmZmYsXG4gICAgU2Nyb2xsYmFyOiAweGFhYWFhYSxcbiAgICBUaHJlZUREYXJrU2hhZG93OiAweDAwMDAwMCxcbiAgICBUaHJlZURGYWNlOiAweGMwYzBjMCxcbiAgICBUaHJlZURIaWdobGlnaHQ6IDB4ZmZmZmZmLFxuICAgIFRocmVlRExpZ2h0U2hhZG93OiAweGZmZmZmZixcbiAgICBUaHJlZURTaGFkb3c6IDB4MDAwMDAwLFxuICAgIFdpbmRvdzogMHhlY2VjZWMsXG4gICAgV2luZG93RnJhbWU6IDB4YWFhYWFhLFxuICAgIFdpbmRvd1RleHQ6IDB4MDAwMDAwLFxuICAgICctd2Via2l0LWZvY3VzLXJpbmctY29sb3InOiAweGU1OTcwMCxcbn0pLm1hcCgoW2tleSwgdmFsdWVdKSA9PiBba2V5LnRvTG93ZXJDYXNlKCksIHZhbHVlXSBhcyBbc3RyaW5nLCBudW1iZXJdKSk7XG5cbi8vIGh0dHBzOi8vZW4ud2lraXBlZGlhLm9yZy93aWtpL1JlbGF0aXZlX2x1bWluYW5jZVxuZXhwb3J0IGZ1bmN0aW9uIGdldFNSR0JMaWdodG5lc3MocjogbnVtYmVyLCBnOiBudW1iZXIsIGI6IG51bWJlcik6IG51bWJlciB7XG4gICAgcmV0dXJuICgwLjIxMjYgKiByICsgMC43MTUyICogZyArIDAuMDcyMiAqIGIpIC8gMjU1O1xufVxuXG5sZXQgY2FudmFzOiBIVE1MQ2FudmFzRWxlbWVudDtcbmxldCBjb250ZXh0OiBDYW52YXNSZW5kZXJpbmdDb250ZXh0MkQ7XG5cbmZ1bmN0aW9uIGRvbVBhcnNlQ29sb3IoJGNvbG9yOiBzdHJpbmcpIHtcbiAgICBpZiAoIWNvbnRleHQpIHtcbiAgICAgICAgY2FudmFzID0gZG9jdW1lbnQuY3JlYXRlRWxlbWVudCgnY2FudmFzJyk7XG4gICAgICAgIGNhbnZhcy53aWR0aCA9IDE7XG4gICAgICAgIGNhbnZhcy5oZWlnaHQgPSAxO1xuICAgICAgICBjb250ZXh0ID0gY2FudmFzLmdldENvbnRleHQoJzJkJywge3dpbGxSZWFkRnJlcXVlbnRseTogdHJ1ZX0pITtcbiAgICB9XG4gICAgY29udGV4dC5maWxsU3R5bGUgPSAkY29sb3I7XG4gICAgY29udGV4dC5maWxsUmVjdCgwLCAwLCAxLCAxKTtcbiAgICBjb25zdCBkID0gY29udGV4dC5nZXRJbWFnZURhdGEoMCwgMCwgMSwgMSkuZGF0YTtcbiAgICBjb25zdCBjb2xvciA9IGByZ2JhKCR7ZFswXX0sICR7ZFsxXX0sICR7ZFsyXX0sICR7KGRbM10gLyAyNTUpLnRvRml4ZWQoMil9KWA7XG4gICAgcmV0dXJuIHBhcnNlUkdCKGNvbG9yKTtcbn1cbiIsImltcG9ydCB7cGFyc2VDb2xvcldpdGhDYWNoZSwgcmdiVG9IZXhTdHJpbmcsIHR5cGUgUkdCQX0gZnJvbSAnLi4vLi4vdXRpbHMvY29sb3InO1xuXG5pbnRlcmZhY2UgUmVnaXN0ZXJlZENvbG9yIHtcbiAgICBwYXJzZWQ6IFJHQkE7XG4gICAgYmFja2dyb3VuZD86IHtcbiAgICAgICAgdmFsdWU6IHN0cmluZztcbiAgICAgICAgdmFyaWFibGU6IHN0cmluZztcbiAgICB9O1xuICAgIHRleHQ/OiB7XG4gICAgICAgIHZhbHVlOiBzdHJpbmc7XG4gICAgICAgIHZhcmlhYmxlOiBzdHJpbmc7XG4gICAgfTtcbiAgICBib3JkZXI/OiB7XG4gICAgICAgIHZhbHVlOiBzdHJpbmc7XG4gICAgICAgIHZhcmlhYmxlOiBzdHJpbmc7XG4gICAgfTtcbn1cblxudHlwZSBDb2xvclR5cGUgPSAnYmFja2dyb3VuZCcgfCAnYm9yZGVyJyB8ICd0ZXh0JztcblxuaW50ZXJmYWNlIENvbG9yUGFsZXR0ZSB7XG4gICAgYmFja2dyb3VuZDogUkdCQVtdO1xuICAgIGJvcmRlcjogUkdCQVtdO1xuICAgIHRleHQ6IFJHQkFbXTtcbn1cblxubGV0IHZhcmlhYmxlc1NoZWV0OiBDU1NTdHlsZVNoZWV0IHwgbnVsbDtcblxuY29uc3QgcmVnaXN0ZXJlZENvbG9ycyA9IG5ldyBNYXA8c3RyaW5nLCBSZWdpc3RlcmVkQ29sb3I+KCk7XG5cbmV4cG9ydCBmdW5jdGlvbiByZWdpc3RlclZhcmlhYmxlc1NoZWV0KHNoZWV0OiBDU1NTdHlsZVNoZWV0KTogdm9pZCB7XG4gICAgdmFyaWFibGVzU2hlZXQgPSBzaGVldDtcbiAgICBjb25zdCB0eXBlczogQ29sb3JUeXBlW10gPSBbJ2JhY2tncm91bmQnLCAndGV4dCcsICdib3JkZXInXTtcbiAgICByZWdpc3RlcmVkQ29sb3JzLmZvckVhY2goKHJlZ2lzdGVyZWQpID0+IHtcbiAgICAgICAgdHlwZXMuZm9yRWFjaCgodHlwZSkgPT4ge1xuICAgICAgICAgICAgaWYgKHJlZ2lzdGVyZWRbdHlwZV0pIHtcbiAgICAgICAgICAgICAgICBjb25zdCB7dmFyaWFibGUsIHZhbHVlfSA9IHJlZ2lzdGVyZWRbdHlwZV07XG4gICAgICAgICAgICAgICAgKHZhcmlhYmxlc1NoZWV0Py5jc3NSdWxlc1swXSBhcyBDU1NTdHlsZVJ1bGUpLnN0eWxlLnNldFByb3BlcnR5KHZhcmlhYmxlLCB2YWx1ZSk7XG4gICAgICAgICAgICB9XG4gICAgICAgIH0pO1xuICAgIH0pO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gcmVsZWFzZVZhcmlhYmxlc1NoZWV0KCk6IHZvaWQge1xuICAgIHZhcmlhYmxlc1NoZWV0ID0gbnVsbDtcbiAgICBjbGVhckNvbG9yUGFsZXR0ZSgpO1xufVxuXG5mdW5jdGlvbiBnZXRSZWdpc3RlcmVkVmFyaWFibGVWYWx1ZSh0eXBlOiBDb2xvclR5cGUsIHJlZ2lzdGVyZWQ6IFJlZ2lzdGVyZWRDb2xvcikge1xuICAgIHJldHVybiBgdmFyKCR7cmVnaXN0ZXJlZFt0eXBlXSEudmFyaWFibGV9LCAke3JlZ2lzdGVyZWRbdHlwZV0hLnZhbHVlfSlgO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gZ2V0UmVnaXN0ZXJlZENvbG9yKHR5cGU6IENvbG9yVHlwZSwgcGFyc2VkOiBSR0JBKTogc3RyaW5nIHwgbnVsbCB7XG4gICAgY29uc3QgaGV4ID0gcmdiVG9IZXhTdHJpbmcocGFyc2VkKTtcbiAgICBjb25zdCByZWdpc3RlcmVkID0gcmVnaXN0ZXJlZENvbG9ycy5nZXQoaGV4KTtcbiAgICBpZiAocmVnaXN0ZXJlZD8uW3R5cGVdKSB7XG4gICAgICAgIHJldHVybiBnZXRSZWdpc3RlcmVkVmFyaWFibGVWYWx1ZSh0eXBlLCByZWdpc3RlcmVkKTtcbiAgICB9XG4gICAgcmV0dXJuIG51bGw7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiByZWdpc3RlckNvbG9yKHR5cGU6IENvbG9yVHlwZSwgcGFyc2VkOiBSR0JBLCB2YWx1ZTogc3RyaW5nKTogc3RyaW5nIHtcbiAgICBjb25zdCBoZXggPSByZ2JUb0hleFN0cmluZyhwYXJzZWQpO1xuXG4gICAgbGV0IHJlZ2lzdGVyZWQ6IFJlZ2lzdGVyZWRDb2xvcjtcbiAgICBpZiAocmVnaXN0ZXJlZENvbG9ycy5oYXMoaGV4KSkge1xuICAgICAgICByZWdpc3RlcmVkID0gcmVnaXN0ZXJlZENvbG9ycy5nZXQoaGV4KSE7XG4gICAgfSBlbHNlIHtcbiAgICAgICAgY29uc3QgcGFyc2VkID0gcGFyc2VDb2xvcldpdGhDYWNoZShoZXgpITtcbiAgICAgICAgcmVnaXN0ZXJlZCA9IHtwYXJzZWR9O1xuICAgICAgICByZWdpc3RlcmVkQ29sb3JzLnNldChoZXgsIHJlZ2lzdGVyZWQpO1xuICAgIH1cblxuICAgIGNvbnN0IHZhcmlhYmxlID0gYC0tZGFya3JlYWRlci0ke3R5cGV9LSR7aGV4LnJlcGxhY2UoJyMnLCAnJyl9YDtcbiAgICByZWdpc3RlcmVkW3R5cGVdID0ge3ZhcmlhYmxlLCB2YWx1ZX07XG4gICAgaWYgKCh2YXJpYWJsZXNTaGVldD8uY3NzUnVsZXNbMF0gYXMgQ1NTU3R5bGVSdWxlKT8uc3R5bGUpIHtcbiAgICAgICAgKHZhcmlhYmxlc1NoZWV0Py5jc3NSdWxlc1swXSBhcyBDU1NTdHlsZVJ1bGUpLnN0eWxlLnNldFByb3BlcnR5KHZhcmlhYmxlLCB2YWx1ZSk7XG4gICAgfVxuXG4gICAgcmV0dXJuIGdldFJlZ2lzdGVyZWRWYXJpYWJsZVZhbHVlKHR5cGUsIHJlZ2lzdGVyZWQpO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gZ2V0Q29sb3JQYWxldHRlKCk6IENvbG9yUGFsZXR0ZSB7XG4gICAgY29uc3QgYmFja2dyb3VuZDogUkdCQVtdID0gW107XG4gICAgY29uc3QgYm9yZGVyOiBSR0JBW10gPSBbXTtcbiAgICBjb25zdCB0ZXh0OiBSR0JBW10gPSBbXTtcblxuICAgIHJlZ2lzdGVyZWRDb2xvcnMuZm9yRWFjaCgocmVnaXN0ZXJlZCkgPT4ge1xuICAgICAgICBpZiAocmVnaXN0ZXJlZC5iYWNrZ3JvdW5kKSB7XG4gICAgICAgICAgICBiYWNrZ3JvdW5kLnB1c2gocmVnaXN0ZXJlZC5wYXJzZWQpO1xuICAgICAgICB9XG4gICAgICAgIGlmIChyZWdpc3RlcmVkLmJvcmRlcikge1xuICAgICAgICAgICAgYm9yZGVyLnB1c2gocmVnaXN0ZXJlZC5wYXJzZWQpO1xuICAgICAgICB9XG4gICAgICAgIGlmIChyZWdpc3RlcmVkLnRleHQpIHtcbiAgICAgICAgICAgIHRleHQucHVzaChyZWdpc3RlcmVkLnBhcnNlZCk7XG4gICAgICAgIH1cbiAgICB9KTtcblxuICAgIHJldHVybiB7YmFja2dyb3VuZCwgYm9yZGVyLCB0ZXh0fTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIGNsZWFyQ29sb3JQYWxldHRlKCk6IHZvaWQge1xuICAgIHJlZ2lzdGVyZWRDb2xvcnMuY2xlYXIoKTtcbn1cbiIsImltcG9ydCB7ZXh0ZW5kVGhlbWVDYWNoZUtleXMsIGdldEJhY2tncm91bmRQb2xlcywgZ2V0VGV4dFBvbGVzLCBtb2RpZnlCZ0NvbG9yRXh0ZW5kZWQsIG1vZGlmeUZnQ29sb3JFeHRlbmRlZCwgbW9kaWZ5TGlnaHRTY2hlbWVDb2xvckV4dGVuZGVkfSBmcm9tICdAcGx1cy91dGlscy90aGVtZSc7XG5pbXBvcnQgdHlwZSB7VGhlbWV9IGZyb20gJy4uLy4uL2RlZmluaXRpb25zJztcbmltcG9ydCB7YXBwbHlDb2xvck1hdHJpeCwgY3JlYXRlRmlsdGVyTWF0cml4fSBmcm9tICcuLi8uLi9nZW5lcmF0b3JzL3V0aWxzL21hdHJpeCc7XG5pbXBvcnQge2dldFJlZ2lzdGVyZWRDb2xvciwgcmVnaXN0ZXJDb2xvcn0gZnJvbSAnLi4vLi4vaW5qZWN0L2R5bmFtaWMtdGhlbWUvcGFsZXR0ZSc7XG5pbXBvcnQgdHlwZSB7UkdCQSwgSFNMQX0gZnJvbSAnLi4vLi4vdXRpbHMvY29sb3InO1xuaW1wb3J0IHtwYXJzZVRvSFNMV2l0aENhY2hlLCByZ2JUb0hTTCwgaHNsVG9SR0IsIHJnYlRvU3RyaW5nLCByZ2JUb0hleFN0cmluZ30gZnJvbSAnLi4vLi4vdXRpbHMvY29sb3InO1xuaW1wb3J0IHtzY2FsZX0gZnJvbSAnLi4vLi4vdXRpbHMvbWF0aCc7XG5cbmludGVyZmFjZSBDb2xvckZ1bmN0aW9uIHtcbiAgICAoaHNsOiBIU0xBKTogSFNMQTtcbn1cblxuZGVjbGFyZSBjb25zdCBfX1BMVVNfXzogYm9vbGVhbjtcblxuZnVuY3Rpb24gZ2V0QmdQb2xlKHRoZW1lOiBUaGVtZSkge1xuICAgIGNvbnN0IGlzRGFya1NjaGVtZSA9IHRoZW1lLm1vZGUgPT09IDE7XG4gICAgY29uc3QgcHJvcDoga2V5b2YgVGhlbWUgPSBpc0RhcmtTY2hlbWUgPyAnZGFya1NjaGVtZUJhY2tncm91bmRDb2xvcicgOiAnbGlnaHRTY2hlbWVCYWNrZ3JvdW5kQ29sb3InO1xuICAgIHJldHVybiB0aGVtZVtwcm9wXTtcbn1cblxuZnVuY3Rpb24gZ2V0RmdQb2xlKHRoZW1lOiBUaGVtZSkge1xuICAgIGNvbnN0IGlzRGFya1NjaGVtZSA9IHRoZW1lLm1vZGUgPT09IDE7XG4gICAgY29uc3QgcHJvcDoga2V5b2YgVGhlbWUgPSBpc0RhcmtTY2hlbWUgPyAnZGFya1NjaGVtZVRleHRDb2xvcicgOiAnbGlnaHRTY2hlbWVUZXh0Q29sb3InO1xuICAgIHJldHVybiB0aGVtZVtwcm9wXTtcbn1cblxuY29uc3QgY29sb3JNb2RpZmljYXRpb25DYWNoZSA9IG5ldyBNYXA8Q29sb3JGdW5jdGlvbiwgTWFwPHN0cmluZywgc3RyaW5nPj4oKTtcblxuZXhwb3J0IGZ1bmN0aW9uIGNsZWFyQ29sb3JNb2RpZmljYXRpb25DYWNoZSgpOiB2b2lkIHtcbiAgICBjb2xvck1vZGlmaWNhdGlvbkNhY2hlLmNsZWFyKCk7XG59XG5cbmNvbnN0IHJnYkNhY2hlS2V5czogQXJyYXk8a2V5b2YgUkdCQT4gPSBbJ3InLCAnZycsICdiJywgJ2EnXTtcblxuZXhwb3J0IGNvbnN0IHRoZW1lQ2FjaGVLZXlzOiBBcnJheTxrZXlvZiBUaGVtZT4gPSBbXG4gICAgJ21vZGUnLFxuICAgICdicmlnaHRuZXNzJyxcbiAgICAnY29udHJhc3QnLFxuICAgICdncmF5c2NhbGUnLFxuICAgICdzZXBpYScsXG4gICAgJ2RhcmtTY2hlbWVCYWNrZ3JvdW5kQ29sb3InLFxuICAgICdkYXJrU2NoZW1lVGV4dENvbG9yJyxcbiAgICAnbGlnaHRTY2hlbWVCYWNrZ3JvdW5kQ29sb3InLFxuICAgICdsaWdodFNjaGVtZVRleHRDb2xvcicsXG5dO1xuZXh0ZW5kVGhlbWVDYWNoZUtleXModGhlbWVDYWNoZUtleXMpO1xuXG5mdW5jdGlvbiBnZXRDYWNoZUlkKHJnYjogUkdCQSwgdGhlbWU6IFRoZW1lKTogc3RyaW5nIHtcbiAgICBsZXQgcmVzdWx0SWQgPSAnJztcbiAgICByZ2JDYWNoZUtleXMuZm9yRWFjaCgoa2V5KSA9PiB7XG4gICAgICAgIHJlc3VsdElkICs9IGAke3JnYltrZXldfTtgO1xuICAgIH0pO1xuICAgIHRoZW1lQ2FjaGVLZXlzLmZvckVhY2goKGtleSkgPT4ge1xuICAgICAgICByZXN1bHRJZCArPSBgJHt0aGVtZVtrZXldfTtgO1xuICAgIH0pO1xuICAgIHJldHVybiByZXN1bHRJZDtcbn1cblxuZnVuY3Rpb24gbW9kaWZ5Q29sb3JXaXRoQ2FjaGUocmdiOiBSR0JBLCB0aGVtZTogVGhlbWUsIG1vZGlmeUhTTDogKGhzbDogSFNMQSwgcG9sZT86IEhTTEEgfCBudWxsLCBhbm90aGVyUG9sZT86IEhTTEEgfCBudWxsKSA9PiBIU0xBLCBwb2xlQ29sb3I/OiBzdHJpbmcsIGFub3RoZXJQb2xlQ29sb3I/OiBzdHJpbmcpOiBzdHJpbmcge1xuICAgIGxldCBmbkNhY2hlOiBNYXA8c3RyaW5nLCBzdHJpbmc+O1xuICAgIGlmIChjb2xvck1vZGlmaWNhdGlvbkNhY2hlLmhhcyhtb2RpZnlIU0wpKSB7XG4gICAgICAgIGZuQ2FjaGUgPSBjb2xvck1vZGlmaWNhdGlvbkNhY2hlLmdldChtb2RpZnlIU0wpITtcbiAgICB9IGVsc2Uge1xuICAgICAgICBmbkNhY2hlID0gbmV3IE1hcCgpO1xuICAgICAgICBjb2xvck1vZGlmaWNhdGlvbkNhY2hlLnNldChtb2RpZnlIU0wsIGZuQ2FjaGUpO1xuICAgIH1cbiAgICBjb25zdCBpZCA9IGdldENhY2hlSWQocmdiLCB0aGVtZSk7XG4gICAgaWYgKGZuQ2FjaGUuaGFzKGlkKSkge1xuICAgICAgICByZXR1cm4gZm5DYWNoZS5nZXQoaWQpITtcbiAgICB9XG5cbiAgICBjb25zdCBoc2wgPSByZ2JUb0hTTChyZ2IpO1xuICAgIGNvbnN0IHBvbGUgPSBwb2xlQ29sb3IgPT0gbnVsbCA/IG51bGwgOiBwYXJzZVRvSFNMV2l0aENhY2hlKHBvbGVDb2xvcik7XG4gICAgY29uc3QgYW5vdGhlclBvbGUgPSBhbm90aGVyUG9sZUNvbG9yID09IG51bGwgPyBudWxsIDogcGFyc2VUb0hTTFdpdGhDYWNoZShhbm90aGVyUG9sZUNvbG9yKTtcbiAgICBjb25zdCBtb2RpZmllZCA9IG1vZGlmeUhTTChoc2wsIHBvbGUsIGFub3RoZXJQb2xlKTtcbiAgICBjb25zdCB7ciwgZywgYiwgYX0gPSBoc2xUb1JHQihtb2RpZmllZCk7XG4gICAgY29uc3QgbWF0cml4ID0gY3JlYXRlRmlsdGVyTWF0cml4KHsuLi50aGVtZSwgbW9kZTogMH0pO1xuICAgIGNvbnN0IFtyZiwgZ2YsIGJmXSA9IGFwcGx5Q29sb3JNYXRyaXgoW3IsIGcsIGJdLCBtYXRyaXgpO1xuXG4gICAgY29uc3QgY29sb3IgPSAoYSA9PT0gMSA/XG4gICAgICAgIHJnYlRvSGV4U3RyaW5nKHtyOiByZiwgZzogZ2YsIGI6IGJmfSkgOlxuICAgICAgICByZ2JUb1N0cmluZyh7cjogcmYsIGc6IGdmLCBiOiBiZiwgYX0pKTtcblxuICAgIGZuQ2FjaGUuc2V0KGlkLCBjb2xvcik7XG4gICAgcmV0dXJuIGNvbG9yO1xufVxuXG5mdW5jdGlvbiBub29wSFNMKGhzbDogSFNMQSk6IEhTTEEge1xuICAgIHJldHVybiBoc2w7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBtb2RpZnlDb2xvcihyZ2I6IFJHQkEsIHRoZW1lOiBUaGVtZSk6IHN0cmluZyB7XG4gICAgcmV0dXJuIG1vZGlmeUNvbG9yV2l0aENhY2hlKHJnYiwgdGhlbWUsIG5vb3BIU0wpO1xufVxuXG5mdW5jdGlvbiBtb2RpZnlBbmRSZWdpc3RlckNvbG9yKFxuICAgIHR5cGU6ICdiYWNrZ3JvdW5kJyB8ICd0ZXh0JyB8ICdib3JkZXInLFxuICAgIHJnYjogUkdCQSxcbiAgICB0aGVtZTogVGhlbWUsXG4gICAgbW9kaWZpZXI6IChyZ2I6IFJHQkEsIHRoZW1lOiBUaGVtZSkgPT4gc3RyaW5nLFxuKSB7XG4gICAgY29uc3QgcmVnaXN0ZXJlZCA9IGdldFJlZ2lzdGVyZWRDb2xvcih0eXBlLCByZ2IpO1xuICAgIGlmIChyZWdpc3RlcmVkKSB7XG4gICAgICAgIHJldHVybiByZWdpc3RlcmVkO1xuICAgIH1cbiAgICBjb25zdCB2YWx1ZSA9IG1vZGlmaWVyKHJnYiwgdGhlbWUpO1xuICAgIHJldHVybiByZWdpc3RlckNvbG9yKHR5cGUsIHJnYiwgdmFsdWUpO1xufVxuXG5mdW5jdGlvbiBtb2RpZnlMaWdodFNjaGVtZUNvbG9yKHJnYjogUkdCQSwgdGhlbWU6IFRoZW1lKTogc3RyaW5nIHtcbiAgICBjb25zdCBwb2xlQmcgPSBnZXRCZ1BvbGUodGhlbWUpO1xuICAgIGNvbnN0IHBvbGVGZyA9IGdldEZnUG9sZSh0aGVtZSk7XG4gICAgcmV0dXJuIG1vZGlmeUNvbG9yV2l0aENhY2hlKHJnYiwgdGhlbWUsIG1vZGlmeUxpZ2h0TW9kZUhTTCwgcG9sZUZnLCBwb2xlQmcpO1xufVxuXG5mdW5jdGlvbiBtb2RpZnlMaWdodE1vZGVIU0woe2gsIHMsIGwsIGF9OiBIU0xBLCBwb2xlRmc6IEhTTEEsIHBvbGVCZzogSFNMQSk6IEhTTEEge1xuICAgIGNvbnN0IGlzRGFyayA9IGwgPCAwLjU7XG4gICAgbGV0IGlzTmV1dHJhbDogYm9vbGVhbjtcbiAgICBpZiAoaXNEYXJrKSB7XG4gICAgICAgIGlzTmV1dHJhbCA9IGwgPCAwLjIgfHwgcyA8IDAuMTI7XG4gICAgfSBlbHNlIHtcbiAgICAgICAgY29uc3QgaXNCbHVlID0gaCA+IDIwMCAmJiBoIDwgMjgwO1xuICAgICAgICBpc05ldXRyYWwgPSBzIDwgMC4yNCB8fCAobCA+IDAuOCAmJiBpc0JsdWUpO1xuICAgIH1cblxuICAgIGxldCBoeCA9IGg7XG4gICAgbGV0IHN4ID0gcztcbiAgICBpZiAoaXNOZXV0cmFsKSB7XG4gICAgICAgIGlmIChpc0RhcmspIHtcbiAgICAgICAgICAgIGh4ID0gcG9sZUZnLmg7XG4gICAgICAgICAgICBzeCA9IHBvbGVGZy5zO1xuICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgaHggPSBwb2xlQmcuaDtcbiAgICAgICAgICAgIHN4ID0gcG9sZUJnLnM7XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBjb25zdCBseCA9IHNjYWxlKGwsIDAsIDEsIHBvbGVGZy5sLCBwb2xlQmcubCk7XG5cbiAgICByZXR1cm4ge2g6IGh4LCBzOiBzeCwgbDogbHgsIGF9O1xufVxuXG5jb25zdCBNQVhfQkdfTElHSFRORVNTID0gMC40O1xuXG5mdW5jdGlvbiBtb2RpZnlCZ0hTTCh7aCwgcywgbCwgYX06IEhTTEEsIHBvbGU6IEhTTEEpOiBIU0xBIHtcbiAgICBjb25zdCBpc0RhcmsgPSBsIDwgMC41O1xuICAgIGNvbnN0IGlzQmx1ZSA9IGggPiAyMDAgJiYgaCA8IDI4MDtcbiAgICBjb25zdCBpc05ldXRyYWwgPSBzIDwgMC4xMiB8fCAobCA+IDAuOCAmJiBpc0JsdWUpO1xuICAgIGlmIChpc0RhcmspIHtcbiAgICAgICAgY29uc3QgbHggPSBzY2FsZShsLCAwLCAwLjUsIDAsIE1BWF9CR19MSUdIVE5FU1MpO1xuICAgICAgICBpZiAoaXNOZXV0cmFsKSB7XG4gICAgICAgICAgICBjb25zdCBoeCA9IHBvbGUuaDtcbiAgICAgICAgICAgIGNvbnN0IHN4ID0gcG9sZS5zO1xuICAgICAgICAgICAgcmV0dXJuIHtoOiBoeCwgczogc3gsIGw6IGx4LCBhfTtcbiAgICAgICAgfVxuICAgICAgICByZXR1cm4ge2gsIHMsIGw6IGx4LCBhfTtcbiAgICB9XG5cbiAgICBsZXQgbHggPSBzY2FsZShsLCAwLjUsIDEsIE1BWF9CR19MSUdIVE5FU1MsIHBvbGUubCk7XG5cbiAgICBpZiAoaXNOZXV0cmFsKSB7XG4gICAgICAgIGNvbnN0IGh4ID0gcG9sZS5oO1xuICAgICAgICBjb25zdCBzeCA9IHBvbGUucztcbiAgICAgICAgcmV0dXJuIHtoOiBoeCwgczogc3gsIGw6IGx4LCBhfTtcbiAgICB9XG5cbiAgICBsZXQgaHggPSBoO1xuICAgIGNvbnN0IGlzWWVsbG93ID0gaCA+IDYwICYmIGggPCAxODA7XG4gICAgaWYgKGlzWWVsbG93KSB7XG4gICAgICAgIGNvbnN0IGlzQ2xvc2VyVG9HcmVlbiA9IGggPiAxMjA7XG4gICAgICAgIGlmIChpc0Nsb3NlclRvR3JlZW4pIHtcbiAgICAgICAgICAgIGh4ID0gc2NhbGUoaCwgMTIwLCAxODAsIDEzNSwgMTgwKTtcbiAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgIGh4ID0gc2NhbGUoaCwgNjAsIDEyMCwgNjAsIDEwNSk7XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICAvLyBMb3dlciB0aGUgbGlnaHRuZXNzLCBpZiB0aGUgcmVzdWx0aW5nXG4gICAgLy8gaHVlIGlzIGluIGxvd2VyIHllbGxvdyBzcGVjdHJ1bS5cbiAgICBpZiAoaHggPiA0MCAmJiBoeCA8IDgwKSB7XG4gICAgICAgIGx4ICo9IDAuNzU7XG4gICAgfVxuXG4gICAgcmV0dXJuIHtoOiBoeCwgcywgbDogbHgsIGF9O1xufVxuXG5mdW5jdGlvbiBfbW9kaWZ5QmFja2dyb3VuZENvbG9yKHJnYjogUkdCQSwgdGhlbWU6IFRoZW1lKSB7XG4gICAgaWYgKHRoZW1lLm1vZGUgPT09IDApIHtcbiAgICAgICAgaWYgKF9fUExVU19fKSB7XG4gICAgICAgICAgICBjb25zdCBwb2xlcyA9IGdldEJhY2tncm91bmRQb2xlcyh0aGVtZSk7XG4gICAgICAgICAgICByZXR1cm4gbW9kaWZ5Q29sb3JXaXRoQ2FjaGUocmdiLCB0aGVtZSwgbW9kaWZ5TGlnaHRTY2hlbWVDb2xvckV4dGVuZGVkLCBwb2xlc1swXSwgcG9sZXNbMV0pO1xuICAgICAgICB9XG4gICAgICAgIHJldHVybiBtb2RpZnlMaWdodFNjaGVtZUNvbG9yKHJnYiwgdGhlbWUpO1xuICAgIH1cbiAgICBpZiAoX19QTFVTX18pIHtcbiAgICAgICAgY29uc3QgcG9sZXMgPSBnZXRCYWNrZ3JvdW5kUG9sZXModGhlbWUpO1xuICAgICAgICByZXR1cm4gbW9kaWZ5Q29sb3JXaXRoQ2FjaGUocmdiLCB0aGVtZSwgbW9kaWZ5QmdDb2xvckV4dGVuZGVkLCBwb2xlc1swXSwgcG9sZXNbMV0pO1xuICAgIH1cbiAgICBjb25zdCBwb2xlID0gZ2V0QmdQb2xlKHRoZW1lKTtcbiAgICByZXR1cm4gbW9kaWZ5Q29sb3JXaXRoQ2FjaGUocmdiLCB0aGVtZSwgbW9kaWZ5QmdIU0wsIHBvbGUpO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gbW9kaWZ5QmFja2dyb3VuZENvbG9yKHJnYjogUkdCQSwgdGhlbWU6IFRoZW1lLCBzaG91bGRSZWdpc3RlckNvbG9yVmFyaWFibGUgPSB0cnVlKTogc3RyaW5nIHtcbiAgICBpZiAoIXNob3VsZFJlZ2lzdGVyQ29sb3JWYXJpYWJsZSkge1xuICAgICAgICByZXR1cm4gX21vZGlmeUJhY2tncm91bmRDb2xvcihyZ2IsIHRoZW1lKTtcbiAgICB9XG4gICAgcmV0dXJuIG1vZGlmeUFuZFJlZ2lzdGVyQ29sb3IoJ2JhY2tncm91bmQnLCByZ2IsIHRoZW1lLCBfbW9kaWZ5QmFja2dyb3VuZENvbG9yKTtcbn1cblxuY29uc3QgTUlOX0ZHX0xJR0hUTkVTUyA9IDAuNTU7XG5cbmZ1bmN0aW9uIG1vZGlmeUJsdWVGZ0h1ZShodWU6IG51bWJlcik6IG51bWJlciB7XG4gICAgcmV0dXJuIHNjYWxlKGh1ZSwgMjA1LCAyNDUsIDIwNSwgMjIwKTtcbn1cblxuZnVuY3Rpb24gbW9kaWZ5RmdIU0woe2gsIHMsIGwsIGF9OiBIU0xBLCBwb2xlOiBIU0xBKTogSFNMQSB7XG4gICAgY29uc3QgaXNMaWdodCA9IGwgPiAwLjU7XG4gICAgY29uc3QgaXNOZXV0cmFsID0gbCA8IDAuMiB8fCBzIDwgMC4yNDtcbiAgICBjb25zdCBpc0JsdWUgPSAhaXNOZXV0cmFsICYmIGggPiAyMDUgJiYgaCA8IDI0NTtcbiAgICBpZiAoaXNMaWdodCkge1xuICAgICAgICBjb25zdCBseCA9IHNjYWxlKGwsIDAuNSwgMSwgTUlOX0ZHX0xJR0hUTkVTUywgcG9sZS5sKTtcbiAgICAgICAgaWYgKGlzTmV1dHJhbCkge1xuICAgICAgICAgICAgY29uc3QgaHggPSBwb2xlLmg7XG4gICAgICAgICAgICBjb25zdCBzeCA9IHBvbGUucztcbiAgICAgICAgICAgIHJldHVybiB7aDogaHgsIHM6IHN4LCBsOiBseCwgYX07XG4gICAgICAgIH1cbiAgICAgICAgbGV0IGh4ID0gaDtcbiAgICAgICAgaWYgKGlzQmx1ZSkge1xuICAgICAgICAgICAgaHggPSBtb2RpZnlCbHVlRmdIdWUoaCk7XG4gICAgICAgIH1cbiAgICAgICAgcmV0dXJuIHtoOiBoeCwgcywgbDogbHgsIGF9O1xuICAgIH1cblxuICAgIGlmIChpc05ldXRyYWwpIHtcbiAgICAgICAgY29uc3QgaHggPSBwb2xlLmg7XG4gICAgICAgIGNvbnN0IHN4ID0gcG9sZS5zO1xuICAgICAgICBjb25zdCBseCA9IHNjYWxlKGwsIDAsIDAuNSwgcG9sZS5sLCBNSU5fRkdfTElHSFRORVNTKTtcbiAgICAgICAgcmV0dXJuIHtoOiBoeCwgczogc3gsIGw6IGx4LCBhfTtcbiAgICB9XG5cbiAgICBsZXQgaHggPSBoO1xuICAgIGxldCBseDogbnVtYmVyO1xuICAgIGlmIChpc0JsdWUpIHtcbiAgICAgICAgaHggPSBtb2RpZnlCbHVlRmdIdWUoaCk7XG4gICAgICAgIGx4ID0gc2NhbGUobCwgMCwgMC41LCBwb2xlLmwsIE1hdGgubWluKDEsIE1JTl9GR19MSUdIVE5FU1MgKyAwLjA1KSk7XG4gICAgfSBlbHNlIHtcbiAgICAgICAgbHggPSBzY2FsZShsLCAwLCAwLjUsIHBvbGUubCwgTUlOX0ZHX0xJR0hUTkVTUyk7XG4gICAgfVxuXG4gICAgcmV0dXJuIHtoOiBoeCwgcywgbDogbHgsIGF9O1xufVxuXG5mdW5jdGlvbiBfbW9kaWZ5Rm9yZWdyb3VuZENvbG9yKHJnYjogUkdCQSwgdGhlbWU6IFRoZW1lKSB7XG4gICAgaWYgKHRoZW1lLm1vZGUgPT09IDApIHtcbiAgICAgICAgaWYgKF9fUExVU19fKSB7XG4gICAgICAgICAgICBjb25zdCBwb2xlcyA9IGdldFRleHRQb2xlcyh0aGVtZSk7XG4gICAgICAgICAgICByZXR1cm4gbW9kaWZ5Q29sb3JXaXRoQ2FjaGUocmdiLCB0aGVtZSwgbW9kaWZ5TGlnaHRTY2hlbWVDb2xvckV4dGVuZGVkLCBwb2xlc1swXSwgcG9sZXNbMV0pO1xuICAgICAgICB9XG4gICAgICAgIHJldHVybiBtb2RpZnlMaWdodFNjaGVtZUNvbG9yKHJnYiwgdGhlbWUpO1xuICAgIH1cbiAgICBpZiAoX19QTFVTX18pIHtcbiAgICAgICAgY29uc3QgcG9sZXMgPSBnZXRUZXh0UG9sZXModGhlbWUpO1xuICAgICAgICByZXR1cm4gbW9kaWZ5Q29sb3JXaXRoQ2FjaGUocmdiLCB0aGVtZSwgbW9kaWZ5RmdDb2xvckV4dGVuZGVkLCBwb2xlc1swXSwgcG9sZXNbMV0pO1xuICAgIH1cbiAgICBjb25zdCBwb2xlID0gZ2V0RmdQb2xlKHRoZW1lKTtcbiAgICByZXR1cm4gbW9kaWZ5Q29sb3JXaXRoQ2FjaGUocmdiLCB0aGVtZSwgbW9kaWZ5RmdIU0wsIHBvbGUpO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gbW9kaWZ5Rm9yZWdyb3VuZENvbG9yKHJnYjogUkdCQSwgdGhlbWU6IFRoZW1lLCBzaG91bGRSZWdpc3RlckNvbG9yVmFyaWFibGUgPSB0cnVlKTogc3RyaW5nIHtcbiAgICBpZiAoIXNob3VsZFJlZ2lzdGVyQ29sb3JWYXJpYWJsZSkge1xuICAgICAgICByZXR1cm4gX21vZGlmeUZvcmVncm91bmRDb2xvcihyZ2IsIHRoZW1lKTtcbiAgICB9XG4gICAgcmV0dXJuIG1vZGlmeUFuZFJlZ2lzdGVyQ29sb3IoJ3RleHQnLCByZ2IsIHRoZW1lLCBfbW9kaWZ5Rm9yZWdyb3VuZENvbG9yKTtcbn1cblxuZnVuY3Rpb24gbW9kaWZ5Qm9yZGVySFNMKHtoLCBzLCBsLCBhfTogSFNMQSwgcG9sZUZnOiBIU0xBLCBwb2xlQmc6IEhTTEEpOiBIU0xBIHtcbiAgICBjb25zdCBpc0RhcmsgPSBsIDwgMC41O1xuICAgIGNvbnN0IGlzTmV1dHJhbCA9IGwgPCAwLjIgfHwgcyA8IDAuMjQ7XG5cbiAgICBsZXQgaHggPSBoO1xuICAgIGxldCBzeCA9IHM7XG5cbiAgICBpZiAoaXNOZXV0cmFsKSB7XG4gICAgICAgIGlmIChpc0RhcmspIHtcbiAgICAgICAgICAgIGh4ID0gcG9sZUZnLmg7XG4gICAgICAgICAgICBzeCA9IHBvbGVGZy5zO1xuICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgaHggPSBwb2xlQmcuaDtcbiAgICAgICAgICAgIHN4ID0gcG9sZUJnLnM7XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBjb25zdCBseCA9IHNjYWxlKGwsIDAsIDEsIDAuNSwgMC4yKTtcblxuICAgIHJldHVybiB7aDogaHgsIHM6IHN4LCBsOiBseCwgYX07XG59XG5cbmZ1bmN0aW9uIF9tb2RpZnlCb3JkZXJDb2xvcihyZ2I6IFJHQkEsIHRoZW1lOiBUaGVtZSkge1xuICAgIGlmICh0aGVtZS5tb2RlID09PSAwKSB7XG4gICAgICAgIHJldHVybiBtb2RpZnlMaWdodFNjaGVtZUNvbG9yKHJnYiwgdGhlbWUpO1xuICAgIH1cbiAgICBjb25zdCBwb2xlRmcgPSBnZXRGZ1BvbGUodGhlbWUpO1xuICAgIGNvbnN0IHBvbGVCZyA9IGdldEJnUG9sZSh0aGVtZSk7XG4gICAgcmV0dXJuIG1vZGlmeUNvbG9yV2l0aENhY2hlKHJnYiwgdGhlbWUsIG1vZGlmeUJvcmRlckhTTCwgcG9sZUZnLCBwb2xlQmcpO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gbW9kaWZ5Qm9yZGVyQ29sb3IocmdiOiBSR0JBLCB0aGVtZTogVGhlbWUsIHNob3VsZFJlZ2lzdGVyQ29sb3JWYXJpYWJsZSA9IHRydWUpOiBzdHJpbmcge1xuICAgIGlmICghc2hvdWxkUmVnaXN0ZXJDb2xvclZhcmlhYmxlKSB7XG4gICAgICAgIHJldHVybiBfbW9kaWZ5Qm9yZGVyQ29sb3IocmdiLCB0aGVtZSk7XG4gICAgfVxuICAgIHJldHVybiBtb2RpZnlBbmRSZWdpc3RlckNvbG9yKCdib3JkZXInLCByZ2IsIHRoZW1lLCBfbW9kaWZ5Qm9yZGVyQ29sb3IpO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gbW9kaWZ5U2hhZG93Q29sb3IocmdiOiBSR0JBLCB0aGVtZTogVGhlbWUpOiBzdHJpbmcge1xuICAgIHJldHVybiBtb2RpZnlCYWNrZ3JvdW5kQ29sb3IocmdiLCB0aGVtZSk7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBtb2RpZnlHcmFkaWVudENvbG9yKHJnYjogUkdCQSwgdGhlbWU6IFRoZW1lKTogc3RyaW5nIHtcbiAgICByZXR1cm4gbW9kaWZ5QmFja2dyb3VuZENvbG9yKHJnYiwgdGhlbWUpO1xufVxuIiwiaW1wb3J0IHR5cGUge1RoZW1lfSBmcm9tICcuLi9kZWZpbml0aW9ucyc7XG5pbXBvcnQge21vZGlmeUJhY2tncm91bmRDb2xvciwgbW9kaWZ5Rm9yZWdyb3VuZENvbG9yLCBtb2RpZnlCb3JkZXJDb2xvcn0gZnJvbSAnLi4vaW5qZWN0L2R5bmFtaWMtdGhlbWUvbW9kaWZ5LWNvbG9ycyc7XG5pbXBvcnQgdHlwZSB7UkdCQX0gZnJvbSAnLi4vdXRpbHMvY29sb3InO1xuaW1wb3J0IHtwYXJzZUNvbG9yV2l0aENhY2hlfSBmcm9tICcuLi91dGlscy9jb2xvcic7XG5cbi8vIFRPRE86IHJlbW92ZSB0eXBlIGFmdGVyIGRlcGVuZGVuY3kgdXBkYXRlXG5kZWNsYXJlIGNvbnN0IGJyb3dzZXI6IHtcbiAgICB0aGVtZToge1xuICAgICAgICB1cGRhdGU6ICgodGhlbWU6IGFueSkgPT4gUHJvbWlzZTx2b2lkPik7XG4gICAgICAgIHJlc2V0OiAoKCkgPT4gUHJvbWlzZTx2b2lkPik7XG4gICAgfTtcbn07XG5cbmNvbnN0IHRoZW1lQ29sb3JUeXBlczogeyBba2V5OiBzdHJpbmddOiAnYmcnIHwgJ3RleHQnIHwgJ2JvcmRlcicgfSA9IHtcbiAgICBhY2NlbnRjb2xvcjogJ2JnJyxcbiAgICBidXR0b25fYmFja2dyb3VuZF9hY3RpdmU6ICd0ZXh0JyxcbiAgICBidXR0b25fYmFja2dyb3VuZF9ob3ZlcjogJ3RleHQnLFxuICAgIGZyYW1lOiAnYmcnLFxuICAgIGljb25zOiAndGV4dCcsXG4gICAgaWNvbnNfYXR0ZW50aW9uOiAndGV4dCcsXG4gICAgbnRwX2JhY2tncm91bmQ6ICdiZycsXG4gICAgbnRwX3RleHQ6ICd0ZXh0JyxcbiAgICBwb3B1cDogJ2JnJyxcbiAgICBwb3B1cF9ib3JkZXI6ICdiZycsXG4gICAgcG9wdXBfaGlnaGxpZ2h0OiAnYmcnLFxuICAgIHBvcHVwX2hpZ2hsaWdodF90ZXh0OiAndGV4dCcsXG4gICAgcG9wdXBfdGV4dDogJ3RleHQnLFxuICAgIHNpZGViYXI6ICdiZycsXG4gICAgc2lkZWJhcl9ib3JkZXI6ICdib3JkZXInLFxuICAgIHNpZGViYXJfdGV4dDogJ3RleHQnLFxuICAgIHRhYl9iYWNrZ3JvdW5kX3RleHQ6ICd0ZXh0JyxcbiAgICB0YWJfbGluZTogJ2JnJyxcbiAgICB0YWJfbG9hZGluZzogJ2JnJyxcbiAgICB0YWJfc2VsZWN0ZWQ6ICdiZycsXG4gICAgdGV4dGNvbG9yOiAndGV4dCcsXG4gICAgdG9vbGJhcjogJ2JnJyxcbiAgICB0b29sYmFyX2JvdHRvbV9zZXBhcmF0b3I6ICdib3JkZXInLFxuICAgIHRvb2xiYXJfZmllbGQ6ICdiZycsXG4gICAgdG9vbGJhcl9maWVsZF9ib3JkZXI6ICdib3JkZXInLFxuICAgIHRvb2xiYXJfZmllbGRfYm9yZGVyX2ZvY3VzOiAnYm9yZGVyJyxcbiAgICB0b29sYmFyX2ZpZWxkX2ZvY3VzOiAnYmcnLFxuICAgIHRvb2xiYXJfZmllbGRfc2VwYXJhdG9yOiAnYm9yZGVyJyxcbiAgICB0b29sYmFyX2ZpZWxkX3RleHQ6ICd0ZXh0JyxcbiAgICB0b29sYmFyX2ZpZWxkX3RleHRfZm9jdXM6ICd0ZXh0JyxcbiAgICB0b29sYmFyX3RleHQ6ICd0ZXh0JyxcbiAgICB0b29sYmFyX3RvcF9zZXBhcmF0b3I6ICdib3JkZXInLFxuICAgIHRvb2xiYXJfdmVydGljYWxfc2VwYXJhdG9yOiAnYm9yZGVyJyxcbn07XG5cbmNvbnN0ICRjb2xvcnM6IHsgW2tleTogc3RyaW5nXTogc3RyaW5nIH0gPSB7XG4gICAgLy8gJ2FjY2VudGNvbG9yJyBpcyB0aGUgZGVwcmVjYXRlZCBwcmVkZWNlc3NvciBvZiAnZnJhbWUnLlxuICAgIC8vIGh0dHBzOi8vZGV2ZWxvcGVyLm1vemlsbGEub3JnL2VuLVVTL2RvY3MvTW96aWxsYS9BZGQtb25zL1dlYkV4dGVuc2lvbnMvbWFuaWZlc3QuanNvbi90aGVtZSNjb2xvcnNcbiAgICBhY2NlbnRjb2xvcjogJyMxMTExMTEnLFxuICAgIGZyYW1lOiAnIzExMTExMScsXG4gICAgbnRwX2JhY2tncm91bmQ6ICd3aGl0ZScsXG4gICAgbnRwX3RleHQ6ICdibGFjaycsXG4gICAgcG9wdXA6ICcjY2NjY2NjJyxcbiAgICBwb3B1cF90ZXh0OiAnYmxhY2snLFxuICAgIHNpZGViYXI6ICcjY2NjY2NjJyxcbiAgICBzaWRlYmFyX2JvcmRlcjogJyMzMzMnLFxuICAgIHNpZGViYXJfdGV4dDogJ2JsYWNrJyxcbiAgICB0YWJfYmFja2dyb3VuZF90ZXh0OiAnd2hpdGUnLFxuICAgIHRhYl9sb2FkaW5nOiAnIzIzYWVmZicsXG4gICAgLy8gJ3RleHRjb2xvcicgaXMgdGhlIHByZWRlY2Vzc29yIG9mICd0YWJfYmFja2dyb3VuZF90ZXh0Jy5cbiAgICAvLyBodHRwczovL2RldmVsb3Blci5tb3ppbGxhLm9yZy9lbi1VUy9kb2NzL01vemlsbGEvQWRkLW9ucy9XZWJFeHRlbnNpb25zL21hbmlmZXN0Lmpzb24vdGhlbWUjY29sb3JzXG4gICAgdGV4dGNvbG9yOiAnd2hpdGUnLFxuICAgIHRvb2xiYXI6ICcjNzA3MDcwJyxcbiAgICB0b29sYmFyX2ZpZWxkOiAnbGlnaHRncmF5JyxcbiAgICB0b29sYmFyX2ZpZWxkX3RleHQ6ICdibGFjaycsXG59O1xuXG5leHBvcnQgZnVuY3Rpb24gc2V0V2luZG93VGhlbWUodGhlbWU6IFRoZW1lKTogdm9pZCB7XG4gICAgY29uc3QgY29sb3JzID0gT2JqZWN0LmVudHJpZXMoJGNvbG9ycykucmVkdWNlKChvYmo6IHsgW2tleTogc3RyaW5nXTogc3RyaW5nIH0sIFtrZXksIHZhbHVlXSkgPT4ge1xuICAgICAgICBjb25zdCB0eXBlOiAnYmcnIHwgJ3RleHQnIHwgJ2JvcmRlcicgPSB0aGVtZUNvbG9yVHlwZXNba2V5XTtcbiAgICAgICAgY29uc3QgbW9kaWZ5OiAoKHJnYjogUkdCQSwgdGhlbWU6IFRoZW1lLCBzaG91bGRSZWdpc3RlcjogYm9vbGVhbikgPT4gc3RyaW5nKSA9IHtcbiAgICAgICAgICAgICdiZyc6IG1vZGlmeUJhY2tncm91bmRDb2xvcixcbiAgICAgICAgICAgICd0ZXh0JzogbW9kaWZ5Rm9yZWdyb3VuZENvbG9yLFxuICAgICAgICAgICAgJ2JvcmRlcic6IG1vZGlmeUJvcmRlckNvbG9yLFxuICAgICAgICB9W3R5cGVdO1xuICAgICAgICBjb25zdCByZ2IgPSBwYXJzZUNvbG9yV2l0aENhY2hlKHZhbHVlKSE7XG4gICAgICAgIGNvbnN0IG1vZGlmaWVkID0gbW9kaWZ5KHJnYiwgdGhlbWUsIGZhbHNlKTtcbiAgICAgICAgb2JqW2tleV0gPSBtb2RpZmllZDtcbiAgICAgICAgcmV0dXJuIG9iajtcbiAgICB9LCB7fSk7XG4gICAgaWYgKHR5cGVvZiBicm93c2VyICE9PSAndW5kZWZpbmVkJyAmJiBicm93c2VyLnRoZW1lICYmIGJyb3dzZXIudGhlbWUudXBkYXRlKSB7XG4gICAgICAgIGJyb3dzZXIudGhlbWUudXBkYXRlKHtjb2xvcnN9KTtcbiAgICB9XG59XG5cbmV4cG9ydCBmdW5jdGlvbiByZXNldFdpbmRvd1RoZW1lKCk6IHZvaWQge1xuICAgIGlmICh0eXBlb2YgYnJvd3NlciAhPT0gJ3VuZGVmaW5lZCcgJiYgYnJvd3Nlci50aGVtZSAmJiBicm93c2VyLnRoZW1lLnJlc2V0KSB7XG4gICAgICAgIC8vIEJVRzogcmVzZXRzIGJyb3dzZXIgdGhlbWUgdG8gZW50aXJlXG4gICAgICAgIC8vIGh0dHBzOi8vYnVnemlsbGEubW96aWxsYS5vcmcvc2hvd19idWcuY2dpP2lkPTE0MTUyNjdcbiAgICAgICAgYnJvd3Nlci50aGVtZS5yZXNldCgpO1xuICAgIH1cbn1cbiIsImltcG9ydCB0eXBlIHtFeHRlbnNpb25EYXRhLCBUaGVtZSwgU2hvcnRjdXRzLCBVc2VyU2V0dGluZ3MsIFRhYkluZm8sIFRhYkRhdGEsIENvbW1hbmQsIERldlRvb2xzRGF0YX0gZnJvbSAnLi4vZGVmaW5pdGlvbnMnO1xuaW1wb3J0IGNyZWF0ZUNTU0ZpbHRlclN0eWxlc2hlZXQgZnJvbSAnLi4vZ2VuZXJhdG9ycy9jc3MtZmlsdGVyJztcbmltcG9ydCB7Z2V0RGV0ZWN0b3JIaW50c0Zvcn0gZnJvbSAnLi4vZ2VuZXJhdG9ycy9kZXRlY3Rvci1oaW50cyc7XG5pbXBvcnQge2dldER5bmFtaWNUaGVtZUZpeGVzRm9yfSBmcm9tICcuLi9nZW5lcmF0b3JzL2R5bmFtaWMtdGhlbWUnO1xuaW1wb3J0IGNyZWF0ZVN0YXRpY1N0eWxlc2hlZXQgZnJvbSAnLi4vZ2VuZXJhdG9ycy9zdGF0aWMtdGhlbWUnO1xuaW1wb3J0IHtjcmVhdGVTVkdGaWx0ZXJTdHlsZXNoZWV0LCBnZXRTVkdGaWx0ZXJNYXRyaXhWYWx1ZSwgZ2V0U1ZHUmV2ZXJzZUZpbHRlck1hdHJpeFZhbHVlfSBmcm9tICcuLi9nZW5lcmF0b3JzL3N2Zy1maWx0ZXInO1xuaW1wb3J0IHtUaGVtZUVuZ2luZX0gZnJvbSAnLi4vZ2VuZXJhdG9ycy90aGVtZS1lbmdpbmVzJztcbmltcG9ydCB7QXV0b21hdGlvbk1vZGV9IGZyb20gJy4uL3V0aWxzL2F1dG9tYXRpb24nO1xuaW1wb3J0IHtkZWJvdW5jZX0gZnJvbSAnLi4vdXRpbHMvZGVib3VuY2UnO1xuaW1wb3J0IHtpc1N5c3RlbURhcmtNb2RlRW5hYmxlZCwgcnVuQ29sb3JTY2hlbWVDaGFuZ2VEZXRlY3Rvcn0gZnJvbSAnLi4vdXRpbHMvbWVkaWEtcXVlcnknO1xuaW1wb3J0IHtNZXNzYWdlVHlwZUJHdG9DU30gZnJvbSAnLi4vdXRpbHMvbWVzc2FnZSc7XG5pbXBvcnQge2lzRmlyZWZveH0gZnJvbSAnLi4vdXRpbHMvcGxhdGZvcm0nO1xuaW1wb3J0IHtQcm9taXNlQmFycmllcn0gZnJvbSAnLi4vdXRpbHMvcHJvbWlzZS1iYXJyaWVyJztcbmltcG9ydCB7U3RhdGVNYW5hZ2VyfSBmcm9tICcuLi91dGlscy9zdGF0ZS1tYW5hZ2VyJztcbmltcG9ydCB7Z2V0QWN0aXZlVGFifSBmcm9tICcuLi91dGlscy90YWJzJztcbmltcG9ydCB7aXNJblRpbWVJbnRlcnZhbExvY2FsLCBuZXh0VGltZUludGVydmFsLCBpc05pZ2h0QXRMb2NhdGlvbiwgbmV4dFRpbWVDaGFuZ2VBdExvY2F0aW9uLCBnZXREdXJhdGlvbn0gZnJvbSAnLi4vdXRpbHMvdGltZSc7XG5pbXBvcnQge2lzVVJMSW5MaXN0LCBnZXRVUkxIb3N0T3JQcm90b2NvbCwgaXNVUkxFbmFibGVkLCBpc1BERn0gZnJvbSAnLi4vdXRpbHMvdXJsJztcblxuaW1wb3J0IENvbmZpZ01hbmFnZXIgZnJvbSAnLi9jb25maWctbWFuYWdlcic7XG5pbXBvcnQgRGV2VG9vbHMgZnJvbSAnLi9kZXZ0b29scyc7XG5pbXBvcnQgSWNvbk1hbmFnZXIgZnJvbSAnLi9pY29uLW1hbmFnZXInO1xuaW1wb3J0IHR5cGUge0V4dGVuc2lvbkFkYXB0ZXJ9IGZyb20gJy4vbWVzc2VuZ2VyJztcbmltcG9ydCBNZXNzZW5nZXIgZnJvbSAnLi9tZXNzZW5nZXInO1xuaW1wb3J0IE5ld3NtYWtlciBmcm9tICcuL25ld3NtYWtlcic7XG5pbXBvcnQgVGFiTWFuYWdlciBmcm9tICcuL3RhYi1tYW5hZ2VyJztcbmltcG9ydCBVSUhpZ2hsaWdodHMgZnJvbSAnLi91aS1oaWdobGlnaHRzJztcbmltcG9ydCBVc2VyU3RvcmFnZSBmcm9tICcuL3VzZXItc3RvcmFnZSc7XG5pbXBvcnQge2dldENvbW1hbmRzLCBjYW5JbmplY3RTY3JpcHQsIHdyaXRlTG9jYWxTdG9yYWdlLCByZW1vdmVMb2NhbFN0b3JhZ2V9IGZyb20gJy4vdXRpbHMvZXh0ZW5zaW9uLWFwaSc7XG5pbXBvcnQge2xvZ0luZm8sIGxvZ1dhcm59IGZyb20gJy4vdXRpbHMvbG9nJztcbmltcG9ydCB7c2V0V2luZG93VGhlbWUsIHJlc2V0V2luZG93VGhlbWV9IGZyb20gJy4vd2luZG93LXRoZW1lJztcblxuXG50eXBlIEF1dG9tYXRpb25TdGF0ZSA9ICd0dXJuLW9uJyB8ICd0dXJuLW9mZicgfCAnc2NoZW1lLWRhcmsnIHwgJ3NjaGVtZS1saWdodCcgfCAnJztcblxuaW50ZXJmYWNlIEV4dGVuc2lvblN0YXRlIGV4dGVuZHMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4ge1xuICAgIGF1dG9TdGF0ZTogQXV0b21hdGlvblN0YXRlO1xuICAgIHdhc0VuYWJsZWRPbkxhc3RDaGVjazogYm9vbGVhbiB8IG51bGw7XG4gICAgcmVnaXN0ZXJlZENvbnRleHRNZW51czogYm9vbGVhbiB8IG51bGw7XG59XG5cbmludGVyZmFjZSBTeXN0ZW1Db2xvclN0YXRlIGV4dGVuZHMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4ge1xuICAgIHdhc0xhc3RDb2xvclNjaGVtZURhcms6IGJvb2xlYW4gfCBudWxsO1xufVxuXG5kZWNsYXJlIGNvbnN0IF9fQ0hST01JVU1fTVYyX186IGJvb2xlYW47XG5kZWNsYXJlIGNvbnN0IF9fQ0hST01JVU1fTVYzX186IGJvb2xlYW47XG5kZWNsYXJlIGNvbnN0IF9fUExVU19fOiBib29sZWFuO1xuZGVjbGFyZSBjb25zdCBfX1RIVU5ERVJCSVJEX186IGJvb2xlYW47XG5cbmV4cG9ydCBjbGFzcyBFeHRlbnNpb24ge1xuICAgIHByaXZhdGUgc3RhdGljIGF1dG9TdGF0ZTogQXV0b21hdGlvblN0YXRlID0gJyc7XG4gICAgcHJpdmF0ZSBzdGF0aWMgd2FzRW5hYmxlZE9uTGFzdENoZWNrOiBib29sZWFuIHwgbnVsbCA9IG51bGw7XG4gICAgcHJpdmF0ZSBzdGF0aWMgcmVnaXN0ZXJlZENvbnRleHRNZW51czogYm9vbGVhbiB8IG51bGwgPSBudWxsO1xuICAgIC8qKlxuICAgICAqIFRoaXMgdmFsdWUgaXMgdXNlZCBmb3IgdHdvIHB1cnBvc2VzOlxuICAgICAqICAtIHRvIGJ5cGFzcyBGaXJlZm94IGJ1Z1xuICAgICAqICAtIHRvIGZpbHRlciBvdXQgZXhjZXNzaXZlIEV4dGVuc2lvbi5vbkNvbG9yU2NoZW1lQ2hhbmdlKCkgaW52b2NhdGlvbnNcbiAgICAgKi9cbiAgICBwcml2YXRlIHN0YXRpYyB3YXNMYXN0Q29sb3JTY2hlbWVEYXJrOiBib29sZWFuIHwgbnVsbCA9IG51bGw7XG4gICAgcHJpdmF0ZSBzdGF0aWMgc3RhcnRCYXJyaWVyOiBQcm9taXNlQmFycmllcjx2b2lkLCB2b2lkPiB8IG51bGwgPSBudWxsO1xuICAgIHByaXZhdGUgc3RhdGljIHN0YXRlTWFuYWdlcjogU3RhdGVNYW5hZ2VyPEV4dGVuc2lvblN0YXRlPiB8IG51bGwgPSBudWxsO1xuXG4gICAgcHJpdmF0ZSBzdGF0aWMgcmVhZG9ubHkgQUxBUk1fTkFNRSA9ICdhdXRvLXRpbWUtYWxhcm0nO1xuICAgIHByaXZhdGUgc3RhdGljIHJlYWRvbmx5IExPQ0FMX1NUT1JBR0VfS0VZID0gJ0V4dGVuc2lvbi1zdGF0ZSc7XG5cbiAgICAvLyBTdG9yZSBzeXN0ZW0gY29sb3IgdGhlbWVcbiAgICBwcml2YXRlIHN0YXRpYyByZWFkb25seSBTWVNURU1fQ09MT1JfTE9DQUxfU1RPUkFHRV9LRVkgPSAnc3lzdGVtLWNvbG9yLXN0YXRlJztcbiAgICBwcml2YXRlIHN0YXRpYyBzeXN0ZW1Db2xvclN0YXRlTWFuYWdlcjogU3RhdGVNYW5hZ2VyPFN5c3RlbUNvbG9yU3RhdGU+O1xuXG4gICAgLy8gUmVjb3JkIHdoZXRoZXIgRXh0ZW5zaW9uLmluaXQoKSBhbHJlYWR5IHJhbiBzaW5jZSB0aGUgbGFzdCBHQiBzdGFydFxuICAgIHByaXZhdGUgc3RhdGljIGluaXRpYWxpemVkID0gZmFsc2U7XG5cbiAgICBzdGF0aWMgaXNGaXJzdExvYWQgPSBmYWxzZTtcblxuICAgIC8vIFRoaXMgc3luYyBpbml0aWFsaXplciBuZWVkcyB0byBydW4gb24gZXZlcnkgQkcgcmVzdGFydCBiZWZvcmUgYW55dGhpbmcgZWxzZSBjYW4gaGFwcGVuXG4gICAgcHJpdmF0ZSBzdGF0aWMgaW5pdCgpIHtcbiAgICAgICAgaWYgKEV4dGVuc2lvbi5pbml0aWFsaXplZCkge1xuICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICB9XG4gICAgICAgIEV4dGVuc2lvbi5pbml0aWFsaXplZCA9IHRydWU7XG5cbiAgICAgICAgRGV2VG9vbHMuaW5pdChFeHRlbnNpb24ub25TZXR0aW5nc0NoYW5nZWQpO1xuICAgICAgICBNZXNzZW5nZXIuaW5pdChFeHRlbnNpb24uZ2V0TWVzc2VuZ2VyQWRhcHRlcigpKTtcbiAgICAgICAgVGFiTWFuYWdlci5pbml0KHtcbiAgICAgICAgICAgIGdldENvbm5lY3Rpb25NZXNzYWdlOiBFeHRlbnNpb24uZ2V0Q29ubmVjdGlvbk1lc3NhZ2UsXG4gICAgICAgICAgICBnZXRUYWJNZXNzYWdlOiBFeHRlbnNpb24uZ2V0VGFiTWVzc2FnZSxcbiAgICAgICAgICAgIG9uQ29sb3JTY2hlbWVDaGFuZ2U6IEV4dGVuc2lvbi5vbkNvbG9yU2NoZW1lQ2hhbmdlLFxuICAgICAgICB9KTtcblxuICAgICAgICBFeHRlbnNpb24uc3RhcnRCYXJyaWVyID0gbmV3IFByb21pc2VCYXJyaWVyKCk7XG4gICAgICAgIEV4dGVuc2lvbi5zdGF0ZU1hbmFnZXIgPSBuZXcgU3RhdGVNYW5hZ2VyPEV4dGVuc2lvblN0YXRlPihFeHRlbnNpb24uTE9DQUxfU1RPUkFHRV9LRVksIEV4dGVuc2lvbiwge1xuICAgICAgICAgICAgYXV0b1N0YXRlOiAnJyxcbiAgICAgICAgICAgIHdhc0VuYWJsZWRPbkxhc3RDaGVjazogbnVsbCxcbiAgICAgICAgICAgIHJlZ2lzdGVyZWRDb250ZXh0TWVudXM6IG51bGwsXG4gICAgICAgIH0sIGxvZ1dhcm4pO1xuXG4gICAgICAgIGNocm9tZS5hbGFybXMub25BbGFybS5hZGRMaXN0ZW5lcihFeHRlbnNpb24uYWxhcm1MaXN0ZW5lcik7XG5cbiAgICAgICAgaWYgKGNocm9tZS5jb21tYW5kcykge1xuICAgICAgICAgICAgLy8gRmlyZWZveCBBbmRyb2lkIGRvZXMgbm90IHN1cHBvcnQgY2hyb21lLmNvbW1hbmRzXG4gICAgICAgICAgICBpZiAoaXNGaXJlZm94KSB7XG4gICAgICAgICAgICAgICAgLy8gRmlyZWZveCBtYXkgbm90IHJlZ2lzdGVyIG9uQ29tbWFuZCBsaXN0ZW5lciBvbiBleHRlbnNpb24gc3RhcnR1cCBzbyB3ZSBuZWVkIHRvIHVzZSBzZXRUaW1lb3V0XG4gICAgICAgICAgICAgICAgc2V0VGltZW91dCgoKSA9PiBjaHJvbWUuY29tbWFuZHMub25Db21tYW5kLmFkZExpc3RlbmVyKGFzeW5jIChjb21tYW5kKSA9PiBFeHRlbnNpb24ub25Db21tYW5kKGNvbW1hbmQgYXMgQ29tbWFuZCwgbnVsbCwgbnVsbCwgbnVsbCkpKTtcbiAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgY2hyb21lLmNvbW1hbmRzLm9uQ29tbWFuZC5hZGRMaXN0ZW5lcihhc3luYyAoY29tbWFuZCwgdGFiKSA9PiBFeHRlbnNpb24ub25Db21tYW5kKGNvbW1hbmQgYXMgQ29tbWFuZCwgdGFiICYmIHRhYi5pZCEgfHwgbnVsbCwgMCwgbnVsbCkpO1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG5cbiAgICAgICAgaWYgKGNocm9tZS5wZXJtaXNzaW9ucy5vblJlbW92ZWQpIHtcbiAgICAgICAgICAgIGNocm9tZS5wZXJtaXNzaW9ucy5vblJlbW92ZWQuYWRkTGlzdGVuZXIoKHBlcm1pc3Npb25zKSA9PiB7XG4gICAgICAgICAgICAgICAgLy8gQXMgZmFyIGFzIHdlIGtub3csIHRoaXMgY29kZSBpcyBuZXZlciBhY3R1YWxseSBydW4gYmVjYXVzZSB0aGVyZVxuICAgICAgICAgICAgICAgIC8vIGlzIG5vIGJyb3dzZXIgVUkgZm9yIHJlbW92aW5nICdjb250ZXh0TWVudXMnIHBlcm1pc3Npb24uXG4gICAgICAgICAgICAgICAgLy8gVGhpcyBjb2RlIGV4aXN0cyBmb3IgZnV0dXJlLXByb29maW5nIGluIGNhc2UgYnJvd3NlcnMgZXZlciBhZGQgc3VjaCBVSS5cbiAgICAgICAgICAgICAgICBpZiAoIXBlcm1pc3Npb25zPy5wZXJtaXNzaW9ucz8uaW5jbHVkZXMoJ2NvbnRleHRNZW51cycpKSB7XG4gICAgICAgICAgICAgICAgICAgIEV4dGVuc2lvbi5yZWdpc3RlcmVkQ29udGV4dE1lbnVzID0gZmFsc2U7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSk7XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBhc3luYyBNVjNzeW5jU3lzdGVtQ29sb3JTdGF0ZU1hbmFnZXIoaXNEYXJrOiBib29sZWFuIHwgbnVsbCk6IFByb21pc2U8dm9pZD4ge1xuICAgICAgICBpZiAoIV9fQ0hST01JVU1fTVYzX18pIHtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuICAgICAgICBpZiAoIUV4dGVuc2lvbi5zeXN0ZW1Db2xvclN0YXRlTWFuYWdlcikge1xuICAgICAgICAgICAgRXh0ZW5zaW9uLnN5c3RlbUNvbG9yU3RhdGVNYW5hZ2VyID0gbmV3IFN0YXRlTWFuYWdlcjxTeXN0ZW1Db2xvclN0YXRlPihFeHRlbnNpb24uU1lTVEVNX0NPTE9SX0xPQ0FMX1NUT1JBR0VfS0VZLCBFeHRlbnNpb24sIHtcbiAgICAgICAgICAgICAgICB3YXNMYXN0Q29sb3JTY2hlbWVEYXJrOiBpc0RhcmssXG4gICAgICAgICAgICB9LCBsb2dXYXJuKTtcbiAgICAgICAgfVxuICAgICAgICBpZiAoaXNEYXJrID09PSBudWxsKSB7XG4gICAgICAgICAgICAvLyBBdHRlbXB0IHRvIHJlc3RvcmUgZGF0YSBmcm9tIHN0b3JhZ2VcbiAgICAgICAgICAgIHJldHVybiBFeHRlbnNpb24uc3lzdGVtQ29sb3JTdGF0ZU1hbmFnZXIubG9hZFN0YXRlKCk7XG4gICAgICAgIH0gZWxzZSBpZiAoRXh0ZW5zaW9uLndhc0xhc3RDb2xvclNjaGVtZURhcmsgIT09IGlzRGFyaykge1xuICAgICAgICAgICAgRXh0ZW5zaW9uLndhc0xhc3RDb2xvclNjaGVtZURhcmsgPSBpc0Rhcms7XG4gICAgICAgICAgICByZXR1cm4gRXh0ZW5zaW9uLnN5c3RlbUNvbG9yU3RhdGVNYW5hZ2VyLnNhdmVTdGF0ZSgpO1xuICAgICAgICB9XG4gICAgfVxuXG4gICAgcHJpdmF0ZSBzdGF0aWMgYWxhcm1MaXN0ZW5lciA9IChhbGFybTogY2hyb21lLmFsYXJtcy5BbGFybSk6IHZvaWQgPT4ge1xuICAgICAgICBpZiAoYWxhcm0ubmFtZSA9PT0gRXh0ZW5zaW9uLkFMQVJNX05BTUUpIHtcbiAgICAgICAgICAgIEV4dGVuc2lvbi5sb2FkRGF0YSgpLnRoZW4oKCkgPT4gRXh0ZW5zaW9uLmhhbmRsZUF1dG9tYXRpb25DaGVjaygpKTtcbiAgICAgICAgfVxuICAgIH07XG5cbiAgICBwcml2YXRlIHN0YXRpYyBpc0V4dGVuc2lvblN3aXRjaGVkT24oKSB7XG4gICAgICAgIHJldHVybiAoXG4gICAgICAgICAgICBFeHRlbnNpb24uYXV0b1N0YXRlID09PSAndHVybi1vbicgfHxcbiAgICAgICAgICAgIEV4dGVuc2lvbi5hdXRvU3RhdGUgPT09ICdzY2hlbWUtZGFyaycgfHxcbiAgICAgICAgICAgIEV4dGVuc2lvbi5hdXRvU3RhdGUgPT09ICdzY2hlbWUtbGlnaHQnIHx8XG4gICAgICAgICAgICAoRXh0ZW5zaW9uLmF1dG9TdGF0ZSA9PT0gJycgJiYgVXNlclN0b3JhZ2Uuc2V0dGluZ3MuZW5hYmxlZClcbiAgICAgICAgKTtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyB1cGRhdGVBdXRvU3RhdGUoKSB7XG4gICAgICAgIGNvbnN0IHttb2RlLCBiZWhhdmlvciwgZW5hYmxlZH0gPSBVc2VyU3RvcmFnZS5zZXR0aW5ncy5hdXRvbWF0aW9uO1xuXG4gICAgICAgIGxldCBpc0F1dG9EYXJrOiBib29sZWFuIHwgbnVsbCB8IHVuZGVmaW5lZDtcbiAgICAgICAgbGV0IG5leHRDaGVjazogbnVtYmVyIHwgbnVsbCB8IHVuZGVmaW5lZDtcbiAgICAgICAgc3dpdGNoIChtb2RlKSB7XG4gICAgICAgICAgICBjYXNlIEF1dG9tYXRpb25Nb2RlLlRJTUU6IHtcbiAgICAgICAgICAgICAgICBjb25zdCB7dGltZX0gPSBVc2VyU3RvcmFnZS5zZXR0aW5ncztcbiAgICAgICAgICAgICAgICBpc0F1dG9EYXJrID0gaXNJblRpbWVJbnRlcnZhbExvY2FsKHRpbWUuYWN0aXZhdGlvbiwgdGltZS5kZWFjdGl2YXRpb24pO1xuICAgICAgICAgICAgICAgIG5leHRDaGVjayA9IG5leHRUaW1lSW50ZXJ2YWwodGltZS5hY3RpdmF0aW9uLCB0aW1lLmRlYWN0aXZhdGlvbik7XG4gICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICBjYXNlIEF1dG9tYXRpb25Nb2RlLlNZU1RFTTpcbiAgICAgICAgICAgICAgICBpZiAoX19DSFJPTUlVTV9NVjNfXykge1xuICAgICAgICAgICAgICAgICAgICBpc0F1dG9EYXJrID0gRXh0ZW5zaW9uLndhc0xhc3RDb2xvclNjaGVtZURhcms7XG4gICAgICAgICAgICAgICAgICAgIGlmIChFeHRlbnNpb24ud2FzTGFzdENvbG9yU2NoZW1lRGFyayA9PT0gbnVsbCkge1xuICAgICAgICAgICAgICAgICAgICAgICAgbG9nV2FybignU3lzdGVtIGNvbG9yIHNjaGVtZSBpcyB1bmtub3duLiBEZWZhdWx0aW5nIHRvIERhcmsuJyk7XG4gICAgICAgICAgICAgICAgICAgICAgICBpc0F1dG9EYXJrID0gdHJ1ZTtcbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgaXNBdXRvRGFyayA9IEV4dGVuc2lvbi53YXNMYXN0Q29sb3JTY2hlbWVEYXJrID09PSBudWxsXG4gICAgICAgICAgICAgICAgICAgID8gaXNTeXN0ZW1EYXJrTW9kZUVuYWJsZWQoKVxuICAgICAgICAgICAgICAgICAgICA6IEV4dGVuc2lvbi53YXNMYXN0Q29sb3JTY2hlbWVEYXJrO1xuICAgICAgICAgICAgICAgIGlmIChpc0ZpcmVmb3gpIHtcbiAgICAgICAgICAgICAgICAgICAgcnVuQ29sb3JTY2hlbWVDaGFuZ2VEZXRlY3RvcihFeHRlbnNpb24ub25Db2xvclNjaGVtZUNoYW5nZSk7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgY2FzZSBBdXRvbWF0aW9uTW9kZS5MT0NBVElPTjoge1xuICAgICAgICAgICAgICAgIGNvbnN0IHtsYXRpdHVkZSwgbG9uZ2l0dWRlfSA9IFVzZXJTdG9yYWdlLnNldHRpbmdzLmxvY2F0aW9uO1xuICAgICAgICAgICAgICAgIGlmIChsYXRpdHVkZSAhPSBudWxsICYmIGxvbmdpdHVkZSAhPSBudWxsKSB7XG4gICAgICAgICAgICAgICAgICAgIGlzQXV0b0RhcmsgPSBpc05pZ2h0QXRMb2NhdGlvbihsYXRpdHVkZSwgbG9uZ2l0dWRlKTtcbiAgICAgICAgICAgICAgICAgICAgbmV4dENoZWNrID0gbmV4dFRpbWVDaGFuZ2VBdExvY2F0aW9uKGxhdGl0dWRlLCBsb25naXR1ZGUpO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGNhc2UgQXV0b21hdGlvbk1vZGUuTk9ORTpcbiAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgfVxuXG4gICAgICAgIGxldCBzdGF0ZTogQXV0b21hdGlvblN0YXRlID0gJyc7XG4gICAgICAgIGlmIChlbmFibGVkKSB7XG4gICAgICAgICAgICBpZiAoYmVoYXZpb3IgPT09ICdPbk9mZicpIHtcbiAgICAgICAgICAgICAgICBzdGF0ZSA9IGlzQXV0b0RhcmsgPyAndHVybi1vbicgOiAndHVybi1vZmYnO1xuICAgICAgICAgICAgfSBlbHNlIGlmIChiZWhhdmlvciA9PT0gJ1NjaGVtZScpIHtcbiAgICAgICAgICAgICAgICBzdGF0ZSA9IGlzQXV0b0RhcmsgPyAnc2NoZW1lLWRhcmsnIDogJ3NjaGVtZS1saWdodCc7XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgICAgRXh0ZW5zaW9uLmF1dG9TdGF0ZSA9IHN0YXRlO1xuXG4gICAgICAgIGlmIChuZXh0Q2hlY2spIHtcbiAgICAgICAgICAgIGlmIChuZXh0Q2hlY2sgPCBEYXRlLm5vdygpKSB7XG4gICAgICAgICAgICAgICAgbG9nV2FybihgQWxhcm0gaXMgc2V0IGluIHRoZSBwYXN0OiAke25leHRDaGVja30uIFRoZSB0aW1lIGlzOiAke25ldyBEYXRlKCl9LiBJU086ICR7KG5ldyBEYXRlKCkpLnRvSVNPU3RyaW5nKCl9YCk7XG4gICAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgICAgIGNocm9tZS5hbGFybXMuY3JlYXRlKEV4dGVuc2lvbi5BTEFSTV9OQU1FLCB7d2hlbjogbmV4dENoZWNrfSk7XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyB3YWtlSW50ZXJ2YWw6IG51bWJlciA9IC0xO1xuXG4gICAgcHJpdmF0ZSBzdGF0aWMgcnVuV2FrZURldGVjdG9yKCkge1xuICAgICAgICBjb25zdCBXQUtFX0NIRUNLX0lOVEVSVkFMID0gZ2V0RHVyYXRpb24oe21pbnV0ZXM6IDF9KTtcbiAgICAgICAgY29uc3QgV0FLRV9DSEVDS19JTlRFUlZBTF9FUlJPUiA9IGdldER1cmF0aW9uKHtzZWNvbmRzOiAxMH0pO1xuICAgICAgICBpZiAodGhpcy53YWtlSW50ZXJ2YWwgPj0gMCkge1xuICAgICAgICAgICAgY2xlYXJJbnRlcnZhbCh0aGlzLndha2VJbnRlcnZhbCk7XG4gICAgICAgIH1cblxuICAgICAgICBsZXQgbGFzdFJ1biA9IERhdGUubm93KCk7XG4gICAgICAgIHRoaXMud2FrZUludGVydmFsID0gc2V0SW50ZXJ2YWwoKCkgPT4ge1xuICAgICAgICAgICAgY29uc3Qgbm93ID0gRGF0ZS5ub3coKTtcbiAgICAgICAgICAgIGlmIChub3cgLSBsYXN0UnVuID4gV0FLRV9DSEVDS19JTlRFUlZBTCArIFdBS0VfQ0hFQ0tfSU5URVJWQUxfRVJST1IpIHtcbiAgICAgICAgICAgICAgICBFeHRlbnNpb24uaGFuZGxlQXV0b21hdGlvbkNoZWNrKCk7XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICBsYXN0UnVuID0gbm93O1xuICAgICAgICB9LCBXQUtFX0NIRUNLX0lOVEVSVkFMKTtcbiAgICB9XG5cbiAgICBzdGF0aWMgYXN5bmMgc3RhcnQoKTogUHJvbWlzZTx2b2lkPiB7XG4gICAgICAgIEV4dGVuc2lvbi5pbml0KCk7XG4gICAgICAgIGF3YWl0IFRhYk1hbmFnZXIuY2xlYW5TdGF0ZSgpO1xuICAgICAgICBhd2FpdCBQcm9taXNlLmFsbChbXG4gICAgICAgICAgICBDb25maWdNYW5hZ2VyLmxvYWQoe2xvY2FsOiB0cnVlfSksXG4gICAgICAgICAgICBFeHRlbnNpb24uTVYzc3luY1N5c3RlbUNvbG9yU3RhdGVNYW5hZ2VyKG51bGwpLFxuICAgICAgICAgICAgVXNlclN0b3JhZ2UubG9hZFNldHRpbmdzKCksXG4gICAgICAgIF0pO1xuXG4gICAgICAgIGlmIChVc2VyU3RvcmFnZS5zZXR0aW5ncy5lbmFibGVDb250ZXh0TWVudXMgJiYgIUV4dGVuc2lvbi5yZWdpc3RlcmVkQ29udGV4dE1lbnVzKSB7XG4gICAgICAgICAgICBjaHJvbWUucGVybWlzc2lvbnMuY29udGFpbnMoe3Blcm1pc3Npb25zOiBbJ2NvbnRleHRNZW51cyddfSwgKHBlcm1pdHRlZCkgPT4ge1xuICAgICAgICAgICAgICAgIGlmIChwZXJtaXR0ZWQpIHtcbiAgICAgICAgICAgICAgICAgICAgRXh0ZW5zaW9uLnJlZ2lzdGVyQ29udGV4dE1lbnVzKCk7XG4gICAgICAgICAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgICAgICAgICAgbG9nV2FybignVXNlciBoYXMgZW5hYmxlZCBjb250ZXh0IG1lbnVzLCBidXQgZGlkIG5vdCBwcm92aWRlIHBlcm1pc3Npb24uJyk7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSk7XG4gICAgICAgIH1cbiAgICAgICAgaWYgKFVzZXJTdG9yYWdlLnNldHRpbmdzLnN5bmNTaXRlc0ZpeGVzKSB7XG4gICAgICAgICAgICBhd2FpdCBDb25maWdNYW5hZ2VyLmxvYWQoe2xvY2FsOiBmYWxzZX0pO1xuICAgICAgICB9XG4gICAgICAgIEV4dGVuc2lvbi51cGRhdGVBdXRvU3RhdGUoKTtcbiAgICAgICAgRXh0ZW5zaW9uLnJ1bldha2VEZXRlY3RvcigpO1xuICAgICAgICBFeHRlbnNpb24ub25BcHBUb2dnbGUoKTtcbiAgICAgICAgbG9nSW5mbygnbG9hZGVkJywgVXNlclN0b3JhZ2Uuc2V0dGluZ3MpO1xuXG4gICAgICAgIGlmIChfX1RIVU5ERVJCSVJEX18pIHtcbiAgICAgICAgICAgIFRhYk1hbmFnZXIucmVnaXN0ZXJNYWlsRGlzcGxheVNjcmlwdCgpO1xuICAgICAgICB9IGVsc2UgaWYgKCFfX0NIUk9NSVVNX01WM19fIHx8IEV4dGVuc2lvbi5pc0ZpcnN0TG9hZCkge1xuICAgICAgICAgICAgVGFiTWFuYWdlci51cGRhdGVDb250ZW50U2NyaXB0KHtydW5PblByb3RlY3RlZFBhZ2VzOiBVc2VyU3RvcmFnZS5zZXR0aW5ncy5lbmFibGVGb3JQcm90ZWN0ZWRQYWdlc30pO1xuICAgICAgICB9XG5cbiAgICAgICAgVXNlclN0b3JhZ2Uuc2V0dGluZ3MuZmV0Y2hOZXdzICYmIE5ld3NtYWtlci5zdWJzY3JpYmUoKTtcbiAgICAgICAgRXh0ZW5zaW9uLnN0YXJ0QmFycmllciEucmVzb2x2ZSgpO1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIGdldE1lc3NlbmdlckFkYXB0ZXIoKTogRXh0ZW5zaW9uQWRhcHRlciB7XG4gICAgICAgIHJldHVybiB7XG4gICAgICAgICAgICBjb2xsZWN0OiBhc3luYyAoKSA9PiB7XG4gICAgICAgICAgICAgICAgcmV0dXJuIGF3YWl0IEV4dGVuc2lvbi5jb2xsZWN0RGF0YSgpO1xuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIGNvbGxlY3REZXZUb29sc0RhdGE6IGFzeW5jICgpID0+IHtcbiAgICAgICAgICAgICAgICByZXR1cm4gYXdhaXQgRXh0ZW5zaW9uLmNvbGxlY3REZXZUb29sc0RhdGEoKTtcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgICBjaGFuZ2VTZXR0aW5nczogRXh0ZW5zaW9uLmNoYW5nZVNldHRpbmdzLFxuICAgICAgICAgICAgc2V0VGhlbWU6IEV4dGVuc2lvbi5zZXRUaGVtZSxcbiAgICAgICAgICAgIHRvZ2dsZUFjdGl2ZVRhYjogRXh0ZW5zaW9uLnRvZ2dsZUFjdGl2ZVRhYixcbiAgICAgICAgICAgIG1hcmtOZXdzQXNSZWFkOiBOZXdzbWFrZXIubWFya0FzUmVhZCxcbiAgICAgICAgICAgIG1hcmtOZXdzQXNEaXNwbGF5ZWQ6IE5ld3NtYWtlci5tYXJrQXNEaXNwbGF5ZWQsXG4gICAgICAgICAgICBsb2FkQ29uZmlnOiBDb25maWdNYW5hZ2VyLmxvYWQsXG4gICAgICAgICAgICBhcHBseURldkR5bmFtaWNUaGVtZUZpeGVzOiBEZXZUb29scy5hcHBseUR5bmFtaWNUaGVtZUZpeGVzLFxuICAgICAgICAgICAgcmVzZXREZXZEeW5hbWljVGhlbWVGaXhlczogRGV2VG9vbHMucmVzZXREeW5hbWljVGhlbWVGaXhlcyxcbiAgICAgICAgICAgIGFwcGx5RGV2SW52ZXJzaW9uRml4ZXM6IERldlRvb2xzLmFwcGx5SW52ZXJzaW9uRml4ZXMsXG4gICAgICAgICAgICByZXNldERldkludmVyc2lvbkZpeGVzOiBEZXZUb29scy5yZXNldEludmVyc2lvbkZpeGVzLFxuICAgICAgICAgICAgYXBwbHlEZXZTdGF0aWNUaGVtZXM6IERldlRvb2xzLmFwcGx5U3RhdGljVGhlbWVzLFxuICAgICAgICAgICAgcmVzZXREZXZTdGF0aWNUaGVtZXM6IERldlRvb2xzLnJlc2V0U3RhdGljVGhlbWVzLFxuICAgICAgICAgICAgc3RhcnRBY3RpdmF0aW9uOiBFeHRlbnNpb24uc3RhcnRBY3RpdmF0aW9uLFxuICAgICAgICAgICAgcmVzZXRBY3RpdmF0aW9uOiBFeHRlbnNpb24ucmVzZXRBY3RpdmF0aW9uLFxuICAgICAgICAgICAgaGlkZUhpZ2hsaWdodHM6IFVJSGlnaGxpZ2h0cy5oaWRlSGlnaGxpZ2h0cyxcbiAgICAgICAgfTtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBvbkNvbW1hbmRJbnRlcm5hbCA9IGFzeW5jIChjb21tYW5kOiBDb21tYW5kLCB0YWJJZDogbnVtYmVyIHwgbnVsbCwgZnJhbWVJZDogbnVtYmVyIHwgbnVsbCwgZnJhbWVVUkw6IHN0cmluZyB8IG51bGwpID0+IHtcbiAgICAgICAgaWYgKEV4dGVuc2lvbi5zdGFydEJhcnJpZXIhLmlzUGVuZGluZygpKSB7XG4gICAgICAgICAgICBhd2FpdCBFeHRlbnNpb24uc3RhcnRCYXJyaWVyIS5lbnRyeSgpO1xuICAgICAgICB9XG4gICAgICAgIEV4dGVuc2lvbi5zdGF0ZU1hbmFnZXIhLmxvYWRTdGF0ZSgpO1xuICAgICAgICBzd2l0Y2ggKGNvbW1hbmQpIHtcbiAgICAgICAgICAgIGNhc2UgJ3RvZ2dsZSc6XG4gICAgICAgICAgICAgICAgbG9nSW5mbygnVG9nZ2xlIGNvbW1hbmQgZW50ZXJlZCcpO1xuICAgICAgICAgICAgICAgIEV4dGVuc2lvbi5jaGFuZ2VTZXR0aW5ncyh7XG4gICAgICAgICAgICAgICAgICAgIGVuYWJsZWQ6ICFFeHRlbnNpb24uaXNFeHRlbnNpb25Td2l0Y2hlZE9uKCksXG4gICAgICAgICAgICAgICAgICAgIGF1dG9tYXRpb246IHsuLi5Vc2VyU3RvcmFnZS5zZXR0aW5ncy5hdXRvbWF0aW9uLCAuLi57ZW5hYmxlZDogZmFsc2V9fSxcbiAgICAgICAgICAgICAgICB9KTtcbiAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgIGNhc2UgJ2FkZFNpdGUnOiB7XG4gICAgICAgICAgICAgICAgbG9nSW5mbygnQWRkIFNpdGUgY29tbWFuZCBlbnRlcmVkJyk7XG4gICAgICAgICAgICAgICAgYXN5bmMgZnVuY3Rpb24gc2NyaXB0UERGKHRhYklkOiBudW1iZXIsIGZyYW1lSWQ6IG51bWJlcik6IFByb21pc2U8Ym9vbGVhbj4ge1xuICAgICAgICAgICAgICAgICAgICAvLyBXZSBjYW4gbm90IGRldGVjdCBQREYgaWYgd2UgZG8gbm90IGtub3cgd2hlcmUgd2UgYXJlIGxvb2tpbmcgZm9yIGl0XG4gICAgICAgICAgICAgICAgICAgIGlmICghKE51bWJlci5pc0ludGVnZXIodGFiSWQpICYmIE51bWJlci5pc0ludGVnZXIoZnJhbWVJZCkpKSB7XG4gICAgICAgICAgICAgICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgZnVuY3Rpb24gZGV0ZWN0UERGKCk6IGJvb2xlYW4ge1xuICAgICAgICAgICAgICAgICAgICAgICAgaWYgKGRvY3VtZW50LmJvZHkuY2hpbGRFbGVtZW50Q291bnQgIT09IDEpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgICAgICBjb25zdCB7bm9kZU5hbWUsIHR5cGV9ID0gZG9jdW1lbnQuYm9keS5jaGlsZE5vZGVzWzBdIGFzIEhUTUxFbWJlZEVsZW1lbnQ7XG4gICAgICAgICAgICAgICAgICAgICAgICByZXR1cm4gbm9kZU5hbWUgPT09ICdFTUJFRCcgJiYgdHlwZSA9PT0gJ2FwcGxpY2F0aW9uL3BkZic7XG4gICAgICAgICAgICAgICAgICAgIH1cblxuICAgICAgICAgICAgICAgICAgICBpZiAoX19DSFJPTUlVTV9NVjNfXykge1xuICAgICAgICAgICAgICAgICAgICAgICAgcmV0dXJuIChhd2FpdCBjaHJvbWUuc2NyaXB0aW5nLmV4ZWN1dGVTY3JpcHQoe1xuICAgICAgICAgICAgICAgICAgICAgICAgICAgIHRhcmdldDoge3RhYklkLCBmcmFtZUlkczogW2ZyYW1lSWRdfSxcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBmdW5jOiBkZXRlY3RQREYsXG4gICAgICAgICAgICAgICAgICAgICAgICB9KSlbMF0ucmVzdWx0IHx8IGZhbHNlO1xuICAgICAgICAgICAgICAgICAgICB9IGVsc2UgaWYgKF9fQ0hST01JVU1fTVYyX18pIHtcbiAgICAgICAgICAgICAgICAgICAgICAgIHJldHVybiBuZXcgUHJvbWlzZTxib29sZWFuPigocmVzb2x2ZSkgPT4gY2hyb21lLnRhYnMuZXhlY3V0ZVNjcmlwdCh0YWJJZCwge1xuICAgICAgICAgICAgICAgICAgICAgICAgICAgIGZyYW1lSWQsXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgY29kZTogYCgke2RldGVjdFBERi50b1N0cmluZygpfSkoKWAsXG4gICAgICAgICAgICAgICAgICAgICAgICB9LCAocmVzdWx0cykgPT4gcmVzb2x2ZShyZXN1bHRzPy5bMF0pKSk7XG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgICAgICAgICAgICAgIH1cblxuICAgICAgICAgICAgICAgIGNvbnN0IHBkZiA9IGFzeW5jICgpID0+IGlzUERGKGZyYW1lVVJMIHx8IGF3YWl0IFRhYk1hbmFnZXIuZ2V0QWN0aXZlVGFiVVJMKCkpO1xuICAgICAgICAgICAgICAgIGlmICgoKF9fQ0hST01JVU1fTVYyX18gfHwgX19DSFJPTUlVTV9NVjNfXykgJiYgYXdhaXQgc2NyaXB0UERGKHRhYklkISwgZnJhbWVJZCEpKSB8fCBhd2FpdCBwZGYoKSkge1xuICAgICAgICAgICAgICAgICAgICBFeHRlbnNpb24uY2hhbmdlU2V0dGluZ3Moe2VuYWJsZUZvclBERjogIVVzZXJTdG9yYWdlLnNldHRpbmdzLmVuYWJsZUZvclBERn0pO1xuICAgICAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgICAgIEV4dGVuc2lvbi50b2dnbGVBY3RpdmVUYWIoKTtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICBjYXNlICdzd2l0Y2hFbmdpbmUnOiB7XG4gICAgICAgICAgICAgICAgbG9nSW5mbygnU3dpdGNoIEVuZ2luZSBjb21tYW5kIGVudGVyZWQnKTtcbiAgICAgICAgICAgICAgICBjb25zdCBlbmdpbmVzID0gT2JqZWN0LnZhbHVlcyhUaGVtZUVuZ2luZSk7XG4gICAgICAgICAgICAgICAgY29uc3QgaW5kZXggPSBlbmdpbmVzLmluZGV4T2YoVXNlclN0b3JhZ2Uuc2V0dGluZ3MudGhlbWUuZW5naW5lKTtcbiAgICAgICAgICAgICAgICBjb25zdCBuZXh0ID0gZW5naW5lc1soaW5kZXggKyAxKSAlIGVuZ2luZXMubGVuZ3RoXTtcbiAgICAgICAgICAgICAgICBFeHRlbnNpb24uc2V0VGhlbWUoe2VuZ2luZTogbmV4dH0pO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG4gICAgfTtcblxuICAgIC8vIDc1IGlzIHNtYWxsIGVub3VnaCB0byBub3Qgbm90aWNlIGl0LCBhbmQgc3RpbGwgY2F0Y2hlcyB3aGVuIHNvbWVvbmVcbiAgICAvLyBpcyBob2xkaW5nIGRvd24gYSBjZXJ0YWluIHNob3J0Y3V0LlxuICAgIHByaXZhdGUgc3RhdGljIG9uQ29tbWFuZCA9IGRlYm91bmNlKDc1LCBFeHRlbnNpb24ub25Db21tYW5kSW50ZXJuYWwpO1xuXG4gICAgcHJpdmF0ZSBzdGF0aWMgcmVnaXN0ZXJDb250ZXh0TWVudXMoKSB7XG4gICAgICAgIGNocm9tZS5jb250ZXh0TWVudXMub25DbGlja2VkLmFkZExpc3RlbmVyKGFzeW5jICh7bWVudUl0ZW1JZCwgZnJhbWVJZCwgZnJhbWVVcmwsIHBhZ2VVcmx9LCB0YWIpID0+XG4gICAgICAgICAgICBFeHRlbnNpb24ub25Db21tYW5kKG1lbnVJdGVtSWQgYXMgQ29tbWFuZCwgdGFiICYmIHRhYi5pZCB8fCBudWxsLCBmcmFtZUlkIHx8IG51bGwsIGZyYW1lVXJsIHx8IHBhZ2VVcmwgfHwgbnVsbCkpO1xuICAgICAgICBjaHJvbWUuY29udGV4dE1lbnVzLnJlbW92ZUFsbCgoKSA9PiB7XG4gICAgICAgICAgICBFeHRlbnNpb24ucmVnaXN0ZXJlZENvbnRleHRNZW51cyA9IGZhbHNlO1xuICAgICAgICAgICAgY2hyb21lLmNvbnRleHRNZW51cy5jcmVhdGUoe1xuICAgICAgICAgICAgICAgIGlkOiAnRGFya1JlYWRlci10b3AnLFxuICAgICAgICAgICAgICAgIHRpdGxlOiAnRGFyayBSZWFkZXInLFxuICAgICAgICAgICAgfSwgKCkgPT4ge1xuICAgICAgICAgICAgICAgIGlmIChjaHJvbWUucnVudGltZS5sYXN0RXJyb3IpIHtcbiAgICAgICAgICAgICAgICAgICAgLy8gRmFpbGVkIHRvIGNyZWF0ZSB0aGUgY29udGV4dCBtZW51XG4gICAgICAgICAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgY29uc3QgbXNnVG9nZ2xlID0gY2hyb21lLmkxOG4uZ2V0TWVzc2FnZSgndG9nZ2xlX2V4dGVuc2lvbicpO1xuICAgICAgICAgICAgICAgIGNvbnN0IG1zZ0FkZFNpdGUgPSBjaHJvbWUuaTE4bi5nZXRNZXNzYWdlKCd0b2dnbGVfY3VycmVudF9zaXRlJyk7XG4gICAgICAgICAgICAgICAgY29uc3QgbXNnU3dpdGNoRW5naW5lID0gY2hyb21lLmkxOG4uZ2V0TWVzc2FnZSgndGhlbWVfZ2VuZXJhdGlvbl9tb2RlJyk7XG4gICAgICAgICAgICAgICAgY2hyb21lLmNvbnRleHRNZW51cy5jcmVhdGUoe1xuICAgICAgICAgICAgICAgICAgICBpZDogJ3RvZ2dsZScsXG4gICAgICAgICAgICAgICAgICAgIHBhcmVudElkOiAnRGFya1JlYWRlci10b3AnLFxuICAgICAgICAgICAgICAgICAgICB0aXRsZTogbXNnVG9nZ2xlIHx8ICdUb2dnbGUgZXZlcnl3aGVyZScsXG4gICAgICAgICAgICAgICAgfSk7XG4gICAgICAgICAgICAgICAgY2hyb21lLmNvbnRleHRNZW51cy5jcmVhdGUoe1xuICAgICAgICAgICAgICAgICAgICBpZDogJ2FkZFNpdGUnLFxuICAgICAgICAgICAgICAgICAgICBwYXJlbnRJZDogJ0RhcmtSZWFkZXItdG9wJyxcbiAgICAgICAgICAgICAgICAgICAgdGl0bGU6IG1zZ0FkZFNpdGUgfHwgJ1RvZ2dsZSBmb3IgY3VycmVudCBzaXRlJyxcbiAgICAgICAgICAgICAgICB9KTtcbiAgICAgICAgICAgICAgICBjaHJvbWUuY29udGV4dE1lbnVzLmNyZWF0ZSh7XG4gICAgICAgICAgICAgICAgICAgIGlkOiAnc3dpdGNoRW5naW5lJyxcbiAgICAgICAgICAgICAgICAgICAgcGFyZW50SWQ6ICdEYXJrUmVhZGVyLXRvcCcsXG4gICAgICAgICAgICAgICAgICAgIHRpdGxlOiBtc2dTd2l0Y2hFbmdpbmUgfHwgJ1N3aXRjaCBlbmdpbmUnLFxuICAgICAgICAgICAgICAgIH0pO1xuICAgICAgICAgICAgICAgIEV4dGVuc2lvbi5yZWdpc3RlcmVkQ29udGV4dE1lbnVzID0gdHJ1ZTtcbiAgICAgICAgICAgIH0pO1xuICAgICAgICB9KTtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBhc3luYyBnZXRTaG9ydGN1dHMoKSB7XG4gICAgICAgIGNvbnN0IGNvbW1hbmRzID0gYXdhaXQgZ2V0Q29tbWFuZHMoKTtcbiAgICAgICAgcmV0dXJuIGNvbW1hbmRzLnJlZHVjZSgobWFwLCBjbWQpID0+IE9iamVjdC5hc3NpZ24obWFwLCB7W2NtZC5uYW1lIV06IGNtZC5zaG9ydGN1dH0pLCB7fSBhcyBTaG9ydGN1dHMpO1xuICAgIH1cblxuICAgIHN0YXRpYyBhc3luYyBjb2xsZWN0RGF0YSgpOiBQcm9taXNlPEV4dGVuc2lvbkRhdGE+IHtcbiAgICAgICAgYXdhaXQgRXh0ZW5zaW9uLmxvYWREYXRhKCk7XG4gICAgICAgIGNvbnN0IFtcbiAgICAgICAgICAgIG5ld3MsXG4gICAgICAgICAgICBzaG9ydGN1dHMsXG4gICAgICAgICAgICBhY3RpdmVUYWIsXG4gICAgICAgICAgICBpc0FsbG93ZWRGaWxlU2NoZW1lQWNjZXNzLFxuICAgICAgICAgICAgdWlIaWdobGlnaHRzLFxuICAgICAgICBdID0gYXdhaXQgUHJvbWlzZS5hbGwoW1xuICAgICAgICAgICAgTmV3c21ha2VyLmdldExhdGVzdCgpLFxuICAgICAgICAgICAgRXh0ZW5zaW9uLmdldFNob3J0Y3V0cygpLFxuICAgICAgICAgICAgRXh0ZW5zaW9uLmdldEFjdGl2ZVRhYkluZm8oKSxcbiAgICAgICAgICAgIG5ldyBQcm9taXNlPGJvb2xlYW4+KChyKSA9PiBjaHJvbWUuZXh0ZW5zaW9uLmlzQWxsb3dlZEZpbGVTY2hlbWVBY2Nlc3MocikpLFxuICAgICAgICAgICAgVUlIaWdobGlnaHRzLmdldEhpZ2hsaWdodHNUb1Nob3coKSxcbiAgICAgICAgXSk7XG4gICAgICAgIHJldHVybiB7XG4gICAgICAgICAgICBpc0VuYWJsZWQ6IEV4dGVuc2lvbi5pc0V4dGVuc2lvblN3aXRjaGVkT24oKSxcbiAgICAgICAgICAgIGlzUmVhZHk6IHRydWUsXG4gICAgICAgICAgICBpc0FsbG93ZWRGaWxlU2NoZW1lQWNjZXNzLFxuICAgICAgICAgICAgc2V0dGluZ3M6IFVzZXJTdG9yYWdlLnNldHRpbmdzLFxuICAgICAgICAgICAgbmV3cyxcbiAgICAgICAgICAgIHNob3J0Y3V0cyxcbiAgICAgICAgICAgIGNvbG9yU2NoZW1lOiBDb25maWdNYW5hZ2VyLkNPTE9SX1NDSEVNRVNfUkFXISxcbiAgICAgICAgICAgIGZvcmNlZFNjaGVtZTogRXh0ZW5zaW9uLmF1dG9TdGF0ZSA9PT0gJ3NjaGVtZS1kYXJrJyA/ICdkYXJrJyA6IEV4dGVuc2lvbi5hdXRvU3RhdGUgPT09ICdzY2hlbWUtbGlnaHQnID8gJ2xpZ2h0JyA6IG51bGwsXG4gICAgICAgICAgICBhY3RpdmVUYWIsXG4gICAgICAgICAgICB1aUhpZ2hsaWdodHMsXG4gICAgICAgIH07XG4gICAgfVxuXG4gICAgc3RhdGljIGFzeW5jIGNvbGxlY3REZXZUb29sc0RhdGEoKTogUHJvbWlzZTxEZXZUb29sc0RhdGE+IHtcbiAgICAgICAgY29uc3QgW1xuICAgICAgICAgICAgZHluYW1pY0ZpeGVzVGV4dCxcbiAgICAgICAgICAgIGZpbHRlckZpeGVzVGV4dCxcbiAgICAgICAgICAgIHN0YXRpY1RoZW1lc1RleHQsXG4gICAgICAgIF0gPSBhd2FpdCBQcm9taXNlLmFsbChbXG4gICAgICAgICAgICBEZXZUb29scy5nZXREeW5hbWljVGhlbWVGaXhlc1RleHQoKSxcbiAgICAgICAgICAgIERldlRvb2xzLmdldEludmVyc2lvbkZpeGVzVGV4dCgpLFxuICAgICAgICAgICAgRGV2VG9vbHMuZ2V0U3RhdGljVGhlbWVzVGV4dCgpLFxuICAgICAgICBdKTtcbiAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICAgIGR5bmFtaWNGaXhlc1RleHQsXG4gICAgICAgICAgICBmaWx0ZXJGaXhlc1RleHQsXG4gICAgICAgICAgICBzdGF0aWNUaGVtZXNUZXh0LFxuICAgICAgICB9O1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIGFzeW5jIGdldEFjdGl2ZVRhYkluZm8oKTogUHJvbWlzZTxUYWJJbmZvPiB7XG4gICAgICAgIGF3YWl0IEV4dGVuc2lvbi5sb2FkRGF0YSgpO1xuICAgICAgICBjb25zdCB0YWIgPSBhd2FpdCBnZXRBY3RpdmVUYWIoKTtcbiAgICAgICAgY29uc3QgdXJsID0gYXdhaXQgVGFiTWFuYWdlci5nZXRUYWJVUkwodGFiKTtcbiAgICAgICAgY29uc3Qge2lzSW5EYXJrTGlzdCwgaXNQcm90ZWN0ZWR9ID0gRXh0ZW5zaW9uLmdldFRhYkluZm8odXJsKTtcbiAgICAgICAgY29uc3QgaXNJbmplY3RlZCA9IFRhYk1hbmFnZXIuY2FuQWNjZXNzVGFiKHRhYik7XG4gICAgICAgIGNvbnN0IGRvY3VtZW50SWQgPSBUYWJNYW5hZ2VyLmdldFRhYkRvY3VtZW50SWQodGFiKTtcbiAgICAgICAgbGV0IGlzRGFya1RoZW1lRGV0ZWN0ZWQgPSBudWxsO1xuICAgICAgICBpZiAoVXNlclN0b3JhZ2Uuc2V0dGluZ3MuZGV0ZWN0RGFya1RoZW1lKSB7XG4gICAgICAgICAgICBpc0RhcmtUaGVtZURldGVjdGVkID0gVGFiTWFuYWdlci5pc1RhYkRhcmtUaGVtZURldGVjdGVkKHRhYik7XG4gICAgICAgIH1cbiAgICAgICAgY29uc3QgaWQgPSB0YWIgJiYgdGFiLmlkIHx8IG51bGw7XG4gICAgICAgIHJldHVybiB7XG4gICAgICAgICAgICBpZCxcbiAgICAgICAgICAgIGRvY3VtZW50SWQsXG4gICAgICAgICAgICB1cmwsXG4gICAgICAgICAgICBpc0luRGFya0xpc3QsXG4gICAgICAgICAgICBpc1Byb3RlY3RlZCxcbiAgICAgICAgICAgIGlzSW5qZWN0ZWQsXG4gICAgICAgICAgICBpc0RhcmtUaGVtZURldGVjdGVkLFxuICAgICAgICB9O1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIGFzeW5jIGdldENvbm5lY3Rpb25NZXNzYWdlKHRhYlVSTDogc3RyaW5nLCB1cmw6IHN0cmluZywgaXNUb3BGcmFtZTogYm9vbGVhbiwgdG9wRnJhbWVIYXNEYXJrVGhlbWU/OiBib29sZWFuKSB7XG4gICAgICAgIGF3YWl0IEV4dGVuc2lvbi5sb2FkRGF0YSgpO1xuICAgICAgICByZXR1cm4gRXh0ZW5zaW9uLmdldFRhYk1lc3NhZ2UodGFiVVJMLCB1cmwsIGlzVG9wRnJhbWUsIHRvcEZyYW1lSGFzRGFya1RoZW1lKTtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBhc3luYyBsb2FkRGF0YSgpIHtcbiAgICAgICAgRXh0ZW5zaW9uLmluaXQoKTtcbiAgICAgICAgYXdhaXQgUHJvbWlzZS5hbGwoW1xuICAgICAgICAgICAgRXh0ZW5zaW9uLnN0YXRlTWFuYWdlciEubG9hZFN0YXRlKCksXG4gICAgICAgICAgICBVc2VyU3RvcmFnZS5sb2FkU2V0dGluZ3MoKSxcbiAgICAgICAgXSk7XG4gICAgfVxuXG4gICAgcHJpdmF0ZSBzdGF0aWMgb25Db2xvclNjaGVtZUNoYW5nZSA9IGFzeW5jIChpc0Rhcms6IGJvb2xlYW4pID0+IHtcbiAgICAgICAgaWYgKEV4dGVuc2lvbi53YXNMYXN0Q29sb3JTY2hlbWVEYXJrID09PSBpc0RhcmspIHtcbiAgICAgICAgICAgIC8vIElmIGNvbG9yIHNjaGVtZSB3YXMgYWxyZWFkeSBjb3JyZWN0LCB3ZSBkbyBub3QgbmVlZCB0byBkbyBhbnl0aGluZ1xuICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICB9XG4gICAgICAgIEV4dGVuc2lvbi53YXNMYXN0Q29sb3JTY2hlbWVEYXJrID0gaXNEYXJrO1xuICAgICAgICBFeHRlbnNpb24uTVYzc3luY1N5c3RlbUNvbG9yU3RhdGVNYW5hZ2VyKGlzRGFyayk7XG4gICAgICAgIGF3YWl0IEV4dGVuc2lvbi5sb2FkRGF0YSgpO1xuICAgICAgICBpZiAoVXNlclN0b3JhZ2Uuc2V0dGluZ3MuYXV0b21hdGlvbi5tb2RlICE9PSBBdXRvbWF0aW9uTW9kZS5TWVNURU0pIHtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuICAgICAgICBFeHRlbnNpb24uaGFuZGxlQXV0b21hdGlvbkNoZWNrKCk7XG4gICAgfTtcblxuICAgIHByaXZhdGUgc3RhdGljIGhhbmRsZUF1dG9tYXRpb25DaGVjayA9ICgpID0+IHtcbiAgICAgICAgRXh0ZW5zaW9uLnVwZGF0ZUF1dG9TdGF0ZSgpO1xuXG4gICAgICAgIGNvbnN0IGlzU3dpdGNoZWRPbiA9IEV4dGVuc2lvbi5pc0V4dGVuc2lvblN3aXRjaGVkT24oKTtcbiAgICAgICAgaWYgKFxuICAgICAgICAgICAgRXh0ZW5zaW9uLndhc0VuYWJsZWRPbkxhc3RDaGVjayA9PT0gbnVsbCB8fFxuICAgICAgICAgICAgRXh0ZW5zaW9uLndhc0VuYWJsZWRPbkxhc3RDaGVjayAhPT0gaXNTd2l0Y2hlZE9uIHx8XG4gICAgICAgICAgICBFeHRlbnNpb24uYXV0b1N0YXRlID09PSAnc2NoZW1lLWRhcmsnIHx8XG4gICAgICAgICAgICBFeHRlbnNpb24uYXV0b1N0YXRlID09PSAnc2NoZW1lLWxpZ2h0J1xuICAgICAgICApIHtcbiAgICAgICAgICAgIEV4dGVuc2lvbi53YXNFbmFibGVkT25MYXN0Q2hlY2sgPSBpc1N3aXRjaGVkT247XG4gICAgICAgICAgICBFeHRlbnNpb24ub25BcHBUb2dnbGUoKTtcbiAgICAgICAgICAgIFRhYk1hbmFnZXIuc2VuZE1lc3NhZ2UoKTtcbiAgICAgICAgICAgIEV4dGVuc2lvbi5yZXBvcnRDaGFuZ2VzKCk7XG4gICAgICAgICAgICBFeHRlbnNpb24uc3RhdGVNYW5hZ2VyIS5zYXZlU3RhdGUoKTtcbiAgICAgICAgfVxuICAgIH07XG5cbiAgICBzdGF0aWMgYXN5bmMgY2hhbmdlU2V0dGluZ3MoJHNldHRpbmdzOiBQYXJ0aWFsPFVzZXJTZXR0aW5ncz4sIG9ubHlVcGRhdGVBY3RpdmVUYWIgPSBmYWxzZSk6IFByb21pc2U8dm9pZD4ge1xuICAgICAgICBjb25zdCBwcm9taXNlcyA9IFtdO1xuICAgICAgICBjb25zdCBwcmV2ID0gey4uLlVzZXJTdG9yYWdlLnNldHRpbmdzfTtcblxuICAgICAgICBVc2VyU3RvcmFnZS5zZXQoJHNldHRpbmdzKTtcblxuICAgICAgICBpZiAoXG4gICAgICAgICAgICAocHJldi5lbmFibGVkICE9PSBVc2VyU3RvcmFnZS5zZXR0aW5ncy5lbmFibGVkKSB8fFxuICAgICAgICAgICAgKHByZXYuYXV0b21hdGlvbi5lbmFibGVkICE9PSBVc2VyU3RvcmFnZS5zZXR0aW5ncy5hdXRvbWF0aW9uLmVuYWJsZWQpIHx8XG4gICAgICAgICAgICAocHJldi5hdXRvbWF0aW9uLm1vZGUgIT09IFVzZXJTdG9yYWdlLnNldHRpbmdzLmF1dG9tYXRpb24ubW9kZSkgfHxcbiAgICAgICAgICAgIChwcmV2LmF1dG9tYXRpb24uYmVoYXZpb3IgIT09IFVzZXJTdG9yYWdlLnNldHRpbmdzLmF1dG9tYXRpb24uYmVoYXZpb3IpIHx8XG4gICAgICAgICAgICAocHJldi50aW1lLmFjdGl2YXRpb24gIT09IFVzZXJTdG9yYWdlLnNldHRpbmdzLnRpbWUuYWN0aXZhdGlvbikgfHxcbiAgICAgICAgICAgIChwcmV2LnRpbWUuZGVhY3RpdmF0aW9uICE9PSBVc2VyU3RvcmFnZS5zZXR0aW5ncy50aW1lLmRlYWN0aXZhdGlvbikgfHxcbiAgICAgICAgICAgIChwcmV2LmxvY2F0aW9uLmxhdGl0dWRlICE9PSBVc2VyU3RvcmFnZS5zZXR0aW5ncy5sb2NhdGlvbi5sYXRpdHVkZSkgfHxcbiAgICAgICAgICAgIChwcmV2LmxvY2F0aW9uLmxvbmdpdHVkZSAhPT0gVXNlclN0b3JhZ2Uuc2V0dGluZ3MubG9jYXRpb24ubG9uZ2l0dWRlKVxuICAgICAgICApIHtcbiAgICAgICAgICAgIEV4dGVuc2lvbi51cGRhdGVBdXRvU3RhdGUoKTtcbiAgICAgICAgICAgIEV4dGVuc2lvbi5vbkFwcFRvZ2dsZSgpO1xuICAgICAgICB9XG4gICAgICAgIGlmIChwcmV2LnN5bmNTZXR0aW5ncyAhPT0gVXNlclN0b3JhZ2Uuc2V0dGluZ3Muc3luY1NldHRpbmdzKSB7XG4gICAgICAgICAgICBjb25zdCBwcm9taXNlID0gVXNlclN0b3JhZ2Uuc2F2ZVN5bmNTZXR0aW5nKFVzZXJTdG9yYWdlLnNldHRpbmdzLnN5bmNTZXR0aW5ncyk7XG4gICAgICAgICAgICBwcm9taXNlcy5wdXNoKHByb21pc2UpO1xuICAgICAgICB9XG4gICAgICAgIGlmIChFeHRlbnNpb24uaXNFeHRlbnNpb25Td2l0Y2hlZE9uKCkgJiYgJHNldHRpbmdzLmNoYW5nZUJyb3dzZXJUaGVtZSAhPSBudWxsICYmIHByZXYuY2hhbmdlQnJvd3NlclRoZW1lICE9PSAkc2V0dGluZ3MuY2hhbmdlQnJvd3NlclRoZW1lKSB7XG4gICAgICAgICAgICBpZiAoJHNldHRpbmdzLmNoYW5nZUJyb3dzZXJUaGVtZSkge1xuICAgICAgICAgICAgICAgIHNldFdpbmRvd1RoZW1lKFVzZXJTdG9yYWdlLnNldHRpbmdzLnRoZW1lKTtcbiAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgcmVzZXRXaW5kb3dUaGVtZSgpO1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICAgIGlmIChwcmV2LmZldGNoTmV3cyAhPT0gVXNlclN0b3JhZ2Uuc2V0dGluZ3MuZmV0Y2hOZXdzKSB7XG4gICAgICAgICAgICBVc2VyU3RvcmFnZS5zZXR0aW5ncy5mZXRjaE5ld3MgPyBOZXdzbWFrZXIuc3Vic2NyaWJlKCkgOiBOZXdzbWFrZXIudW5TdWJzY3JpYmUoKTtcbiAgICAgICAgfVxuXG4gICAgICAgIGlmIChwcmV2LmVuYWJsZUNvbnRleHRNZW51cyAhPT0gVXNlclN0b3JhZ2Uuc2V0dGluZ3MuZW5hYmxlQ29udGV4dE1lbnVzKSB7XG4gICAgICAgICAgICBpZiAoVXNlclN0b3JhZ2Uuc2V0dGluZ3MuZW5hYmxlQ29udGV4dE1lbnVzKSB7XG4gICAgICAgICAgICAgICAgRXh0ZW5zaW9uLnJlZ2lzdGVyQ29udGV4dE1lbnVzKCk7XG4gICAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgICAgIGNocm9tZS5jb250ZXh0TWVudXMucmVtb3ZlQWxsKCk7XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgICAgY29uc3QgcHJvbWlzZSA9IEV4dGVuc2lvbi5vblNldHRpbmdzQ2hhbmdlZChvbmx5VXBkYXRlQWN0aXZlVGFiKTtcbiAgICAgICAgcHJvbWlzZXMucHVzaChwcm9taXNlKTtcbiAgICAgICAgYXdhaXQgUHJvbWlzZS5hbGwocHJvbWlzZXMpO1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIHNldFRoZW1lKCR0aGVtZTogUGFydGlhbDxUaGVtZT4pIHtcbiAgICAgICAgVXNlclN0b3JhZ2Uuc2V0KHt0aGVtZTogey4uLlVzZXJTdG9yYWdlLnNldHRpbmdzLnRoZW1lLCAuLi4kdGhlbWV9fSk7XG5cbiAgICAgICAgaWYgKEV4dGVuc2lvbi5pc0V4dGVuc2lvblN3aXRjaGVkT24oKSAmJiBVc2VyU3RvcmFnZS5zZXR0aW5ncy5jaGFuZ2VCcm93c2VyVGhlbWUpIHtcbiAgICAgICAgICAgIHNldFdpbmRvd1RoZW1lKFVzZXJTdG9yYWdlLnNldHRpbmdzLnRoZW1lKTtcbiAgICAgICAgfVxuXG4gICAgICAgIEV4dGVuc2lvbi5vblNldHRpbmdzQ2hhbmdlZCgpO1xuICAgIH1cblxuICAgIHByaXZhdGUgc3RhdGljIGFzeW5jIHJlcG9ydENoYW5nZXMoKSB7XG4gICAgICAgIGNvbnN0IGluZm8gPSBhd2FpdCBFeHRlbnNpb24uY29sbGVjdERhdGEoKTtcbiAgICAgICAgTWVzc2VuZ2VyLnJlcG9ydENoYW5nZXMoaW5mbyk7XG4gICAgfVxuXG4gICAgcHJpdmF0ZSBzdGF0aWMgYXN5bmMgdG9nZ2xlQWN0aXZlVGFiKCkge1xuICAgICAgICBjb25zdCBzZXR0aW5ncyA9IFVzZXJTdG9yYWdlLnNldHRpbmdzO1xuICAgICAgICBjb25zdCB0YWIgPSBhd2FpdCBFeHRlbnNpb24uZ2V0QWN0aXZlVGFiSW5mbygpO1xuICAgICAgICBpZiAoIXRhYikge1xuICAgICAgICAgICAgcmV0dXJuO1xuICAgICAgICB9XG4gICAgICAgIGNvbnN0IHt1cmx9ID0gdGFiO1xuICAgICAgICBjb25zdCBpc0luRGFya0xpc3QgPSBDb25maWdNYW5hZ2VyLmlzVVJMSW5EYXJrTGlzdCh1cmwpO1xuICAgICAgICBjb25zdCBob3N0ID0gZ2V0VVJMSG9zdE9yUHJvdG9jb2wodXJsKTtcblxuICAgICAgICBmdW5jdGlvbiBnZXRUb2dnbGVkTGlzdChzb3VyY2VMaXN0OiBzdHJpbmdbXSkge1xuICAgICAgICAgICAgY29uc3QgbGlzdCA9IHNvdXJjZUxpc3Quc2xpY2UoKTtcblxuICAgICAgICAgICAgbGV0IGluZGV4ID0gbGlzdC5pbmRleE9mKGhvc3QpO1xuICAgICAgICAgICAgaWYgKGluZGV4IDwgMCAmJiBob3N0LnN0YXJ0c1dpdGgoJ3d3dy4nKSkge1xuICAgICAgICAgICAgICAgIGNvbnN0IG5vV3d3SG9zdCA9IGhvc3Quc3Vic3RyaW5nKDQpO1xuICAgICAgICAgICAgICAgIGluZGV4ID0gbGlzdC5pbmRleE9mKG5vV3d3SG9zdCk7XG4gICAgICAgICAgICB9XG5cbiAgICAgICAgICAgIGlmIChpbmRleCA8IDApIHtcbiAgICAgICAgICAgICAgICBsaXN0LnB1c2goaG9zdCk7XG4gICAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgICAgIGxpc3Quc3BsaWNlKGluZGV4LCAxKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIHJldHVybiBsaXN0O1xuICAgICAgICB9XG5cbiAgICAgICAgY29uc3QgZGFya1RoZW1lRGV0ZWN0ZWQgPSBzZXR0aW5ncy5lbmFibGVkQnlEZWZhdWx0ICYmIHNldHRpbmdzLmRldGVjdERhcmtUaGVtZSAmJiB0YWIuaXNEYXJrVGhlbWVEZXRlY3RlZDtcbiAgICAgICAgaWYgKCFzZXR0aW5ncy5lbmFibGVkQnlEZWZhdWx0IHx8IGlzSW5EYXJrTGlzdCB8fCBkYXJrVGhlbWVEZXRlY3RlZCkge1xuICAgICAgICAgICAgY29uc3QgdG9nZ2xlZExpc3QgPSBnZXRUb2dnbGVkTGlzdChzZXR0aW5ncy5lbmFibGVkRm9yKTtcbiAgICAgICAgICAgIEV4dGVuc2lvbi5jaGFuZ2VTZXR0aW5ncyh7ZW5hYmxlZEZvcjogdG9nZ2xlZExpc3R9LCB0cnVlKTtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuICAgICAgICBpZiAoc2V0dGluZ3MuZW5hYmxlZEJ5RGVmYXVsdCAmJiBzZXR0aW5ncy5lbmFibGVkRm9yLmluY2x1ZGVzKGhvc3QpKSB7XG4gICAgICAgICAgICBjb25zdCBlbmFibGVkRm9yID0gZ2V0VG9nZ2xlZExpc3Qoc2V0dGluZ3MuZW5hYmxlZEZvcik7XG4gICAgICAgICAgICBjb25zdCBkaXNhYmxlZEZvciA9IGdldFRvZ2dsZWRMaXN0KHNldHRpbmdzLmRpc2FibGVkRm9yKTtcbiAgICAgICAgICAgIEV4dGVuc2lvbi5jaGFuZ2VTZXR0aW5ncyh7ZW5hYmxlZEZvciwgZGlzYWJsZWRGb3J9LCB0cnVlKTtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuXG4gICAgICAgIGNvbnN0IHRvZ2dsZWRMaXN0ID0gZ2V0VG9nZ2xlZExpc3Qoc2V0dGluZ3MuZGlzYWJsZWRGb3IpO1xuICAgICAgICBFeHRlbnNpb24uY2hhbmdlU2V0dGluZ3Moe2Rpc2FibGVkRm9yOiB0b2dnbGVkTGlzdH0sIHRydWUpO1xuICAgIH1cblxuICAgIC8vLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tXG4gICAgLy9cbiAgICAvLyAgICAgICBIYW5kbGUgY29uZmlnIGNoYW5nZXNcbiAgICAvL1xuXG4gICAgcHJpdmF0ZSBzdGF0aWMgb25BcHBUb2dnbGUoKSB7XG4gICAgICAgIGlmIChFeHRlbnNpb24uaXNFeHRlbnNpb25Td2l0Y2hlZE9uKCkpIHtcbiAgICAgICAgICAgIEljb25NYW5hZ2VyLnNldEljb24oe2lzQWN0aXZlOiB0cnVlLCBjb2xvclNjaGVtZTogVXNlclN0b3JhZ2Uuc2V0dGluZ3MudGhlbWUubW9kZSA/ICdkYXJrJyA6ICdsaWdodCd9KTtcbiAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgIEljb25NYW5hZ2VyLnNldEljb24oe2lzQWN0aXZlOiBmYWxzZSwgY29sb3JTY2hlbWU6IFVzZXJTdG9yYWdlLnNldHRpbmdzLnRoZW1lLm1vZGUgPyAnZGFyaycgOiAnbGlnaHQnfSk7XG4gICAgICAgIH1cblxuICAgICAgICBpZiAoVXNlclN0b3JhZ2Uuc2V0dGluZ3MuY2hhbmdlQnJvd3NlclRoZW1lKSB7XG4gICAgICAgICAgICBpZiAoRXh0ZW5zaW9uLmlzRXh0ZW5zaW9uU3dpdGNoZWRPbigpICYmIEV4dGVuc2lvbi5hdXRvU3RhdGUgIT09ICdzY2hlbWUtbGlnaHQnKSB7XG4gICAgICAgICAgICAgICAgc2V0V2luZG93VGhlbWUoVXNlclN0b3JhZ2Uuc2V0dGluZ3MudGhlbWUpO1xuICAgICAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgICAgICByZXNldFdpbmRvd1RoZW1lKCk7XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBhc3luYyBvblNldHRpbmdzQ2hhbmdlZChvbmx5VXBkYXRlQWN0aXZlVGFiID0gZmFsc2UpIHtcbiAgICAgICAgYXdhaXQgRXh0ZW5zaW9uLmxvYWREYXRhKCk7XG4gICAgICAgIEV4dGVuc2lvbi53YXNFbmFibGVkT25MYXN0Q2hlY2sgPSBFeHRlbnNpb24uaXNFeHRlbnNpb25Td2l0Y2hlZE9uKCk7XG4gICAgICAgIFRhYk1hbmFnZXIuc2VuZE1lc3NhZ2Uob25seVVwZGF0ZUFjdGl2ZVRhYik7XG4gICAgICAgIEV4dGVuc2lvbi5zYXZlVXNlclNldHRpbmdzKCk7XG4gICAgICAgIEV4dGVuc2lvbi5yZXBvcnRDaGFuZ2VzKCk7XG4gICAgICAgIEljb25NYW5hZ2VyLnNldEljb24oe2NvbG9yU2NoZW1lOiBVc2VyU3RvcmFnZS5zZXR0aW5ncy50aGVtZS5tb2RlID8gJ2RhcmsnIDogJ2xpZ2h0J30pO1xuICAgICAgICBFeHRlbnNpb24uc3RhdGVNYW5hZ2VyIS5zYXZlU3RhdGUoKTtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBhc3luYyBzdGFydEFjdGl2YXRpb24oZW1haWw6IHN0cmluZywga2V5OiBzdHJpbmcpIHtcbiAgICAgICAgY29uc3QgZGVsYXkgPSAyMDAwICsgTWF0aC5yb3VuZChNYXRoLnJhbmRvbSgpICogMjAwMCk7XG4gICAgICAgIGNvbnN0IGNoZWNrRW1haWwgPSAoZW1haWw6IHN0cmluZykgPT4gZW1haWwgJiYgZW1haWwudHJpbSgpLmluY2x1ZGVzKCdAJyk7XG4gICAgICAgIGNvbnN0IGNoZWNrS2V5ID0gKGtleTogc3RyaW5nKSA9PiBrZXkucmVwbGFjZUFsbCgnLScsICcnKS5sZW5ndGggPT09IDI1ICYmIGtleS50b0xvY2FsZUxvd2VyQ2FzZSgpLnN0YXJ0c1dpdGgoJ2RyJykgJiYga2V5LnJlcGxhY2VBbGwoJy0nLCAnJykubWF0Y2goL15bMC05YS16XXsyNX0kL2kpO1xuICAgICAgICBzZXRUaW1lb3V0KGFzeW5jICgpID0+IHtcbiAgICAgICAgICAgIGF3YWl0IHdyaXRlTG9jYWxTdG9yYWdlKHthY3RpdmF0aW9uRW1haWw6IGVtYWlsLCBhY3RpdmF0aW9uS2V5OiBrZXl9KTtcbiAgICAgICAgICAgIGlmIChjaGVja0VtYWlsKGVtYWlsKSAmJiBjaGVja0tleShrZXkpKSB7XG4gICAgICAgICAgICAgICAgYXdhaXQgVUlIaWdobGlnaHRzLmhpZGVIaWdobGlnaHRzKFsnYW5uaXZlcnNhcnknXSk7XG4gICAgICAgICAgICAgICAgaWYgKF9fUExVU19fKSB7XG4gICAgICAgICAgICAgICAgICAgIGF3YWl0IEV4dGVuc2lvbi5jaGFuZ2VTZXR0aW5ncyh7cHJldmlld05ld2VzdERlc2lnbjogdHJ1ZX0pO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIEV4dGVuc2lvbi5yZXBvcnRDaGFuZ2VzKCk7XG4gICAgICAgIH0sIGRlbGF5KTtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBhc3luYyByZXNldEFjdGl2YXRpb24oKSB7XG4gICAgICAgIGF3YWl0IHJlbW92ZUxvY2FsU3RvcmFnZShbJ2FjdGl2YXRpb25FbWFpbCcsICdhY3RpdmF0aW9uS2V5J10pO1xuICAgICAgICBhd2FpdCBVSUhpZ2hsaWdodHMucmVzdG9yZUhpZ2hsaWdodHMoWydhbm5pdmVyc2FyeSddKTtcbiAgICAgICAgaWYgKF9fUExVU19fKSB7XG4gICAgICAgICAgICBhd2FpdCBFeHRlbnNpb24uY2hhbmdlU2V0dGluZ3Moe3ByZXZpZXdOZXdlc3REZXNpZ246IGZhbHNlfSk7XG4gICAgICAgIH1cbiAgICAgICAgRXh0ZW5zaW9uLnJlcG9ydENoYW5nZXMoKTtcbiAgICB9XG5cbiAgICAvLy0tLS0tLS0tLS0tLS0tLS0tLS0tLS1cbiAgICAvL1xuICAgIC8vIEFkZC9yZW1vdmUgY3NzIHRvIHRhYlxuICAgIC8vXG4gICAgLy8tLS0tLS0tLS0tLS0tLS0tLS0tLS0tXG5cbiAgICBwcml2YXRlIHN0YXRpYyBnZXRUYWJJbmZvKHRhYlVSTDogc3RyaW5nKTogUGljazxUYWJJbmZvLCAnaXNJbkRhcmtMaXN0JyB8ICdpc1Byb3RlY3RlZCc+IHtcbiAgICAgICAgY29uc3QgaXNJbkRhcmtMaXN0ID0gQ29uZmlnTWFuYWdlci5pc1VSTEluRGFya0xpc3QodGFiVVJMKTtcbiAgICAgICAgY29uc3QgaXNQcm90ZWN0ZWQgPSAhY2FuSW5qZWN0U2NyaXB0KHRhYlVSTCk7XG4gICAgICAgIHJldHVybiB7XG4gICAgICAgICAgICBpc0luRGFya0xpc3QsXG4gICAgICAgICAgICBpc1Byb3RlY3RlZCxcbiAgICAgICAgfTtcbiAgICB9XG5cbiAgICBwcml2YXRlIHN0YXRpYyBnZXRUYWJNZXNzYWdlID0gKHRhYlVSTDogc3RyaW5nLCB1cmw6IHN0cmluZywgaXNUb3BGcmFtZTogYm9vbGVhbiwgdG9wRnJhbWVIYXNEYXJrVGhlbWU/OiBib29sZWFuKTogVGFiRGF0YSA9PiB7XG4gICAgICAgIGNvbnN0IHNldHRpbmdzID0gVXNlclN0b3JhZ2Uuc2V0dGluZ3M7XG4gICAgICAgIGNvbnN0IHRhYkluZm8gPSBFeHRlbnNpb24uZ2V0VGFiSW5mbyh0YWJVUkwpO1xuICAgICAgICBpZiAoRXh0ZW5zaW9uLmlzRXh0ZW5zaW9uU3dpdGNoZWRPbigpICYmIGlzVVJMRW5hYmxlZCh0YWJVUkwsIHNldHRpbmdzLCB0YWJJbmZvKSAmJiAhdG9wRnJhbWVIYXNEYXJrVGhlbWUpIHtcbiAgICAgICAgICAgIGNvbnN0IGN1c3RvbSA9IHNldHRpbmdzLmN1c3RvbVRoZW1lcy5maW5kKCh7dXJsOiB1cmxMaXN0fSkgPT4gaXNVUkxJbkxpc3QodGFiVVJMLCB1cmxMaXN0KSk7XG4gICAgICAgICAgICBjb25zdCBwcmVzZXQgPSBjdXN0b20gPyBudWxsIDogc2V0dGluZ3MucHJlc2V0cy5maW5kKCh7dXJsc30pID0+IGlzVVJMSW5MaXN0KHRhYlVSTCwgdXJscykpO1xuICAgICAgICAgICAgbGV0IHRoZW1lID0gY3VzdG9tID8gY3VzdG9tLnRoZW1lIDogcHJlc2V0ID8gcHJlc2V0LnRoZW1lIDogc2V0dGluZ3MudGhlbWU7XG4gICAgICAgICAgICBpZiAoRXh0ZW5zaW9uLmF1dG9TdGF0ZSA9PT0gJ3NjaGVtZS1kYXJrJyB8fCBFeHRlbnNpb24uYXV0b1N0YXRlID09PSAnc2NoZW1lLWxpZ2h0Jykge1xuICAgICAgICAgICAgICAgIGNvbnN0IG1vZGUgPSBFeHRlbnNpb24uYXV0b1N0YXRlID09PSAnc2NoZW1lLWRhcmsnID8gMSA6IDA7XG4gICAgICAgICAgICAgICAgdGhlbWUgPSB7Li4udGhlbWUsIG1vZGV9O1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgY29uc3QgZGV0ZWN0b3JIaW50cyA9IHNldHRpbmdzLmRldGVjdERhcmtUaGVtZSA/IGdldERldGVjdG9ySGludHNGb3IodXJsLCBDb25maWdNYW5hZ2VyLkRFVEVDVE9SX0hJTlRTX1JBVyEsIENvbmZpZ01hbmFnZXIuREVURUNUT1JfSElOVFNfSU5ERVghKSA6IG51bGw7XG4gICAgICAgICAgICBjb25zdCBkZXRlY3REYXJrVGhlbWUgPSAoXG4gICAgICAgICAgICAgICAgc2V0dGluZ3MuZGV0ZWN0RGFya1RoZW1lICYmXG4gICAgICAgICAgICAgICAgKGlzVG9wRnJhbWUgfHwgZGV0ZWN0b3JIaW50cz8uc29tZSgoaCkgPT4gaC5pZnJhbWUpKSAmJlxuICAgICAgICAgICAgICAgICFpc1VSTEluTGlzdCh0YWJVUkwsIHNldHRpbmdzLmVuYWJsZWRGb3IpICYmXG4gICAgICAgICAgICAgICAgIWlzUERGKHRhYlVSTClcbiAgICAgICAgICAgICk7XG5cbiAgICAgICAgICAgIGxvZ0luZm8oYENyZWF0aW5nIENTUyBmb3IgdXJsOiAke3VybH1gKTtcbiAgICAgICAgICAgIGxvZ0luZm8oYEN1c3RvbSB0aGVtZSAke2N1c3RvbSA/ICd3YXMgZm91bmQnIDogJ3dhcyBub3QgZm91bmQnfSwgUHJlc2V0IHRoZW1lICR7cHJlc2V0ID8gJ3dhcyBmb3VuZCcgOiAnd2FzIG5vdCBmb3VuZCd9XG4gICAgICAgICAgICBUaGUgdGhlbWUoJHtjdXN0b20gPyAnY3VzdG9tJyA6IHByZXNldCA/ICdwcmVzZXQnIDogJ2dsb2JhbCd9IHNldHRpbmdzKSB1c2VkIGlzOiAke0pTT04uc3RyaW5naWZ5KHRoZW1lKX1gKTtcbiAgICAgICAgICAgIHN3aXRjaCAodGhlbWUuZW5naW5lKSB7XG4gICAgICAgICAgICAgICAgY2FzZSBUaGVtZUVuZ2luZS5jc3NGaWx0ZXI6IHtcbiAgICAgICAgICAgICAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICAgICAgICAgICAgICAgIHR5cGU6IE1lc3NhZ2VUeXBlQkd0b0NTLkFERF9DU1NfRklMVEVSLFxuICAgICAgICAgICAgICAgICAgICAgICAgZGF0YToge1xuICAgICAgICAgICAgICAgICAgICAgICAgICAgIGNzczogY3JlYXRlQ1NTRmlsdGVyU3R5bGVzaGVldCh0aGVtZSwgdXJsLCBpc1RvcEZyYW1lLCBDb25maWdNYW5hZ2VyLklOVkVSU0lPTl9GSVhFU19SQVchLCBDb25maWdNYW5hZ2VyLklOVkVSU0lPTl9GSVhFU19JTkRFWCEpLFxuICAgICAgICAgICAgICAgICAgICAgICAgICAgIGRldGVjdERhcmtUaGVtZSxcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBkZXRlY3RvckhpbnRzLFxuICAgICAgICAgICAgICAgICAgICAgICAgICAgIHRoZW1lLFxuICAgICAgICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICAgICAgfTtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgY2FzZSBUaGVtZUVuZ2luZS5zdmdGaWx0ZXI6IHtcbiAgICAgICAgICAgICAgICAgICAgaWYgKGlzRmlyZWZveCkge1xuICAgICAgICAgICAgICAgICAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICB0eXBlOiBNZXNzYWdlVHlwZUJHdG9DUy5BRERfQ1NTX0ZJTFRFUixcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBkYXRhOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGNzczogY3JlYXRlU1ZHRmlsdGVyU3R5bGVzaGVldCh0aGVtZSwgdXJsLCBpc1RvcEZyYW1lLCBDb25maWdNYW5hZ2VyLklOVkVSU0lPTl9GSVhFU19SQVchLCBDb25maWdNYW5hZ2VyLklOVkVSU0lPTl9GSVhFU19JTkRFWCEpLFxuICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBkZXRlY3REYXJrVGhlbWUsXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGRldGVjdG9ySGludHMsXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHRoZW1lLFxuICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICB9O1xuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgIHJldHVybiB7XG4gICAgICAgICAgICAgICAgICAgICAgICB0eXBlOiBNZXNzYWdlVHlwZUJHdG9DUy5BRERfU1ZHX0ZJTFRFUixcbiAgICAgICAgICAgICAgICAgICAgICAgIGRhdGE6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBjc3M6IGNyZWF0ZVNWR0ZpbHRlclN0eWxlc2hlZXQodGhlbWUsIHVybCwgaXNUb3BGcmFtZSwgQ29uZmlnTWFuYWdlci5JTlZFUlNJT05fRklYRVNfUkFXISwgQ29uZmlnTWFuYWdlci5JTlZFUlNJT05fRklYRVNfSU5ERVghKSxcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBzdmdNYXRyaXg6IGdldFNWR0ZpbHRlck1hdHJpeFZhbHVlKHRoZW1lKSxcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBzdmdSZXZlcnNlTWF0cml4OiBnZXRTVkdSZXZlcnNlRmlsdGVyTWF0cml4VmFsdWUoKSxcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBkZXRlY3REYXJrVGhlbWUsXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgZGV0ZWN0b3JIaW50cyxcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICB0aGVtZSxcbiAgICAgICAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICAgIH07XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIGNhc2UgVGhlbWVFbmdpbmUuc3RhdGljVGhlbWU6IHtcbiAgICAgICAgICAgICAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICAgICAgICAgICAgICAgIHR5cGU6IE1lc3NhZ2VUeXBlQkd0b0NTLkFERF9TVEFUSUNfVEhFTUUsXG4gICAgICAgICAgICAgICAgICAgICAgICBkYXRhOiB7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgY3NzOiB0aGVtZS5zdHlsZXNoZWV0ICYmIHRoZW1lLnN0eWxlc2hlZXQudHJpbSgpID9cbiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdGhlbWUuc3R5bGVzaGVldCA6XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGNyZWF0ZVN0YXRpY1N0eWxlc2hlZXQodGhlbWUsIHVybCwgaXNUb3BGcmFtZSwgQ29uZmlnTWFuYWdlci5TVEFUSUNfVEhFTUVTX1JBVyEsIENvbmZpZ01hbmFnZXIuU1RBVElDX1RIRU1FU19JTkRFWCEpLFxuICAgICAgICAgICAgICAgICAgICAgICAgICAgIGRldGVjdERhcmtUaGVtZTogc2V0dGluZ3MuZGV0ZWN0RGFya1RoZW1lLFxuICAgICAgICAgICAgICAgICAgICAgICAgICAgIGRldGVjdG9ySGludHMsXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgdGhlbWUsXG4gICAgICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICB9O1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICBjYXNlIFRoZW1lRW5naW5lLmR5bmFtaWNUaGVtZToge1xuICAgICAgICAgICAgICAgICAgICBjb25zdCBmaXhlcyA9IGdldER5bmFtaWNUaGVtZUZpeGVzRm9yKHVybCwgaXNUb3BGcmFtZSwgQ29uZmlnTWFuYWdlci5EWU5BTUlDX1RIRU1FX0ZJWEVTX1JBVyEsIENvbmZpZ01hbmFnZXIuRFlOQU1JQ19USEVNRV9GSVhFU19JTkRFWCEsIFVzZXJTdG9yYWdlLnNldHRpbmdzLmVuYWJsZUZvclBERik7XG4gICAgICAgICAgICAgICAgICAgIHJldHVybiB7XG4gICAgICAgICAgICAgICAgICAgICAgICB0eXBlOiBNZXNzYWdlVHlwZUJHdG9DUy5BRERfRFlOQU1JQ19USEVNRSxcbiAgICAgICAgICAgICAgICAgICAgICAgIGRhdGE6IHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICB0aGVtZSxcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBmaXhlcyxcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBpc0lGcmFtZTogIWlzVG9wRnJhbWUsXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgZGV0ZWN0RGFya1RoZW1lLFxuICAgICAgICAgICAgICAgICAgICAgICAgICAgIGRldGVjdG9ySGludHMsXG4gICAgICAgICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgICAgICB9O1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICBkZWZhdWx0OlxuICAgICAgICAgICAgICAgICAgICB0aHJvdyBuZXcgRXJyb3IoYFVua25vd24gZW5naW5lICR7dGhlbWUuZW5naW5lfWApO1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG5cbiAgICAgICAgbG9nSW5mbyhgU2l0ZSBpcyBub3QgaW52ZXJ0ZWQ6ICR7dGFiVVJMfWApO1xuICAgICAgICByZXR1cm4ge1xuICAgICAgICAgICAgdHlwZTogTWVzc2FnZVR5cGVCR3RvQ1MuQ0xFQU5fVVAsXG4gICAgICAgIH07XG4gICAgfTtcblxuICAgIC8vLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLVxuICAgIC8vICAgICAgICAgIFVzZXIgc2V0dGluZ3NcblxuICAgIHByaXZhdGUgc3RhdGljIGFzeW5jIHNhdmVVc2VyU2V0dGluZ3MoKSB7XG4gICAgICAgIGF3YWl0IFVzZXJTdG9yYWdlLnNhdmVTZXR0aW5ncygpO1xuICAgICAgICBsb2dJbmZvKCdzYXZlZCcsIFVzZXJTdG9yYWdlLnNldHRpbmdzKTtcbiAgICB9XG59XG4iLCJpbXBvcnQge2NhbkluamVjdFNjcmlwdCwga2VlcExpc3RlbmluZ1RvRXZlbnRzfSBmcm9tICcuLi9iYWNrZ3JvdW5kL3V0aWxzL2V4dGVuc2lvbi1hcGknO1xuaW1wb3J0IHR5cGUge0NvbG9yU2NoZW1lLCBEZWJ1Z01lc3NhZ2VCR3RvQ1MsIERlYnVnTWVzc2FnZUJHdG9VSSwgRGVidWdNZXNzYWdlQ1N0b0JHLCBFeHRlbnNpb25EYXRhLCBOZXdzLCBVc2VyU2V0dGluZ3N9IGZyb20gJy4uL2RlZmluaXRpb25zJztcbmltcG9ydCB7Z2V0SGVscFVSTCwgVU5JTlNUQUxMX1VSTH0gZnJvbSAnLi4vdXRpbHMvbGlua3MnO1xuaW1wb3J0IHtlbXVsYXRlQ29sb3JTY2hlbWUsIGlzU3lzdGVtRGFya01vZGVFbmFibGVkfSBmcm9tICcuLi91dGlscy9tZWRpYS1xdWVyeSc7XG5pbXBvcnQge0RlYnVnTWVzc2FnZVR5cGVCR3RvQ1MsIERlYnVnTWVzc2FnZVR5cGVCR3RvVUksIERlYnVnTWVzc2FnZVR5cGVDU3RvQkd9IGZyb20gJy4uL3V0aWxzL21lc3NhZ2UnO1xuaW1wb3J0IHtpc0ZpcmVmb3h9IGZyb20gJy4uL3V0aWxzL3BsYXRmb3JtJztcblxuaW1wb3J0IHtFeHRlbnNpb259IGZyb20gJy4vZXh0ZW5zaW9uJztcbmltcG9ydCB7bWFrZUNocm9taXVtSGFwcHl9IGZyb20gJy4vbWFrZS1jaHJvbWl1bS1oYXBweSc7XG5pbXBvcnQge3NldE5ld3NGb3JUZXN0aW5nfSBmcm9tICcuL25ld3NtYWtlcic7XG5pbXBvcnQge0FTU0VSVH0gZnJvbSAnLi91dGlscy9sb2cnO1xuaW1wb3J0IHtzZW5kTG9nfSBmcm9tICcuL3V0aWxzL3NlbmRMb2cnO1xuXG5cbnR5cGUgVGVzdE1lc3NhZ2UgPSB7XG4gICAgdHlwZTogJ2dldE1hbmlmZXN0JztcbiAgICBpZDogbnVtYmVyO1xufSB8IHtcbiAgICB0eXBlOiAnY2hhbmdlU2V0dGluZ3MnO1xuICAgIGRhdGE6IFBhcnRpYWw8VXNlclNldHRpbmdzPjtcbiAgICBpZDogbnVtYmVyO1xufSB8IHtcbiAgICB0eXBlOiAnY29sbGVjdERhdGEnO1xuICAgIGlkOiBudW1iZXI7XG59IHwge1xuICAgIHR5cGU6ICdnZXRDaHJvbWVTdG9yYWdlJztcbiAgICBkYXRhOiB7XG4gICAgICAgIHJlZ2lvbjogJ2xvY2FsJyB8ICdzeW5jJztcbiAgICAgICAga2V5czogc3RyaW5nIHwgc3RyaW5nW107XG4gICAgfTtcbiAgICBpZDogbnVtYmVyO1xufSB8IHtcbiAgICB0eXBlOiAnY2hhbmdlQ2hyb21lU3RvcmFnZSc7XG4gICAgZGF0YToge1xuICAgICAgICByZWdpb246ICdsb2NhbCcgfCAnc3luYyc7XG4gICAgICAgIGRhdGE6IHtba2V5OiBzdHJpbmddOiBhbnl9O1xuICAgIH07XG4gICAgaWQ6IG51bWJlcjtcbn0gfCB7XG4gICAgdHlwZTogJ2ZpcmVmb3gtY3JlYXRlVGFiJztcbiAgICBkYXRhOiBzdHJpbmc7XG4gICAgaWQ6IG51bWJlcjtcbn0gfCB7XG4gICAgdHlwZTogJ2ZpcmVmb3gtZ2V0Q29sb3JTY2hlbWUnO1xuICAgIGlkOiBudW1iZXI7XG59IHwge1xuICAgIHR5cGU6ICdmaXJlZm94LWVtdWxhdGVDb2xvclNjaGVtZSc7XG4gICAgZGF0YTogQ29sb3JTY2hlbWU7XG4gICAgaWQ6IG51bWJlcjtcbn0gfCB7XG4gICAgdHlwZTogJ3NldE5ld3MnO1xuICAgIGRhdGE6IE5ld3NbXTtcbiAgICBpZDogbnVtYmVyO1xufTtcblxuLy8gU3RhcnQgZXh0ZW5zaW9uXG5jb25zdCBleHRlbnNpb24gPSBFeHRlbnNpb24uc3RhcnQoKTtcblxuY29uc3Qgd2VsY29tZSA9IGAgIC8nJycnXFxcXFxuICgwKT09KDApXG4vX198fHx8X19cXFxcXG5XZWxjb21lIHRvIERhcmsgUmVhZGVyIWA7XG5jb25zb2xlLmxvZyh3ZWxjb21lKTtcblxuZGVjbGFyZSBjb25zdCBfX0RFQlVHX186IGJvb2xlYW47XG5kZWNsYXJlIGNvbnN0IF9fV0FUQ0hfXzogYm9vbGVhbjtcbmRlY2xhcmUgY29uc3QgX19MT0dfXzogc3RyaW5nIHwgZmFsc2U7XG5kZWNsYXJlIGNvbnN0IF9fUE9SVF9fOiBudW1iZXI7XG5kZWNsYXJlIGNvbnN0IF9fVEVTVF9fOiBib29sZWFuO1xuZGVjbGFyZSBjb25zdCBfX0NIUk9NSVVNX01WM19fOiBib29sZWFuO1xuZGVjbGFyZSBjb25zdCBfX0ZJUkVGT1hfTVYyX186IGJvb2xlYW47XG5cbmlmIChfX0NIUk9NSVVNX01WM19fKSB7XG4gICAgY2hyb21lLnJ1bnRpbWUub25JbnN0YWxsZWQuYWRkTGlzdGVuZXIoYXN5bmMgKCkgPT4ge1xuICAgICAgICBFeHRlbnNpb24uaXNGaXJzdExvYWQgPSB0cnVlO1xuICAgIH0pO1xuICAgIGtlZXBMaXN0ZW5pbmdUb0V2ZW50cygpO1xufVxuXG5pZiAoX19XQVRDSF9fKSB7XG4gICAgY29uc3QgUE9SVCA9IF9fUE9SVF9fO1xuICAgIGNvbnN0IEFMQVJNX05BTUUgPSAnc29ja2V0LWNsb3NlJztcbiAgICBjb25zdCBQSU5HX0lOVEVSVkFMX0lOX01JTlVURVMgPSAxIC8gNjA7XG5cbiAgICBjb25zdCBzb2NrZXRBbGFybUxpc3RlbmVyID0gKGFsYXJtOiBjaHJvbWUuYWxhcm1zLkFsYXJtKSA9PiB7XG4gICAgICAgIGlmIChhbGFybS5uYW1lID09PSBBTEFSTV9OQU1FKSB7XG4gICAgICAgICAgICBsaXN0ZW4oKTtcbiAgICAgICAgfVxuICAgIH07XG5cbiAgICBjb25zdCBsaXN0ZW4gPSAoKSA9PiB7XG4gICAgICAgIGNvbnN0IHNvY2tldCA9IG5ldyBXZWJTb2NrZXQoYHdzOi8vbG9jYWxob3N0OiR7UE9SVH1gKTtcbiAgICAgICAgY29uc3Qgc2VuZCA9IChtZXNzYWdlOiB7dHlwZTogc3RyaW5nfSkgPT4gc29ja2V0LnNlbmQoSlNPTi5zdHJpbmdpZnkobWVzc2FnZSkpO1xuICAgICAgICBzb2NrZXQub25tZXNzYWdlID0gKGUpID0+IHtcbiAgICAgICAgICAgIGNocm9tZS5hbGFybXMub25BbGFybS5yZW1vdmVMaXN0ZW5lcihzb2NrZXRBbGFybUxpc3RlbmVyKTtcblxuICAgICAgICAgICAgY29uc3QgbWVzc2FnZSA9IEpTT04ucGFyc2UoZS5kYXRhKTtcbiAgICAgICAgICAgIGlmIChtZXNzYWdlLnR5cGUuc3RhcnRzV2l0aCgncmVsb2FkOicpKSB7XG4gICAgICAgICAgICAgICAgc2VuZCh7dHlwZTogJ3JlbG9hZGluZyd9KTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIHN3aXRjaCAobWVzc2FnZS50eXBlKSB7XG4gICAgICAgICAgICAgICAgY2FzZSAncmVsb2FkOmNzcyc6XG4gICAgICAgICAgICAgICAgICAgIGNocm9tZS5ydW50aW1lLnNlbmRNZXNzYWdlPERlYnVnTWVzc2FnZUJHdG9VST4oe3R5cGU6IERlYnVnTWVzc2FnZVR5cGVCR3RvVUkuQ1NTX1VQREFURX0pO1xuICAgICAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgICAgICBjYXNlICdyZWxvYWQ6dWknOlxuICAgICAgICAgICAgICAgICAgICBjaHJvbWUucnVudGltZS5zZW5kTWVzc2FnZTxEZWJ1Z01lc3NhZ2VCR3RvVUk+KHt0eXBlOiBEZWJ1Z01lc3NhZ2VUeXBlQkd0b1VJLlVQREFURX0pO1xuICAgICAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgICAgICBjYXNlICdyZWxvYWQ6ZnVsbCc6XG4gICAgICAgICAgICAgICAgICAgIGNocm9tZS50YWJzLnF1ZXJ5KHt9LCAodGFicykgPT4ge1xuICAgICAgICAgICAgICAgICAgICAgICAgY29uc3QgbWVzc2FnZTogRGVidWdNZXNzYWdlQkd0b0NTID0ge3R5cGU6IERlYnVnTWVzc2FnZVR5cGVCR3RvQ1MuUkVMT0FEfTtcbiAgICAgICAgICAgICAgICAgICAgICAgIC8vIFNvbWUgY29udGV4dHMgYXJlIG5vdCBjb25zaWRlcmVkIHRvIGJlIHRhYnMgYW5kIGNhbiBub3QgcmVjZWl2ZSByZWd1bGFyIG1lc3NhZ2VzXG4gICAgICAgICAgICAgICAgICAgICAgICBjaHJvbWUucnVudGltZS5zZW5kTWVzc2FnZTxEZWJ1Z01lc3NhZ2VCR3RvQ1M+KG1lc3NhZ2UpO1xuICAgICAgICAgICAgICAgICAgICAgICAgZm9yIChjb25zdCB0YWIgb2YgdGFicykge1xuICAgICAgICAgICAgICAgICAgICAgICAgICAgIGlmIChjYW5JbmplY3RTY3JpcHQodGFiLnVybCkpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgaWYgKF9fQ0hST01JVU1fTVYzX18pIHtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGNocm9tZS50YWJzLnNlbmRNZXNzYWdlPERlYnVnTWVzc2FnZUJHdG9DUz4odGFiLmlkISwgbWVzc2FnZSkuY2F0Y2goKCkgPT4geyAvKiBub29wICovIH0pO1xuICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgY29udGludWU7XG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgY2hyb21lLnRhYnMuc2VuZE1lc3NhZ2U8RGVidWdNZXNzYWdlQkd0b0NTPih0YWIuaWQhLCBtZXNzYWdlKTtcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgICAgICBjaHJvbWUucnVudGltZS5yZWxvYWQoKTtcbiAgICAgICAgICAgICAgICAgICAgfSk7XG4gICAgICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgfVxuICAgICAgICB9O1xuICAgICAgICBzb2NrZXQub25jbG9zZSA9ICgpID0+IHtcbiAgICAgICAgICAgIGNocm9tZS5hbGFybXMub25BbGFybS5hZGRMaXN0ZW5lcihzb2NrZXRBbGFybUxpc3RlbmVyKTtcbiAgICAgICAgICAgIGNocm9tZS5hbGFybXMuY3JlYXRlKEFMQVJNX05BTUUsIHtkZWxheUluTWludXRlczogUElOR19JTlRFUlZBTF9JTl9NSU5VVEVTfSk7XG4gICAgICAgIH07XG4gICAgfTtcblxuICAgIGxpc3RlbigpO1xufSBlbHNlIGlmICghX19ERUJVR19fICYmICFfX1RFU1RfXykge1xuICAgIGNocm9tZS5ydW50aW1lLm9uSW5zdGFsbGVkLmFkZExpc3RlbmVyKCh7cmVhc29ufSkgPT4ge1xuICAgICAgICBpZiAocmVhc29uID09PSAnaW5zdGFsbCcpIHtcbiAgICAgICAgICAgIGNocm9tZS50YWJzLmNyZWF0ZSh7dXJsOiBnZXRIZWxwVVJMKCl9KTtcbiAgICAgICAgfVxuICAgIH0pO1xuXG4gICAgY2hyb21lLnJ1bnRpbWUuc2V0VW5pbnN0YWxsVVJMKFVOSU5TVEFMTF9VUkwpO1xufVxuXG5pZiAoX19URVNUX18pIHtcbiAgICAvLyBPcGVuIHBvcHVwIGFuZCBEZXZUb29scyBwYWdlc1xuICAgIGNocm9tZS50YWJzLmNyZWF0ZSh7dXJsOiBjaHJvbWUucnVudGltZS5nZXRVUkwoJy91aS9wb3B1cC9pbmRleC5odG1sJyksIGFjdGl2ZTogZmFsc2V9KTtcbiAgICBjaHJvbWUudGFicy5jcmVhdGUoe3VybDogY2hyb21lLnJ1bnRpbWUuZ2V0VVJMKCcvdWkvZGV2dG9vbHMvaW5kZXguaHRtbCcpLCBhY3RpdmU6IGZhbHNlfSk7XG5cbiAgICBsZXQgdGVzdFRhYklkOiBudW1iZXIgfCBudWxsID0gbnVsbDtcbiAgICBpZiAoX19GSVJFRk9YX01WMl9fKSB7XG4gICAgICAgIGNocm9tZS50YWJzLmNyZWF0ZSh7dXJsOiAnYWJvdXQ6YmxhbmsnLCBhY3RpdmU6IHRydWV9LCAoe2lkfSkgPT4gdGVzdFRhYklkID0gaWQhKTtcbiAgICB9XG5cbiAgICBjb25zdCBzb2NrZXQgPSBuZXcgV2ViU29ja2V0KGB3czovL2xvY2FsaG9zdDo4ODk0YCk7XG4gICAgc29ja2V0Lm9ub3BlbiA9IGFzeW5jICgpID0+IHtcbiAgICAgICAgLy8gV2FpdCBmb3IgZXh0ZW5zaW9uIHRvIHN0YXJ0XG4gICAgICAgIGF3YWl0IGV4dGVuc2lvbjtcbiAgICAgICAgc29ja2V0LnNlbmQoSlNPTi5zdHJpbmdpZnkoe1xuICAgICAgICAgICAgZGF0YToge1xuICAgICAgICAgICAgICAgIHR5cGU6ICdiYWNrZ3JvdW5kJyxcbiAgICAgICAgICAgICAgICBleHRlbnNpb25PcmlnaW46IGNocm9tZS5ydW50aW1lLmdldFVSTCgnJyksXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgaWQ6IG51bGwsXG4gICAgICAgIH0pKTtcbiAgICB9O1xuICAgIHNvY2tldC5vbm1lc3NhZ2UgPSAoZSkgPT4ge1xuICAgICAgICB0cnkge1xuICAgICAgICAgICAgY29uc3QgbWVzc2FnZTogVGVzdE1lc3NhZ2UgPSBKU09OLnBhcnNlKGUuZGF0YSk7XG4gICAgICAgICAgICBjb25zdCB7aWQsIHR5cGV9ID0gbWVzc2FnZTtcbiAgICAgICAgICAgIGNvbnN0IHJlc3BvbmQgPSAoZGF0YT86IEV4dGVuc2lvbkRhdGEgfCBzdHJpbmcgfCBib29sZWFuIHwge1trZXk6IHN0cmluZ106IHN0cmluZ30gfCBudWxsKSA9PiBzb2NrZXQuc2VuZChKU09OLnN0cmluZ2lmeSh7XG4gICAgICAgICAgICAgICAgZGF0YSxcbiAgICAgICAgICAgICAgICBpZCxcbiAgICAgICAgICAgIH0pKTtcblxuICAgICAgICAgICAgc3dpdGNoICh0eXBlKSB7XG4gICAgICAgICAgICAgICAgY2FzZSAnY2hhbmdlU2V0dGluZ3MnOlxuICAgICAgICAgICAgICAgICAgICBFeHRlbnNpb24uY2hhbmdlU2V0dGluZ3MobWVzc2FnZS5kYXRhKTtcbiAgICAgICAgICAgICAgICAgICAgcmVzcG9uZCgpO1xuICAgICAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgICAgICBjYXNlICdjb2xsZWN0RGF0YSc6XG4gICAgICAgICAgICAgICAgICAgIEV4dGVuc2lvbi5jb2xsZWN0RGF0YSgpLnRoZW4ocmVzcG9uZCk7XG4gICAgICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgICAgIGNhc2UgJ2dldE1hbmlmZXN0Jzoge1xuICAgICAgICAgICAgICAgICAgICBjb25zdCBkYXRhID0gY2hyb21lLnJ1bnRpbWUuZ2V0TWFuaWZlc3QoKTtcbiAgICAgICAgICAgICAgICAgICAgcmVzcG9uZChkYXRhKTtcbiAgICAgICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIGNhc2UgJ2NoYW5nZUNocm9tZVN0b3JhZ2UnOiB7XG4gICAgICAgICAgICAgICAgICAgIGNvbnN0IHJlZ2lvbiA9IG1lc3NhZ2UuZGF0YS5yZWdpb247XG4gICAgICAgICAgICAgICAgICAgIGNocm9tZS5zdG9yYWdlW3JlZ2lvbl0uc2V0KG1lc3NhZ2UuZGF0YS5kYXRhLCAoKSA9PiByZXNwb25kKCkpO1xuICAgICAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgY2FzZSAnZ2V0Q2hyb21lU3RvcmFnZSc6IHtcbiAgICAgICAgICAgICAgICAgICAgY29uc3Qga2V5cyA9IG1lc3NhZ2UuZGF0YS5rZXlzO1xuICAgICAgICAgICAgICAgICAgICBjb25zdCByZWdpb24gPSBtZXNzYWdlLmRhdGEucmVnaW9uO1xuICAgICAgICAgICAgICAgICAgICBjaHJvbWUuc3RvcmFnZVtyZWdpb25dLmdldChrZXlzIGFzIGFueSwgcmVzcG9uZCk7XG4gICAgICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICBjYXNlICdzZXROZXdzJzpcbiAgICAgICAgICAgICAgICAgICAgc2V0TmV3c0ZvclRlc3RpbmcobWVzc2FnZS5kYXRhKTtcbiAgICAgICAgICAgICAgICAgICAgcmVzcG9uZCgpO1xuICAgICAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgICAgICAvLyBUT0RPKGFudG9uKTogcmVtb3ZlIHRoaXMgb25jZSBGaXJlZm94IHN1cHBvcnRzIHRhYi5ldmFsKCkgdmlhIFdlYkRyaXZlciBCaURpXG4gICAgICAgICAgICAgICAgY2FzZSAnZmlyZWZveC1jcmVhdGVUYWInOlxuICAgICAgICAgICAgICAgICAgICBBU1NFUlQoJ0ZpcmVmb3gtc3BlY2lmaWMgZnVuY3Rpb24nLCBpc0ZpcmVmb3gpO1xuICAgICAgICAgICAgICAgICAgICBjaHJvbWUudGFicy51cGRhdGUodGVzdFRhYklkISwge3VybDogbWVzc2FnZS5kYXRhLCBhY3RpdmU6IHRydWV9LCAoKSA9PiByZXNwb25kKCkpO1xuICAgICAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgICAgICBjYXNlICdmaXJlZm94LWdldENvbG9yU2NoZW1lJzoge1xuICAgICAgICAgICAgICAgICAgICBBU1NFUlQoJ0ZpcmVmb3gtc3BlY2lmaWMgZnVuY3Rpb24nLCBpc0ZpcmVmb3gpO1xuICAgICAgICAgICAgICAgICAgICByZXNwb25kKGlzU3lzdGVtRGFya01vZGVFbmFibGVkKCkgPyAnZGFyaycgOiAnbGlnaHQnKTtcbiAgICAgICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIGNhc2UgJ2ZpcmVmb3gtZW11bGF0ZUNvbG9yU2NoZW1lJzoge1xuICAgICAgICAgICAgICAgICAgICBBU1NFUlQoJ0ZpcmVmb3gtc3BlY2lmaWMgZnVuY3Rpb24nLCBpc0ZpcmVmb3gpO1xuICAgICAgICAgICAgICAgICAgICBlbXVsYXRlQ29sb3JTY2hlbWUobWVzc2FnZS5kYXRhKTtcbiAgICAgICAgICAgICAgICAgICAgcmVzcG9uZCgpO1xuICAgICAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9XG4gICAgICAgIH0gY2F0Y2ggKGVycikge1xuICAgICAgICAgICAgc29ja2V0LnNlbmQoSlNPTi5zdHJpbmdpZnkoe2Vycm9yOiBTdHJpbmcoZXJyKSwgb3JpZ2luYWw6IGUuZGF0YX0pKTtcbiAgICAgICAgfVxuICAgIH07XG5cbiAgICBjaHJvbWUuZG93bmxvYWRzLm9uQ3JlYXRlZC5hZGRMaXN0ZW5lcigoe2lkLCBtaW1lLCB1cmwsIGRhbmdlciwgcGF1c2VkfSkgPT4ge1xuICAgICAgICAvLyBDYW5jZWwgZG93bmxvYWRcbiAgICAgICAgY2hyb21lLmRvd25sb2Fkcy5jYW5jZWwoaWQpO1xuXG4gICAgICAgIHRyeSB7XG4gICAgICAgICAgICBjb25zdCB7cHJvdG9jb2wsIG9yaWdpbn0gPSBuZXcgVVJMKHVybCk7XG4gICAgICAgICAgICBjb25zdCByZWFsT3JpZ2luID0gKG5ldyBVUkwoY2hyb21lLnJ1bnRpbWUuZ2V0VVJMKCcnKSkpLm9yaWdpbjtcbiAgICAgICAgICAgIGNvbnN0IG9rID0gcGF1c2VkID09PSBmYWxzZSAmJiBkYW5nZXIgPT09ICdzYWZlJyAmJiBwcm90b2NvbCA9PT0gJ2Jsb2I6JyAmJiBvcmlnaW4gPT09IHJlYWxPcmlnaW47XG4gICAgICAgICAgICBzb2NrZXQuc2VuZChKU09OLnN0cmluZ2lmeSh7XG4gICAgICAgICAgICAgICAgZGF0YToge1xuICAgICAgICAgICAgICAgICAgICB0eXBlOiAnZG93bmxvYWQnLFxuICAgICAgICAgICAgICAgICAgICBvayxcbiAgICAgICAgICAgICAgICAgICAgbWltZSxcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIGlkOiBudWxsLFxuICAgICAgICAgICAgfSkpO1xuICAgICAgICB9IGNhdGNoIChlKSB7XG4gICAgICAgICAgICAvLyBEbyBub3RoaW5nXG4gICAgICAgIH1cbiAgICB9KTtcbn1cblxuaWYgKF9fREVCVUdfXyAmJiBfX0xPR19fKSB7XG4gICAgY2hyb21lLnJ1bnRpbWUub25NZXNzYWdlLmFkZExpc3RlbmVyKChtZXNzYWdlOiBEZWJ1Z01lc3NhZ2VDU3RvQkcpID0+IHtcbiAgICAgICAgaWYgKG1lc3NhZ2UudHlwZSA9PT0gRGVidWdNZXNzYWdlVHlwZUNTdG9CRy5MT0cpIHtcbiAgICAgICAgICAgIHNlbmRMb2cobWVzc2FnZS5kYXRhLmxldmVsLCBtZXNzYWdlLmRhdGEubG9nKTtcbiAgICAgICAgfVxuICAgIH0pO1xufVxuXG5tYWtlQ2hyb21pdW1IYXBweSgpO1xuXG5mdW5jdGlvbiB3cml0ZUluc3RhbGxhdGlvblZlcnNpb24oXG4gICAgc3RvcmFnZTogY2hyb21lLnN0b3JhZ2UuU3luY1N0b3JhZ2VBcmVhIHwgY2hyb21lLnN0b3JhZ2UuTG9jYWxTdG9yYWdlQXJlYSxcbiAgICBkZXRhaWxzOiBjaHJvbWUucnVudGltZS5JbnN0YWxsZWREZXRhaWxzLFxuKSB7XG4gICAgc3RvcmFnZS5nZXQ8UmVjb3JkPHN0cmluZywgYW55Pj4oe2luc3RhbGxhdGlvbjoge3ZlcnNpb246ICcnfX0sIChkYXRhKSA9PiB7XG4gICAgICAgIGlmIChkYXRhPy5pbnN0YWxsYXRpb24/LnZlcnNpb24pIHtcbiAgICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuICAgICAgICBzdG9yYWdlLnNldCh7aW5zdGFsbGF0aW9uOiB7XG4gICAgICAgICAgICBkYXRlOiBEYXRlLm5vdygpLFxuICAgICAgICAgICAgcmVhc29uOiBkZXRhaWxzLnJlYXNvbixcbiAgICAgICAgICAgIHZlcnNpb246IGRldGFpbHMucHJldmlvdXNWZXJzaW9uID8/IGNocm9tZS5ydW50aW1lLmdldE1hbmlmZXN0KCkudmVyc2lvbixcbiAgICAgICAgfX0pO1xuICAgIH0pO1xufVxuXG5jaHJvbWUucnVudGltZS5vbkluc3RhbGxlZC5hZGRMaXN0ZW5lcigoZGV0YWlscykgPT4ge1xuICAgIHdyaXRlSW5zdGFsbGF0aW9uVmVyc2lvbihjaHJvbWUuc3RvcmFnZS5sb2NhbCwgZGV0YWlscyk7XG4gICAgd3JpdGVJbnN0YWxsYXRpb25WZXJzaW9uKGNocm9tZS5zdG9yYWdlLnN5bmMsIGRldGFpbHMpO1xufSk7XG4iXSwibmFtZXMiOlsiY3JlYXRlQ1NTRmlsdGVyU3R5bGVzaGVldCJdLCJtYXBwaW5ncyI6Ijs7O0lBdUJBLE1BQU0sa0JBQWtCLEdBQUcsT0FBTyxTQUFTLEtBQUssV0FBVztJQUMzRCxNQUFNLFNBQVMsR0FBRyxrQkFBa0IsR0FBRyxDQUFDLFNBQVMsQ0FBQyxhQUFhLElBQUksS0FBSyxDQUFDLE9BQU8sQ0FBQyxTQUFTLENBQUMsYUFBYSxDQUFDLE1BQU0sQ0FBQztJQUM1RyxJQUFBLFNBQVMsQ0FBQyxhQUFhLENBQUMsTUFBTSxDQUFDLEdBQUcsQ0FBQyxDQUFDLEtBQUssS0FBSyxDQUFBLEVBQUcsS0FBSyxDQUFDLEtBQUssQ0FBQyxXQUFXLEVBQUUsQ0FBQSxDQUFBLEVBQUksS0FBSyxDQUFDLE9BQU8sQ0FBQSxDQUFFLENBQUMsQ0FBQyxJQUFJLENBQUMsR0FBRyxDQUFDLEdBQUcsU0FBUyxDQUFDLFNBQVMsQ0FBQyxXQUFXO1VBQ3hJLGdCQUFnQjtJQUV0QixNQUFNLFFBQVEsR0FBRyxrQkFBa0Is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Q0FBQyxHQUFHLEdBQUcsRUFBRTtnQkFDVCxDQUFDLElBQUksR0FBRztZQUNaO0lBQU8sYUFBQSxJQUFJLENBQUMsR0FBRyxDQUFDLEVBQUU7Z0JBQ2QsQ0FBQyxJQUFJLEdBQUc7WUFDWjs7SUFHQSxRQUFBLElBQUksRUFBRSxHQUFHLEdBQUcsR0FBRyxJQUFJLENBQUMsSUFBSSxDQUFDLE9BQU8sR0FBRyxJQUFJLENBQUMsR0FBRyxDQUFDLENBQUMsR0FBRyxHQUFHLENBQUMsQ0FBQztJQUNyRCxRQUFBLElBQUksRUFBRSxHQUFHLEdBQUcsRUFBRTtnQkFDVixFQUFFLElBQUksR0FBRztZQUNiO0lBQU8sYUFBQSxJQUFJLEVBQUUsR0FBRyxDQUFDLEVBQUU7Z0JBQ2YsRUFBRSxJQUFJLEdBQUc7WUFDYjs7SUFHQSxRQUFBLE1BQU0sU0FBUyxHQUFHLENBQUMsSUFBSSxDQUFDLEtBQUssQ0FBQyxDQUFDLElBQUksRUFBRSxDQUFDLENBQUMsSUFBSSxFQUFFO0lBQzdDLFFBQUEsTUFBTSxVQUFVLEdBQUcsQ0FBQyxJQUFJLENBQUMsS0FBSyxDQUFDLEVBQUUsR0FBRyxFQUFFLENBQUMsSUFBSSxFQUFFO0lBQzdDLFFBQUEsRUFBRSxLQUFLLFNBQVMsR0FBRyxVQUFVLENBQUM7O1lBRzlCLEVBQUUsSUFBSSxFQUFFOztJQUdSLFFBQUEsTUFBTSxNQUFNLEdBQUcsT0FBTyxHQUFHLElBQUksQ0FBQyxHQUFHLENBQUMsQ0FBQyxHQUFHLEdBQUcsQ0FBQztJQUMxQyxRQUFBLE1BQU0sTUFBTSxHQUFHLElBQUksQ0FBQyxHQUFHLENBQUMsSUFBSSxDQUFDLElBQUksQ0FBQyxNQUFNLENBQUMsQ0FBQzs7SUFHMUMsUUFBQSxNQUFNLElBQUksR0FBRyxDQUFDLElBQUksQ0FBQyxHQUFHLENBQUMsTUFBTSxHQUFHLEdBQUcsQ0FBQyxJQUFJLE1BQU0sR0FBRyxJQUFJLENBQUMsR0FBRyxDQUFDLFFBQVEsR0FBRyxHQUFHLENBQUMsQ0FBQyxLQUFLLE1BQU0sR0FBRyxJQUFJLENBQUMsR0FBRyxDQUFDLFFBQVEs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R0FBRyxFQUFFLEdBQUcsQ0FBQyxFQUFFLEVBQUUsQ0FBQyxFQUFFLENBQUMsTUFBTSxDQUFDLENBQUMsRUFBRSxDQUFDLEVBQUUsQ0FBQyxDQUFDLEtBQUssQ0FBQSxFQUFHLENBQUMsQ0FBQSxTQUFBLEVBQVksQ0FBQyxDQUFBLE1BQUEsQ0FBUSxDQUFDO1FBQy9KLGFBQWEsQ0FBQyxDQUFDLENBQUMsS0FBSyxDQUFDLENBQUMsV0FBVyxFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxPQUFBLEVBQVUsR0FBRyxDQUFDLENBQUMsQ0FBQyxXQUFXLENBQUMsQ0FBQSxDQUFFLENBQUMsQ0FBQztRQUM1RSxhQUFhLENBQUMsQ0FBQyxDQUFDLEtBQUssQ0FBQyxDQUFDLGlCQUFpQixFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxPQUFBLEVBQVUsR0FBRyxDQUFDLENBQUMsQ0FBQyxXQUFXLENBQUMsQ0FBQSxDQUFFLENBQUMsQ0FBQztRQUNsRixhQUFhLENBQUMsQ0FBQyxDQUFDLEtBQUssQ0FBQyxDQUFDLGlCQUFpQixFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxPQUFBLEVBQVUsR0FBRyxDQUFDLEdBQUcsQ0FBQyxDQUFDLENBQUMsV0FBVyxFQUFFLENBQUMsR0FBRyxFQUFFLEdBQUcsRUFBRSxHQUFHLENBQUMsRUFBRSxFQUFFLENBQUMsRUFBRSxDQUFDLEtBQUssQ0FBQyxDQUFDLENBQUEsQ0FBRSxDQUFDLEVBQUUsQ0FBQyxDQUFDLEtBQUssQ0FBQSxFQUFHLENBQUMsQ0FBQSxNQUFBLENBQVEsQ0FBQztRQUMxSSxhQUFhLENBQUMsQ0FBQyxDQUFDLEtBQUssQ0FBQyxDQUFDLGlCQUFpQixFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxPQUFBLEVBQVUsR0FBRyxDQUFDLEdBQUcsQ0FBQyxDQUFDLENBQUMsV0FBVyxFQUFFLENBQUMsR0FBRyxFQUFFLEdBQUcsRUFBRSxHQUFHLENBQUMsRUFBRSxFQUFFLENBQUMsRUFBRSxDQUFDLE1BQU0sQ0FBQyxDQUFDLEVBQUUsQ0FBQyxFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUEsRUFBRyxDQUFDLENBQUEsU0FBQSxFQUFZLENBQUMsQ0FBQSxNQUFBLENBQVEsQ0FBQztJQUN4SixJQUFBLGFBQWEsQ0FBQyxDQUFDLENBQUMsS0FBSyxDQUFDLENBQUMsYUFBYSxFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxjQUFBLEVBQWlCLEdBQUcsQ0FBQyxHQUFHLENBQUMsQ0FBQyxDQUFDLFNBQVMsRUFBRSxDQUFDLENBQUMsV0FBVyxFQUFFLEVBQUUsQ0FBQyxNQUFNLENBQUMsQ0FBQyxDQUFBLENBQUUsQ0FBQyxDQUFDO1FBRWxILGFBQWEsQ0FBQyxDQUFDLENBQUMsS0FBSyxDQUFDLENBQUMsS0FBSyxFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxrQkFBQSxFQUFxQixHQUFHLENBQUMsQ0FBQyxDQUFDLEtBQUssQ0FBQyxDQUFBLENBQUUsQ0FBQyxDQUFDO1FBQzNFLGFBQWEsQ0FBQyxDQUFDLENBQUMsS0FBSyxDQUFDLENBQUMsV0FBVyxFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxrQkFBQSxFQUFxQixHQUFHLENBQUMsQ0FBQyxDQUFDLEtBQUssQ0FBQyxDQUFBLENBQUUsQ0FBQyxDQUFDO1FBQ2pGLGFBQWEsQ0FBQyxDQUFDLENBQUMsS0FBSyxDQUFDLENBQUMsV0FBVyxFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxrQkFBQSxFQUFxQixHQUFHLENBQUMsR0FBRyxDQUFDLENBQUMsQ0FBQyxLQUFLLEVBQUUsQ0FBQyxHQUFHLEVBQUUsQ0FBQyxFQUFFLEVBQUUsQ0FBQyxFQUFFLEVBQUUsQ0FBQyxFQUFFLENBQUMsS0FBSyxDQUFDLENBQUMsQ0FBQSxDQUFFLENBQUMsRUFBRSxDQUFDLENBQUMsS0FBSyxDQUFBLEVBQUcsQ0FBQyxDQUFBLE1BQUEsQ0FBUSxDQUFDO1FBQ3RJLGFBQWEsQ0FBQyxDQUFDLENBQUMsS0FBSyxDQUFDLENBQUMsV0FBVyxFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxrQkFBQSxFQUFxQixHQUFHLENBQUMsR0FBRyxDQUFDLENBQUMsQ0FBQyxLQUFLLEVBQUUsQ0FBQyxHQUFHLEVBQUUsQ0FBQyxFQUFFLEVBQUUsQ0FBQyxFQUFFLEVBQUUsQ0FBQyxFQUFFLENBQUMsTUFBTSxDQUFDLENBQUMsRUFBRSxDQUFDLEVBQUUsQ0FBQyxDQUFDLEtBQUssQ0FBQSxFQUFHLENBQUMsQ0FBQSxTQUFBLEVBQVksQ0FBQyxDQUFBLE1BQUEsQ0FBUSxDQUFDO1FBQ3BKLGFBQWEsQ0FBQyxDQUFDLENBQUMsS0FBSyxDQUFDLENBQUMsT0FBTyxFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxPQUFBLEVBQVUsR0FBRyxDQUFDLENBQUMsQ0FBQyxPQUFPLENBQUMsQ0FBQSxDQUFFLENBQUMsQ0FBQztRQUNwRSxhQUFhLENBQUMsQ0FBQyxDQUFDLEtBQUssQ0FBQyxDQUFDLGFBQWEsRUFBRSxDQUFDLENBQUMsS0FBSyxDQUFDLENBQUEsT0FBQSxFQUFVLEdBQUcsQ0FBQyxDQUFDLENBQUMsT0FBTyxDQUFDLENBQUEsQ0FBRSxDQUFDLENBQUM7UUFDMUUsYUFBYSxDQUFDLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQyxhQUFhLEVBQUUsQ0FBQyxDQUFDLEtBQUssQ0FBQyxDQUFBLE9BQUEsRUFBVSxHQUFHLENBQUMsR0FBRyxDQUFDLENBQUMsQ0FBQyxPQUFPLEVBQUUsQ0FBQyxHQUFHLEVBQUUsR0FBRyxFQUFFLENBQUMsQ0FBQyxFQUFFLEVBQUUsQ0FBQyxFQUFFLENBQUMsS0FBSyxDQUFDLENBQUMsQ0FBQSxDQUFFLENBQUMsRUFBRSxDQUFDLENBQUMsS0FBSyxDQUFBLEVBQUcsQ0FBQyxDQUFBLE1BQUEsQ0FBUSxDQUFDO1FBQ2hJLGFBQWEsQ0FBQyxDQUFDLENBQUMsS0FBSyxDQUFDLENBQUMsYUFBYSxFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxPQUFBLEVBQVUsR0FBRyxDQUFDLEdBQUcsQ0FBQyxDQUFDLENBQUMsT0FBTyxFQUFFLENBQUMsR0FBRyxFQUFFLEdB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LEVBQVUsR0FBRyxDQUFDLEdBQUcsQ0FBQyxDQUFDLENBQUMsU0FBUyxFQUFFLENBQUMsR0FBRyxFQUFFLEdBQUcsRUFBRSxHQUFHLENBQUMsRUFBRSxFQUFFLENBQUMsRUFBRSxDQUFDLE1BQU0sQ0FBQyxDQUFDLEVBQUUsQ0FBQyxFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUEsRUFBRyxDQUFDLENBQUEsU0FBQSxFQUFZLENBQUMsQ0FBQSxNQUFBLENBQVEsQ0FBQztJQUNwSixJQUFBLGFBQWEsQ0FBQyxDQUFDLENBQUMsS0FBSyxDQUFDLENBQUMsV0FBVyxFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxjQUFBLEVBQWlCLEdBQUcsQ0FBQyxHQUFHLENBQUMsQ0FBQyxDQUFDLE9BQU8sRUFBRSxDQUFDLENBQUMsU0FBUyxFQUFFLEVBQUUsQ0FBQyxNQUFNLENBQUMsQ0FBQyxDQUFBLENBQUUsQ0FBQyxDQUFDO1FBRTVHLGFBQWEsQ0FBQyxDQUFDLENBQUMsS0FBSyxDQUFDLENBQUMsTUFBTSxFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxrQkFBQSxFQUFxQixHQUFHLENBQUMsQ0FBQyxDQUFDLE1BQU0sQ0FBQyxDQUFBLENBQUUsQ0FBQyxDQUFDO1FBQzdFLGFBQWEsQ0FBQyxDQUFDLENBQUMsS0FBSyxDQUFDLENBQUMsWUFBWSxFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxrQkFBQSxFQUFxQixHQUFHLENBQUMsQ0FBQyxDQUFDLE1BQU0sQ0FBQyxDQUFBLENBQUUsQ0FBQyxDQUFDO1FBQ25GLGFBQWEsQ0FBQyxDQUFDLENBQUMsS0FBSyxDQUFDLENBQUMsWUFBWSxFQUFFLENBQUMsQ0FBQyxLQUFLLENBQUMsQ0FBQSxrQkFBQSxFQUFxQixHQUFHLENBQUMsR0FBRyxDQUFDLENBQUMsQ0FBQyxNQUFNLEVBQUUsQ0FBQyxDQUFDLEVBQUUsR0FBRyxFQUFFLEdBQUcsQ0FBQyxFQUFFLEVBQUUsQ0FBQyxFQUFFLENBQUMsS0FBSyxDQUFDLENBQUMsQ0FBQSxDQUFFLENBQUMsRUFB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
