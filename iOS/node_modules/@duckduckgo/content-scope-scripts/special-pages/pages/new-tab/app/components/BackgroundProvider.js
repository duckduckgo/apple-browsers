import { Fragment, h } from 'preact';
import styles from './BackgroundReceiver.module.css';
import { values } from '../customizer/values.js';
import { useContext, useEffect, useState } from 'preact/hooks';
import { CustomizerContext } from '../customizer/CustomizerProvider.js';
import { detectThemeFromHex } from '../customizer/utils.js';
import { useSignalEffect } from '@preact/signals';
import { memo } from 'preact/compat';

/**
 * @import { BackgroundVariant, BrowserTheme } from "../../types/new-tab"
 */

/**
 * @param {BackgroundVariant} background
 * @param {BrowserTheme} browserTheme
 * @param {'light' | 'dark'} system
 * @return {{bg: 'light' | 'dark', browser: 'light' | 'dark'}}
 */
export function inferSchemeFrom(background, browserTheme, system) {
    const browser = themeFromBrowser(browserTheme, system);
    switch (background.kind) {
        case 'default':
            return { bg: browser, browser };
        case 'color': {
            const color = values.colors[background.value];
            return { bg: color.colorScheme, browser };
        }

        case 'gradient': {
            const gradient = values.gradients[background.value];
            return { bg: gradient.colorScheme, browser };
        }

        case 'userImage':
            return { bg: background.value.colorScheme, browser };

        case 'hex':
            return { bg: detectThemeFromHex(background.value), browser };
    }
}

/**
 * @param {BrowserTheme} browserTheme
 * @param {'light' | 'dark'} system
 * @return {'light' | 'dark'}
 */
export function themeFromBrowser(browserTheme, system) {
    if (browserTheme === 'system') {
        return system;
    }
    return browserTheme;
}

/**
 * @param {object} props
 * @param {import("@preact/signals").Signal<'light' | 'dark'>} props.browser
 */
export function BackgroundConsumer({ browser }) {
    const { data } = useContext(CustomizerContext);
    const background = data.value.background;

    useSignalEffect(() => {
        const background = data.value.background;

        // reflect some values onto the <body> tag
        document.body.dataset.backgroundKind = background.kind;
        let nextBodyBackground = '';

        if (background.kind === 'gradient') {
            const gradient = values.gradients[background.value];
            nextBodyBackground = gradient.fallback;
        }
        if (background.kind === 'color') {
            const color = values.colors[background.value];
            nextBodyBackground = color.hex;
        }
        if (background.kind === 'hex') {
            nextBodyBackground = background.value;
        }
        if (background.kind === 'userImage') {
            const isDark = background.value.colorScheme === 'dark';
            nextBodyBackground = isDark ? 'var(--default-dark-background-color)' : 'var(--default-light-background-color)';
        }
        if (background.kind === 'default') {
            nextBodyBackground =
                browser.value === 'dark' ? 'var(--default-dark-background-color)' : 'var(--default-light-background-color)';
        }

        document.body.style.setProperty('background-color', nextBodyBackground);

        // let animations occur, after properties above have been flushed to the DOM
        if (!document.body.dataset.animateBackground) {
            requestAnimationFrame(() => {
                document.body.dataset.animateBackground = 'true';
            });
        }
    });

    switch (background.kind) {
        case 'color':
        case 'default':
        case 'hex': {
            return null;
        }
        case 'userImage': {
            const img = background.value;
            return <ImageCrossFade src={img.src} />;
        }
        case 'gradient': {
            const gradient = values.gradients[background.value];
            return (
                <Fragment>
                    <ImageCrossFade src={gradient.path} />
                    <div
                        className={styles.root}
                        style={{
                            backgroundImage: `url(gradients/grain.png)`,
                            backgroundRepeat: 'repeat',
                            opacity: 0.5,
                            mixBlendMode: 'soft-light',
                        }}
                    />
                </Fragment>
            );
        }
        default: {
            console.warn('Unreachable!');
            return null;
        }
    }
}

/**
 * @typedef {'idle'
 *  | 'loadingFirst'
 *  | 'loading'
 *  | 'fading'
 *  | 'settled'
 * } ImgState
 */

/**
 * @type {Record<ImgState, ImgState>}
 */
const states = {
    idle: 'idle',
    loadingFirst: 'loadingFirst',
    loading: 'loading',
    fading: 'fading',
    settled: 'settled',
};

/**
 * @param {object} props
 * @param {string} props.src
 */
function ImageCrossFade_({ src }) {
    const [state, setState] = useState({
        /** @type {ImgState} */
        value: states.idle,
        current: src,
        next: src,
    });

    useEffect(() => {
        /** @type {HTMLImageElement|undefined} */
        let img = new Image();
        let cancelled = false;

        // Mark the component as being in a 'loading' state, without
        // explicit changes to any DOM
        setState((prev) => {
            // prettier-ignore
            const nextState = prev.value === states.idle
                ? states.loadingFirst
                : states.loading
            return { ...prev, value: nextState };
        });

        /** @type {(()=>void)|undefined} */
        let handler = () => {
            if (cancelled) return;
            setState((prev) => {
                // when coming from a 'loading' states, we can fade
                if (prev.value === states.loading) {
                    return { ...prev, value: states.fading, next: src };
                }
                return prev;
            });
        };

        // trigger the load in memory, not on screen
        img.addEventListener('load', handler);
        img.src = src;

        return () => {
            cancelled = true;
            if (img && handler) {
                img.removeEventListener('load', handler);
                img = undefined;
                handler = undefined;
            }
        };
    }, [src]);

    switch (state.value) {
        case states.settled:
        case states.loadingFirst:
            return <img class={styles.root} data-state={state.value} src={state.current} alt="" />;
        case states.loading:
        case states.fading:
            return (
                <Fragment>
                    <img class={styles.root} data-state={state.value} src={state.current} alt="" />
                    <img
                        class={styles.root}
                        data-state={state.value}
                        src={state.next}
                        onLoad={(e) => {
                            const elem = /** @type {HTMLImageElement} */ (e.target);

                            // HACK: This is what I needed to force, to get 100% predictability. 🤷
                            elem.style.opacity = '0';

                            const anim = elem.animate([{ opacity: '0' }, { opacity: '1' }], {
                                duration: 250,
                                iterations: 1,
                                fill: 'both',
                            });

                            // when the fade completes, we want to reset the stable `src`.
                            // This allows the image underneath to be updated but also allows us to un-mount the fader on top.
                            anim.onfinish = () => {
                                setState((prev) => {
                                    return { ...prev, value: states.settled, current: prev.next, next: prev.next };
                                });
                            };
                        }}
                    />
                </Fragment>
            );
        default:
            return null;
    }
}

const ImageCrossFade = memo(ImageCrossFade_);
