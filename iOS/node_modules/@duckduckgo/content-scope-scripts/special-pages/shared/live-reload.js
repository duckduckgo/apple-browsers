/**
 * This file can be included to support live-reloading of CSS
 * Just import it somewhere, like this (it will be stripped from other builds)
 *
 * ```js
 * import '../../../shared/live-reload.js';
 * ```
 */
// eslint-disable-next-line no-labels,no-unused-labels
$WATCH: (() => {
    if (window.__playwright_01) return;
    fetch('dist/timestamp.json')
        // eslint-disable-next-line promise/prefer-await-to-then
        .then((x) => x.json())
        // eslint-disable-next-line promise/prefer-await-to-then
        .then(display)
        // eslint-disable-next-line promise/prefer-await-to-then
        .catch(console.error);

    const es = new EventSource('/esbuild');
    es.addEventListener('change', (e) => {
        // eslint-disable-next-line @typescript-eslint/ban-ts-comment
        // @ts-ignore - this will always be present in watch mode
        // eslint-disable-next-line promise/prefer-await-to-then
        import('../timestamp.json').then((x) => {
            // noop to force reload
        });
        const { added, removed, updated } = JSON.parse(e.data);
        const all = [...added, ...removed, ...updated];
        const filtered = all.filter((x) => !x.endsWith('.map'));
        const allcss = filtered.length > 0 && filtered.every((x) => x.endsWith('.css'));
        if (allcss) {
            for (const link of document.getElementsByTagName('link')) {
                if (!(link instanceof HTMLLinkElement)) return;
                const url = new URL(link.href);
                if (url.host === location.host && url.pathname === updated[0]) {
                    const next = /** @type {HTMLLinkElement} */ (link.cloneNode());
                    next.href = updated[0] + '?' + Math.random().toString(36).slice(2);
                    next.onload = () => link.remove();
                    link.parentNode?.insertBefore(next, link.nextSibling);
                    return;
                }
            }
        }
        console.log('reloading because', { added, removed, updated });
        if (location.search.includes('no-reload')) return;
        location.reload();
    });
})();

/**
 * @param {{now: number, stdout: string, stderr: string, didError: string, event: string|null, path: string|null}} timestamp
 */
function display(timestamp) {
    const { didError, stdout, stderr, event, path } = timestamp;
    const unixts = timestamp.now;
    const delta = Date.now() - unixts;
    if (didError) {
        console.groupCollapsed(`❌ ${didError} failed ${delta / 1000}s ago ${path ? `(${path})` : ''}`);
        if (stderr.trim().length) console.error(stderr);
        if (event && path) {
            console.log(` -> triggered by ${event} on ${path}`);
        }
        if (stdout.trim().length) console.log(stdout);
        console.groupEnd();
    }
}
