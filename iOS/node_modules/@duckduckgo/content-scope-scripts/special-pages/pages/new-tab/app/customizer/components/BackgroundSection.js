import { h, Fragment } from 'preact';
import cn from 'classnames';

import { values } from '../values.js';
import styles from './CustomizerDrawerInner.module.css';
import { CircleCheck, PlusIcon } from '../../components/Icons.js';
import { useComputed } from '@preact/signals';
import { useContext, useId } from 'preact/hooks';
import { CustomizerThemesContext } from '../CustomizerProvider.js';
import { detectThemeFromHex } from '../utils.js';
import { useTypedTranslationWith } from '../../types.js';

/**
 * @import { Widgets, WidgetConfigItem, WidgetVisibility, VisibilityMenuItem, CustomizerData, BackgroundData } from '../../../types/new-tab.js'
 * @import enStrings from '../strings.json';
 */

/**
 * @param {object} props
 * @param {(bg: BackgroundData) => void} props.select
 * @param {import('@preact/signals').Signal<CustomizerData>} props.data
 * @param {(target: 'color' | 'back' | 'image' | 'gradient') => void} props.onNav
 * @param {() => void} props.onUpload
 */
export function BackgroundSection({ data, onNav, onUpload, select }) {
    const { browser } = useContext(CustomizerThemesContext);
    let displayColor;

    if (data.value.background.kind === 'color') {
        displayColor = values.colors[data.value.background.value];
    } else if (data.value.background.kind === 'hex') {
        const hex = data.value.background.value;
        displayColor = { hex: data.value.background.value, colorScheme: detectThemeFromHex(hex) };
    } else {
        displayColor = values.colors.color11;
    }

    /** @type {{path: string; colorScheme: 'light' | 'dark'}} */
    let gradient;
    if (data.value.background.kind === 'gradient') {
        gradient = values.gradients[data.value.background.value];
    } else {
        gradient = values.gradients.gradient02;
    }

    return (
        <ul class={cn(styles.bgList)} role="radiogroup">
            <li class={styles.bgListItem}>
                <DefaultPanel
                    checked={data.value.background.kind === 'default'}
                    onClick={() => select({ background: { kind: 'default' } })}
                />
            </li>
            <li class={styles.bgListItem}>
                <ColorPanel
                    checked={data.value.background.kind === 'color' || data.value.background.kind === 'hex'}
                    color={displayColor}
                    onClick={() => onNav('color')}
                />
            </li>
            <li class={styles.bgListItem}>
                <GradientPanel checked={data.value.background.kind === 'gradient'} gradient={gradient} onClick={() => onNav('gradient')} />
            </li>
            <li class={styles.bgListItem}>
                <BackgroundImagePanel
                    checked={data.value.background.kind === 'userImage'}
                    onClick={() => onNav('image')}
                    data={data}
                    upload={onUpload}
                    browserTheme={browser}
                />
            </li>
        </ul>
    );
}

/**
 * @param {object} props
 * @param {boolean} props.checked
 * @param {() => void} props.onClick
 */
function DefaultPanel({ checked, onClick }) {
    const id = useId();
    const { main } = useContext(CustomizerThemesContext);
    const { t } = useTypedTranslationWith(/** @type {enStrings} */ ({}));

    return (
        <>
            <button
                class={cn(styles.bgPanel, styles.bgPanelEmpty, styles.dynamicIconColor)}
                data-color-mode={main}
                aria-checked={checked}
                aria-labelledby={id}
                role="radio"
                onClick={onClick}
                tabindex={checked ? -1 : 0}
            >
                {checked && <CircleCheck />}
            </button>
            <span id={id}>{t('customizer_background_selection_default')}</span>
        </>
    );
}

/**
 * @param {object} props
 * @param {boolean} props.checked
 * @param {() => void} props.onClick
 * @param {{hex: string, colorScheme: 'light' | 'dark'}} props.color
 */
