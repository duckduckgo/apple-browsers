import { h, Fragment } from 'preact';
import cn from 'classnames';

import { values } from '../values.js';
import styles from './CustomizerDrawerInner.module.css';
import { BackChevron, Picker } from '../../components/Icons.js';
import { useComputed } from '@preact/signals';
import { detectThemeFromHex } from '../utils.js';
import { InlineErrorBoundary } from '../../InlineErrorBoundary.js';
import { useTypedTranslationWith } from '../../types.js';

/**
 * @import { Widgets, WidgetConfigItem, WidgetVisibility, VisibilityMenuItem, CustomizerData, PredefinedColor, BackgroundData } from '../../../types/new-tab.js'
 * @import enStrings from '../strings.json';
 */

/**
 * @param {object} props
 * @param {import("@preact/signals").Signal<CustomizerData>} props.data
 * @param {(bg: BackgroundData) => void} props.select
 * @param {() => void} props.back
 */
export function ColorSelection({ data, select, back }) {
    const { t } = useTypedTranslationWith(/** @type {enStrings} */ ({}));
    function onClick(event) {
        let target = /** @type {HTMLElement|null} */ (event.target);
        const selector = `[role="radio"][aria-checked="false"][data-value]`;
        if (!target?.matches(selector)) {
            target = /** @type {HTMLElement|null} */ (target?.closest(selector));
        }
        if (!target) return;
        const value = /** @type {PredefinedColor} */ (target.dataset.value);
        // todo: report exception?
        if (!(value in values.colors)) return console.warn('could not select color', value);
        select({ background: { kind: 'color', value } });
    }

    return (
        <div>
            <button type={'button'} onClick={back} class={cn(styles.backBtn, styles.sectionTitle)}>
                <BackChevron />
                {t('customizer_background_selection_color')}
            </button>
            <div class={styles.sectionBody}>
                <InlineErrorBoundary format={(message) => `Customizer section 'ColorGrid' threw an exception: ` + message}>
                    <div class={cn(styles.bgList)} role="radiogroup" onClick={onClick}>
                        <PickerPanel data={data} select={select} />
                        <ColorGrid data={data} />
                    </div>
                </InlineErrorBoundary>
            </div>
        </div>
    );
}

const entries = Object.keys(values.colors);

/**
 * @param {object} props
 * @param {import("@preact/signals").Signal<CustomizerData>} props.data
 */
function ColorGrid({ data }) {
    const selected = useComputed(() => data.value.background.kind === 'color' && data.value.background.value);
    return (
        <Fragment>
            {entries.map((key) => {
                const entry = values.colors[key];
                return (
                    <div class={styles.bgListItem} key={key}>
                        <button
                            class={styles.bgPanel}
                            type="button"
                            tabindex={0}
                            style={{ background: entry.hex }}
                            role="radio"
                            aria-checked={key === selected.value}
                            data-value={key}
                        >
                            <span class="sr-only">Select {key}</span>
                        </button>
                    </div>
                );
            })}
        </Fragment>
    );
}

/**
 * @param {object} props
 * @param {import("@preact/signals").Signal<CustomizerData>} props.data
 * @param {(bg: BackgroundData) => void} props.select
 */
function PickerPanel({ data, select }) {
    const hex = useComputed(() => {
        // first case, the user has their background set to be a hex value
        if (data.value.background.kind === 'hex') {
            return data.value.background.value;
        }

        // second case - the user previously set a hex value
        if (data.value.userColor?.kind === 'hex') {
            return data.value.userColor.value;
        }

        // 3rd case - the default
        return '#ffffff';
    });

    const hexSelected = useComputed(() => data.value.background.kind === 'hex');
    const modeSelected = useComputed(() => detectThemeFromHex(hex.value));

    return (
        <div class={styles.bgListItem}>
            <button
                className={cn(styles.bgPanel, styles.bgPanelEmpty)}
                type="button"
                tabIndex={0}
                style={{ background: hex.value }}
                role="radio"
                aria-checked={hexSelected}
            ></button>
            <input
                type="color"
                tabIndex={-1}
                style={{ opacity: 0, inset: 0, position: 'absolute', width: '100%', height: '100%' }}
                value={hex}
                onChange={(e) => {
                    if (!(e.target instanceof HTMLInputElement)) return;
                    select({ background: { kind: 'hex', value: e.target.value } });
                }}
                onClick={(e) => {
                    if (!(e.target instanceof HTMLInputElement)) return;
                    if (data.value.userColor?.value === hex.value) {
                        select({ background: { kind: 'hex', value: e.target.value } });
                    }
                }}
            />
            <span class={cn(styles.colorInputIcon, styles.dynamicPickerIconColor)} data-color-mode={modeSelected}>
                <Picker />
            </span>
        </div>
    );
}
