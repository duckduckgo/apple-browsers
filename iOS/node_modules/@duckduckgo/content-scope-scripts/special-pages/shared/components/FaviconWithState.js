import { h } from 'preact';
import { useState } from 'preact/hooks';
import cn from 'classnames';
import styles from './FaviconWithState.module.css';
import { urlToColor } from '../getColorForString.js';

/**
 * @typedef {'loading_favicon_src'
 * | 'did_load_favicon_src'
 * | 'loading_fallback_img'
 * | 'did_load_fallback_img'
 * | 'using_fallback_text'
 * | 'fallback_img_failed'
 * } ImgState
 */
const states = /** @type {Record<ImgState, ImgState>} */ ({
    loading_favicon_src: 'loading_favicon_src',
    did_load_favicon_src: 'did_load_favicon_src',

    loading_fallback_img: 'loading_fallback_img',
    did_load_fallback_img: 'did_load_fallback_img',
    fallback_img_failed: 'fallback_img_failed',

    using_fallback_text: 'using_fallback_text',
});

/**
 *
 * Loads and displays an image for a given webpage.
 *
 * @param {Object} props - The props for the image loader.
 * @param {string|null|undefined} props.faviconSrc - The URL of the favicon image to load.
 * @param {number} [props.defaultSize] - The default size for the display of the favicon
 * @param {string} props.fallback - The URL of the fallback
 * @param {string} props.fallbackDark - The URL of the dark fallback
 * @param {string|null|undefined} props.faviconSrc - The URL of the favicon image to load.
 * @param {number} props.faviconMax - The maximum size this icon be displayed as
 * @param {'light' | 'dark'} props.theme - the currently applied theme
 * @param {'favorite-tile' | 'history-favicon'} props.displayKind
 * @param {string|null} props.etldPlusOne - The relevant domain section of the url
 */
export function FaviconWithState({ defaultSize = 64, fallback, fallbackDark, faviconSrc, faviconMax, etldPlusOne, theme, displayKind }) {
    const size = Math.min(faviconMax, defaultSize);
    const sizeClass = displayKind === 'favorite-tile' ? styles.faviconLarge : styles.faviconSmall;

    // try to use the defined image source
    // prettier-ignore
    const imgsrc = faviconSrc
        ? faviconSrc + '?preferredSize=' + size
        : null;

    // prettier-ignore
    const initialState = (() => {
        /**
         * If the favicon has `src`, always prefer it
         */
        if (imgsrc) return states.loading_favicon_src;
        /**
         * Failing that, use fallback text if possible
         */
        if (etldPlusOne) return states.using_fallback_text;
        /**
         * If we get here, we have no favicon src, and no chance of using fallback text
         */
        return states.loading_fallback_img;
    })();

    const [state, setState] = useState(/** @type {ImgState} */ (initialState));

    switch (state) {
        /**
         * These are the happy paths, where we are loading the favicon source and it does not 404
         */
        case states.loading_favicon_src:
        case states.did_load_favicon_src: {
            if (!imgsrc) {
                console.warn('unreachable - must have imgsrc here');
                return null;
            }
            return (
                <img
                    src={imgsrc}
                    class={cn(styles.favicon, sizeClass)}
                    alt=""
                    data-state={state}
                    onLoad={() => setState(states.did_load_favicon_src)}
                    onError={() => {
                        if (etldPlusOne) {
                            setState(states.using_fallback_text);
                        } else {
                            setState(states.loading_fallback_img);
                        }
                    }}
                />
            );
        }
        /**
         * A fallback can be applied when the `etldPlusOne` is there. For example,
         * if `etldPlusOne = 'example.com'`, we can display `Ex` and use the domain name
         * to select a background color.
         */
        case states.using_fallback_text: {
            if (!etldPlusOne) {
                console.warn('unreachable - must have etld+1 here');
                return null;
            }
            /** @type {Record<string, string>|undefined} */
            let style;
            const fallbackColor = urlToColor(etldPlusOne);
            if (fallbackColor) {
                style = { background: fallbackColor };
            }
            const chars = etldPlusOne.slice(0, 2);
            return (
                <div class={cn(styles.favicon, sizeClass, styles.faviconText)} style={style} data-state={state}>
                    <span aria-hidden={true}>{chars[0]}</span>
                    <span aria-hidden={true}>{chars[1]}</span>
                </div>
            );
        }
        /**
         * If we get here, we couldn't load the favicon source OR the fallback text
         * So, we default to a globe icon
         */
        case states.loading_fallback_img:
        case states.did_load_fallback_img: {
            return (
                <img
                    src={theme === 'light' ? fallback : fallbackDark}
                    class={cn(styles.favicon, sizeClass)}
                    alt=""
                    data-state={state}
                    onLoad={() => setState(states.did_load_fallback_img)}
                    onError={() => setState(states.fallback_img_failed)}
                />
            );
        }
        default:
            return null;
    }
}
