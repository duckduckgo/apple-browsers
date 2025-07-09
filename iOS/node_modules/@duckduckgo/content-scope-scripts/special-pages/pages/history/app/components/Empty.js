import { h } from 'preact';
import { useTypedTranslation } from '../types.js';
import cn from 'classnames';
import styles from './VirtualizedList.module.css';
import { useQueryContext } from '../global/Providers/QueryProvider.js';
import { useResultsData } from '../global/Providers/HistoryServiceProvider.js';
import { useComputed } from '@preact/signals';

/**
 * Empty state component displayed when no results are available
 * @param {object} props
 * @param {object} props.title
 * @param {object} props.text
 */
export function Empty({ title, text }) {
    return (
        <div class={cn(styles.emptyState, styles.emptyStateOffset)}>
            <div class={styles.icons}>
                <img src="icons/backdrop.svg" width={128} height={96} alt="" />
                <img src="icons/clock.svg" width={60} height={60} alt="" class={styles.forground} />
            </div>
            <h2 class={styles.emptyTitle}>{title}</h2>
            <p class={styles.emptyText}>{text}</p>
        </div>
    );
}

/**
 * Use the application state to figure out which title+text to use.
 */
export function EmptyState() {
    const { t } = useTypedTranslation();
    const results = useResultsData();
    const query = useQueryContext();
    const hasSearch = useComputed(() => query.value.term !== null && query.value.term.trim().length > 0);

    /**
     * Compute the empty state title. this text needs to match the results
     * it produces, not just the latest UI value.
     */
    const text = useComputed(() => {
        const termFromSearchBox = query.value.term;
        if (!('term' in results.value.info.query)) return termFromSearchBox;

        // if we have results + a search term in the UI, choose which term to show
        const termFromApiResponse = results.value.info.query.term;
        if (termFromSearchBox === termFromApiResponse) {
            return termFromSearchBox;
        }
        return termFromApiResponse;
    });

    if (hasSearch.value) {
        return <Empty title={t('no_results_title', { term: `"${text.value}"` })} text={t('no_results_text')} />;
    }

    return <Empty title={t('empty_title')} text={t('empty_text')} />;
}
