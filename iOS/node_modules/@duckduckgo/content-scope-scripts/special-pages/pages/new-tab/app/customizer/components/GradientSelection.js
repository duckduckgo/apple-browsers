import { h } from 'preact';
import cn from 'classnames';

import { values } from '../values.js';
import styles from './CustomizerDrawerInner.module.css';
import { useComputed } from '@preact/signals';
import { BackChevron } from '../../components/Icons.js';
import { InlineErrorBoundary } from '../../InlineErrorBoundary.js';
import { useTypedTranslationWith } from '../../types.js';

/**
 * @import { Widgets, WidgetConfigItem, WidgetVisibility, VisibilityMenuItem, BackgroundData, CustomizerData, PredefinedGradient } from '../../../types/new-tab.js'
 * @import enStrings from '../strings.json';
 */

/**
 * @param {object} props
 * @param {import('@preact/signals').Signal<CustomizerData>} props.data
 * @param {(bg: BackgroundData) => void} props.select
 * @param {() => void} props.back
 */
export function GradientSelection({ data, select, back }) {
    // const gradient = values.gradients.gradient02;
    const { t } = useTypedTranslationWith(/** @type {enStrings} */ ({}));

    function onClick(event) {
        let target = /** @type {HTMLElement|null} */ (event.target);
        const selector = `[role="radio"][aria-checked="false"][data-value]`;
        if (!target?.matches(selector)) {
            target = /** @type {HTMLElement|null} */ (target?.closest(selector));
        }
        if (!target) return;
        const value = /** @type {PredefinedGradient} */ (target.dataset.value);
        // todo: report exception?
        if (!(value in values.gradients)) return console.warn('could not select gradient', value);
        select({ background: { kind: 'gradient', value } });
    }

    return (
        <div>
            <button type={'button'} onClick={back} class={cn(styles.backBtn, styles.sectionTitle)}>
                <BackChevron />
                {t('customizer_background_selection_gradient')}
            </button>
            <div className={styles.sectionBody} onClick={onClick}>
                <InlineErrorBoundary format={(message) => `Customizer section 'GradientSelection' threw an exception: ` + message}>
                    <GradientGrid data={data} />
                </InlineErrorBoundary>
            </div>
        </div>
    );
}

const entries = Object.keys(values.gradients);
/**
 * @param {object} props
 * @param {import("@preact/signals").Signal<CustomizerData>} props.data
 */
function GradientGrid({ data }) {
    const selected = useComputed(() => data.value.background.kind === 'gradient' && data.value.background.value);
    return (
        <ul className={cn(styles.bgList)}>
            {entries.map((key) => {
                const entry = values.gradients[key];
                return (
                    <li className={styles.bgListItem} key={key}>
                        <button
                            className={styles.bgPanel}
                            type="button"
                            tabIndex={0}
                            role="radio"
                            aria-checked={key === selected.value}
                            data-value={key}
                            style={{
                                backgroundColor: entry.fallback,
                                backgroundImage: `url(${entry.path})`,
                                backgroundSize: 'cover',
                                backgroundRepeat: 'no-repeat',
                            }}
                        >
                            <span className="sr-only">Select {key}</span>
                        </button>
                    </li>
                );
            })}
        </ul>
    );
}
