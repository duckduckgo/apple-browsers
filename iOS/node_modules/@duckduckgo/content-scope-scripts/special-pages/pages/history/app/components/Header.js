import styles from './Header.module.css';
import { h } from 'preact';
import { useComputed } from '@preact/signals';
import { SearchForm } from './SearchForm.js';
import { Trash } from '../icons/Trash.js';
import { useTypedTranslation } from '../types.js';
import { useQueryContext } from '../global/Providers/QueryProvider.js';
import { useSelected } from '../global/Providers/SelectionProvider.js';
import { useHistoryServiceDispatch, useResultsData } from '../global/Providers/HistoryServiceProvider.js';

/**
 */
export function Header() {
    const search = useQueryContext();
    const term = useComputed(() => search.value.term);
    const range = useComputed(() => search.value.range);
    const domain = useComputed(() => search.value.domain);
    return (
        <div class={styles.root}>
            <div class={styles.controls}>
                <Controls term={term} range={range} domain={domain} />
            </div>
            <div class={styles.search}>
                <SearchForm term={term} domain={domain} />
            </div>
        </div>
    );
}

/**
 * Renders the Controls component that displays a button for deletion functionality.
 *
 * @param {Object} props - Properties passed to the component.
 * @param {import("@preact/signals").Signal<string|null>} props.term
 * @param {import("@preact/signals").Signal<string|null>} props.range
 * @param {import("@preact/signals").Signal<string|null>} props.domain
 */
function Controls({ term, range, domain }) {
    const { t } = useTypedTranslation();
    const results = useResultsData();
    const selected = useSelected();
    const dispatch = useHistoryServiceDispatch();

    /**
     * Aria labels + title text is derived from the current result set.
     */
    const ariaDisabled = useComputed(() => results.value.items.length === 0);
    const title = useComputed(() => (results.value.items.length === 0 ? t('delete_none') : ''));

    /**
     * The button text should be 'delete all', unless there are row selections, then it's just 'delete'
     */
    const buttonTxt = useComputed(() => {
        const hasSelections = selected.value.size > 0;
        if (hasSelections) return t('delete_some');
        return t('delete_all');
    });

    /**
     * Which action should the delete button take?
     *
     * - if there are selections, they should be deleted by indexes
     * - if there's a range selected, that should be deleted
     * - if there's a search term, that should be deleted
     * - or fallback to deleting all
     */
    function onClick() {
        if (ariaDisabled.value === true) return;
        if (selected.value.size > 0) {
            return dispatch({ kind: 'delete-entries-by-index', value: [...selected.value] });
        }
        if (range.value !== null) {
            return dispatch({ kind: 'delete-range', value: range.value });
        }
        if (term.value !== null && term.value !== '') {
            return dispatch({ kind: 'delete-term', term: term.value });
        }
        if (domain.value !== null) {
            return dispatch({ kind: 'delete-domain', domain: domain.value });
        }
        if (term.value !== null && term.value !== '') {
            return dispatch({ kind: 'delete-term', term: term.value });
        }
        dispatch({ kind: 'delete-all' });
    }

    return (
        <button class={styles.largeButton} onClick={onClick} aria-disabled={ariaDisabled} title={title} tabindex={0}>
            <Trash />
            <span>{buttonTxt}</span>
        </button>
    );
}
