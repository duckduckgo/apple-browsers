export const DEFAULT_RETRY_CONFIG = {
    interval: { ms: 0 },
    maxAttempts: 1,
};

/**
 * A generic retry mechanism for synchronous functions that return
 * a 'success' or 'error' response
 *
 * @template T
 * @template {{ success: T } | { error: { message: string } }} FnReturn
 * @param {() => Promise<FnReturn>} fn
 * @param {typeof DEFAULT_RETRY_CONFIG} [config]
 * @return {Promise<{ result: FnReturn | undefined, exceptions: string[] }>}
 */
export async function retry(fn, config = DEFAULT_RETRY_CONFIG) {
    let lastResult;
    const exceptions = [];
    for (let i = 0; i < config.maxAttempts; i++) {
        try {
            lastResult = await Promise.resolve(fn());
        } catch (e) {
            exceptions.push(e.toString());
        }

        // stop when there's a good result to return
        // since fn() returns either { success: <value> } or { error: ... }
        if (lastResult && 'success' in lastResult) break;

        // don't pause on the last item
        if (i === config.maxAttempts - 1) break;

        await new Promise((resolve) => setTimeout(resolve, config.interval.ms));
    }

    return { result: lastResult, exceptions };
}
