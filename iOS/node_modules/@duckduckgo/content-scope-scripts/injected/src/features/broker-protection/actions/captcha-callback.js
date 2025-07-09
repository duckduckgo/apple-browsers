/**
 * @param {object} args
 * @param {string} args.token
 */
export function captchaCallback(args) {
    const clients = findRecaptchaClients(globalThis);

    // if a client was found, check there was a function
    if (clients.length === 0) {
        return console.log('cannot find clients');
    }

    if (typeof clients[0].function === 'function') {
        try {
            clients[0].function(args.token);
            console.log('called function with path', clients[0].callback);
        } catch (e) {
            console.error('could not call function');
        }
    }

    /**
     * Try to find a callback in a path such as ['___grecaptcha_cfg', 'clients', '0', 'U', 'U', 'callback']
     * @param {Record<string, any>} target
     */
    function findRecaptchaClients(target) {
        if (typeof target.___grecaptcha_cfg === 'undefined') {
            console.log('target.___grecaptcha_cfg not found in ', location.href);
            return [];
        }
        return Object.entries(target.___grecaptcha_cfg.clients || {}).map(([cid, client]) => {
            const cidNumber = parseInt(cid, 10);
            const data = {
                id: cid,
                version: cidNumber >= 10000 ? 'V3' : 'V2',
            };
            const objects = Object.entries(client).filter(([, value]) => value && typeof value === 'object');

            objects.forEach(([toplevelKey, toplevel]) => {
                const found = Object.entries(toplevel).find(
                    ([, value]) => value && typeof value === 'object' && 'sitekey' in value && 'size' in value,
                );

                if (
                    typeof toplevel === 'object' &&
                    typeof HTMLElement !== 'undefined' &&
                    toplevel instanceof HTMLElement &&
                    toplevel.tagName === 'DIV'
                ) {
                    data.pageurl = toplevel.baseURI;
                }

                if (found) {
                    const [sublevelKey, sublevel] = found;

                    data.sitekey = sublevel.sitekey;
                    const callbackKey = data.version === 'V2' ? 'callback' : 'promise-callback';
                    const callback = sublevel[callbackKey];
                    if (!callback) {
                        data.callback = null;
                        data.function = null;
                    } else {
                        data.function = callback;
                        data.callback = ['___grecaptcha_cfg', 'clients', cid, toplevelKey, sublevelKey, callbackKey];
                    }
                }
            });
            return data;
        });
    }
}
