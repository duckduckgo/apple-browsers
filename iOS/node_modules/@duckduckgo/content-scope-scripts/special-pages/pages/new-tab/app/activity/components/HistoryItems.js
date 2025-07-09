import { useTypedTranslationWith } from '../../types.js';
import { useContext, useState } from 'preact/hooks';
import { NormalizedDataContext } from '../NormalizeDataProvider.js';
import { useComputed } from '@preact/signals';
import styles from './Activity.module.css';
import { ChevronSmall } from '../../components/Icons.js';
import { h } from 'preact';

/**
 * @import enStrings from "../strings.json"
 * @import { Expansion, HistoryEntry } from "../../../types/new-tab"
 */

export const MIN_SHOW_AMOUNT = 2;
export const MAX_SHOW_AMOUNT = 10;

/**
 * @param {object} props
 * @param {string} props.id
 */
export function HistoryItems({ id }) {
    const { activity } = useContext(NormalizedDataContext);
    const history = useComputed(() => activity.value.history[id]);
    const [expansion, setExpansion] = useState(/** @type {Expansion} */ ('collapsed'));
    const max = Math.min(history.value.length, MAX_SHOW_AMOUNT);
    const min = Math.min(MIN_SHOW_AMOUNT, max);
    const current = expansion === 'collapsed' ? min : max;

    function onClick(event) {
        const btn = event.target?.closest('button[data-action]');
        if (btn?.dataset.action === 'hide') {
            setExpansion('collapsed');
        } else if (btn?.dataset.action === 'show') {
            setExpansion('expanded');
        }
    }

    return (
        <ul class={styles.history} onClick={onClick}>
            {history.value.slice(0, current).map((item, index) => {
                const isLast = index === current - 1;
                return <HistoryItem key={item.url + item.title} item={item} isLast={isLast} current={current} min={min} max={max} />;
            })}
        </ul>
    );
}

/**
 * Renders a history item with relevant details such as title, time, and optional show/hide button.
 *
 * @param {object} props
 * @param {HistoryEntry} props.item - The history item object containing details like title, URL, and relative time.
 * @param {boolean} props.isLast - Indicates if the current item is the last item in the history list.
 * @param {number} props.current - The current number of visible history items.
 * @param {number} props.min - The minimum number of visible history items.
 * @param {number} props.max - The maximum number of visible history items.
 */
function HistoryItem({ item, isLast, current, min, max }) {
    const { t } = useTypedTranslationWith(/** @type {enStrings} */ ({}));

    const hasMore = current < max;
    const hasLess = current > min;
    const hiddenCount = max - current;
    const showButton = hasMore || hasLess;

    // prettier-ignore
    const buttonLabel = hasMore && isLast
        ? t('activity_show_more_history', { count: String(hiddenCount) })
        : t('activity_show_less_history');

    return (
        <li class={styles.historyItem}>
            <a href={item.url} class={styles.historyLink} title={item.url} data-url={item.url}>
                {item.title}
            </a>
            <small class={styles.time}>{item.relativeTime}</small>
            {isLast && showButton && (
                <button data-action={hasMore && isLast ? 'show' : 'hide'} class={styles.historyBtn} aria-label={buttonLabel}>
                    <ChevronSmall />
                </button>
            )}
        </li>
    );
}