function ColorPanel(props) {
    const id = useId();
    const { t } = useTypedTranslationWith(/** @type {enStrings} */ ({}));
    return (
        <>
            <button
                class={cn(styles.bgPanel, styles.dynamicIconColor)}
                data-color-mode={props.color.colorScheme}
                onClick={props.onClick}
                aria-checked={props.checked}
                tabindex={props.checked ? -1 : 0}
                aria-labelledby={id}
                role="radio"
                style={{ background: props.color.hex }}
            >
                {props.checked && <CircleCheck />}
            </button>
            <span id={id}>{t('customizer_background_selection_color')}</span>
        </>
    );
}

/**
 * @param {object} props
 * @param {boolean} props.checked
 * @param {() => void} props.onClick
 * @param {{path: string; colorScheme: 'light' | 'dark'}} props.gradient
 */
function GradientPanel(props) {
    const id = useId();
    const { t } = useTypedTranslationWith(/** @type {enStrings} */ ({}));
    return (
        <>
            <button
                onClick={props.onClick}
                class={cn(styles.bgPanel, styles.dynamicIconColor)}
                data-color-mode={props.gradient.colorScheme}
                aria-checked={props.checked}
                tabindex={props.checked ? -1 : 0}
                aria-labelledby={id}
                style={{
                    background: `url(${props.gradient.path})`,
                    backgroundSize: 'cover',
                    backgroundRepeat: 'no-repeat',
                    backgroundPosition: 'center center',
                }}
            >
                {props.checked && <CircleCheck />}
            </button>
            <span id={id}>{t('customizer_background_selection_gradient')}</span>
        </>
    );
}

/**
 * @param {object} props
 * @param {boolean} props.checked
 * @param {() => void} props.onClick
 * @param {() => void} props.upload
 * @param {import('@preact/signals').Signal<CustomizerData>} props.data
 * @param {import('@preact/signals').Signal<'light' | 'dark'>} props.browserTheme
 */
function BackgroundImagePanel(props) {
    const id = useId();
    const { t } = useTypedTranslationWith(/** @type {enStrings} */ ({}));
    const empty = useComputed(() => props.data.value.userImages.length === 0);
    const selectedImage = useComputed(() => {
        const imageId = props.data.value.background.kind === 'userImage' ? props.data.value.background.value : null;
        if (imageId !== null) {
            const match = props.data.value.userImages.find((i) => i.id === imageId.id);
            if (match) {
                return match;
            }
        }
        return null;
    });

    const firstImage = useComputed(() => {
        return props.data.value.userImages[0] ?? null;
    });

    // prettier-ignore
    const label = empty.value === true
        ? <span id={id}>{t('customizer_background_selection_image_add')}</span>
        : <span id={id}>{t('customizer_background_selection_image_existing')}</span>;

    if (empty.value === true) {
        return (
            <Fragment>
                <button
                    class={cn(styles.bgPanel, styles.bgPanelEmpty, styles.dynamicIconColor)}
                    data-color-mode={props.browserTheme}
                    aria-checked={props.checked}
                    aria-labelledby={id}
                    role={'radio'}
                    onClick={props.upload}
                >
                    <PlusIcon />
                </button>
                {label}
            </Fragment>
        );
    }

    // prettier-ignore
    const image = selectedImage.value !== null
        ? selectedImage.value?.thumb
        : firstImage.value?.thumb;

    // prettier-ignore
    const scheme = selectedImage.value !== null
        ? selectedImage.value?.colorScheme
        : firstImage.value?.colorScheme;

    return (
        <Fragment>
            <button
                class={cn(styles.bgPanel, styles.dynamicIconColor)}
                data-color-mode={scheme}
                onClick={props.onClick}
                aria-checked={props.checked}
                aria-labelledby={id}
                style={{
                    backgroundImage: `url(${image})`,
                    backgroundSize: 'cover',
                    backgroundRepeat: 'no-repeat',
                }}
            >
                {props.checked && <CircleCheck />}
            </button>
            {label}
        </Fragment>
    );
}
