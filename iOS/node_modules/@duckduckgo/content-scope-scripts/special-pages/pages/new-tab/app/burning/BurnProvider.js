import { h, createContext } from 'preact';
import { useCallback, useContext } from 'preact/hooks';
import { batch, signal, useSignal, useSignalEffect } from '@preact/signals';
import { useEnv } from '../../../../shared/components/EnvironmentProvider.js';
import { ActivityInteractionsContext } from './ActivityInteractionsContext.js';

export const ACTION_BURN = 'burn';

export const ActivityBurningSignalContext = createContext({
    /** @type {import("@preact/signals").Signal<string[]>} */
    burning: signal([]),
    /** @type {import("@preact/signals").Signal<string[]>} */
    exiting: signal([]),
    /** @type {import("@preact/signals").Signal<{state: 'loading' | 'ready' | 'error', data: null | Record<string, any>}>} */
    animation: signal({ state: 'loading', data: null }),
    /** @type {boolean} */
    showBurnAnimation: true,
    /** @type {(url: string) => void} */
    doneBurning: (_url) => {},
});

/**
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 * @param {{confirmBurn: (url: string) => Promise<{action: 'burn' | 'none'}>; disableBroadcast: () => void; enableBroadcast: () => void }} props.service
 * @param {boolean} [props.showBurnAnimation] - defaults to true to match original implementation
 *
 */
export function BurnProvider({ children, service, showBurnAnimation = true }) {
    const burning = useSignal(/** @type {string[]} */ ([]));
    const exiting = useSignal(/** @type {string[]} */ ([]));
    const animation = useSignal({ state: /** @type {'loading' | 'ready' | 'error'} */ ('loading'), data: null });
    const { didClick: originalDidClick } = useContext(ActivityInteractionsContext);
    const { isReducedMotion } = useEnv();

    async function didClick(e) {
        const button = /** @type {HTMLButtonElement|null} */ (e.target?.closest(`button[value][data-action="${ACTION_BURN}"]`));
        if (!button) return originalDidClick(e);
        if (!service) throw new Error('unreachable');

        e.preventDefault();
        e.stopImmediatePropagation();

        if (burning.value.length > 0 || exiting.value.length > 0) return;

        const value = button.value;
        const response = await service?.confirmBurn(value);
        if (response && response.action === 'none') return;

        // stop the service broadcasting any updates for a moment
        service.disableBroadcast();

        // mark this item as burning - this will prevent further events until we're done
        burning.value = burning.value.concat(value);

        // wait for a signal from the FE that we can continue
        const feSignals = any(reducedMotion(isReducedMotion), animationExit(), didChangeDocumentVisibility());

        // the signal from native that burning was complete
        const nativeSignal = didCompleteNatively(service);

        // at least 1 FE signal + 1 native signal is required to continue
        const required = all(feSignals, nativeSignal);

        // but don't wait any longer than 3 seconds
        const withTimer = any(required, timer(3000));

        // exec the chain
        await toPromise(withTimer);

        // when we get here, clear out all state
        batch(() => {
            exiting.value = [];
            burning.value = [];
        });

        // and re-enable the data broadcasting
        service?.enableBroadcast();
    }

    useSignalEffect(() => {
        let cancelled = false;
        async function fetchAnimation() {
            const resp = await fetch('burn.json');
            if (!resp.ok) {
                animation.value = { state: /** @type {const} */ ('error'), data: null };
                return;
            }
            const json = await resp.json();
            if (!cancelled) animation.value = { state: 'ready', data: json };
        }
        fetchAnimation()
            // eslint-disable-next-line promise/prefer-await-to-then
            .catch((_) => {
                animation.value = { state: /** @type {const} */ ('error'), data: null };
            });
        return () => {
            cancelled = true;
        };
    });

    /** @type {(url: string) => void} */
    const doneBurning = useCallback(
        (url) => {
            if (url) {
                batch(() => {
                    burning.value = burning.value.filter((x) => x !== url);
                    exiting.value = exiting.value.concat(url);
                });
            }
        },
        [burning, exiting],
    );

    return (
        <ActivityBurningSignalContext.Provider value={{ burning, exiting, animation, showBurnAnimation, doneBurning }}>
            <ActivityInteractionsContext.Provider value={{ didClick }}>{children}</ActivityInteractionsContext.Provider>
        </ActivityBurningSignalContext.Provider>
    );
}

function toPromise(fn) {
    return new Promise((resolve) => {
        const cleanup = fn({
            next: (v) => {
                resolve(v);
                cleanup();
            },
        });
    });
}

function reducedMotion(isReducedMotion) {
    return (subject) => {
        if (isReducedMotion) {
            subject.next();
        }
    };
}

function animationExit() {
    return (subject) => {
        const handler = () => {
            subject.next();
        };
        window.addEventListener('done-exiting', handler, { once: true });
        return () => {
            window.removeEventListener('done-exiting', handler);
        };
    };
}

function timer(ms) {
    return (subject) => {
        const int = setTimeout(() => {
            return subject.next();
        }, ms);
        return () => {
            clearTimeout(int);
        };
    };
}

function didCompleteNatively(service) {
    return (subject) => {
        const unsub = service?.onBurnComplete(() => {
            subject.next();
        });
        return () => {
            unsub();
        };
    };
}

function didChangeDocumentVisibility() {
    return (subject) => {
        const handler = () => {
            return subject.next(document.visibilityState);
        };
        document.addEventListener('visibilitychange', handler, { once: true });
        return () => {
            window.removeEventListener('visibilitychange', handler);
        };
    };
}

function any(...fns) {
    return (subject) => {
        const jobs = fns.map((factory) => {
            const subject = {
                /** @type {any} */
                next: undefined,
            };
            const promise = new Promise((resolve) => (subject.next = resolve));
            const cleanup = factory(subject);
            return {
                promise,
                cleanup,
            };
        });

        Promise.any(jobs.map((x) => x.promise))
            // eslint-disable-next-line promise/prefer-await-to-then
            .then((d) => subject.next(d))
            // eslint-disable-next-line promise/prefer-await-to-then
            .catch(console.error);

        return () => {
            for (const job of jobs) {
                job.cleanup?.();
            }
        };
    };
}

function all(...fns) {
    return (subject) => {
        const jobs = fns.map((factory) => {
            const subject = {
                /** @type {any} */
                next: undefined,
            };
            const promise = new Promise((resolve) => (subject.next = resolve));
            const cleanup = factory(subject);
            return {
                promise,
                cleanup,
            };
        });

        Promise.all(jobs.map((x) => x.promise))
            // eslint-disable-next-line promise/prefer-await-to-then
            .then((d) => subject.next(d))
            // eslint-disable-next-line promise/prefer-await-to-then
            .catch(console.error);

        return () => {
            for (const job of jobs) {
                job.cleanup?.();
            }
        };
    };
}
