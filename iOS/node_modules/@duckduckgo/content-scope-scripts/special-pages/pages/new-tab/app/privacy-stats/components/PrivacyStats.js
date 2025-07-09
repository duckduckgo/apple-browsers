import { Fragment, h } from 'preact';
import styles from './PrivacyStats.module.css';
import { useTypedTranslationWith } from '../../types.js';
import { useState } from 'preact/hooks';
import { ShowHideButtonPill } from '../../components/ShowHideButton.jsx';
import { DDG_STATS_DEFAULT_ROWS, DDG_STATS_OTHER_COMPANY_IDENTIFIER } from '../constants.js';
import { displayNameForCompany, sortStatsForDisplay } from '../privacy-stats.utils.js';
import { CompanyIcon } from '../../components/CompanyIcon.js';
import { useBodyExpansion, useBodyExpansionApi } from './BodyExpansionProvider.js';
import { ProtectionsEmpty } from '../../protections/components/Protections.js';
import { getLocalizedNumberFormatter } from '../../../../../shared/utils.js';
import { useLocale } from '../../../../../shared/components/EnvironmentProvider';

/**
 * @import enStrings from "../strings.json"
 * @typedef {enStrings} Strings
 * @typedef {import('../../../types/new-tab').TrackerCompany} TrackerCompany
 * @typedef {import('../../../types/new-tab').Expansion} Expansion
 * @typedef {import('../../../types/new-tab').PrivacyStatsData} PrivacyStatsData
 */

/**
 * @param {object} props
 * @param {TrackerCompany[]} props.trackerCompanies
 * @param {Expansion} [props.expansion]
 */
export function PrivacyStats({ trackerCompanies, expansion = 'expanded' }) {
    const locale = useLocale();
    const [formatter] = useState(() => getLocalizedNumberFormatter(locale));
    const sorted = sortStatsForDisplay(trackerCompanies);
    const largestTrackerCount = sorted[0]?.count ?? 0;

    // prettier-ignore
    const visibleRows = expansion === 'expanded'
        /**
         * When expanded, show everything
         */
        ? sorted
        /**
         * When collapsed, show upto the default
         */
        : sorted.slice(0, DDG_STATS_DEFAULT_ROWS);

    return (
        <div class={styles.body}>
            {sorted.length === 0 && <PrivacyStatsEmptyState />}
            {sorted.length > 0 && <CompanyList rows={visibleRows} largestTrackerCount={largestTrackerCount} formatter={formatter} />}
            {sorted.length > 0 && <ListFooter all={sorted} />}
        </div>
    );
}

export function PrivacyStatsEmptyState() {
    const { t } = useTypedTranslationWith(/** @type {import("../strings.json")} */ ({}));
    return <ProtectionsEmpty>{t('stats_noActivity')}</ProtectionsEmpty>;
}

/**
 * @param {object} props
 * @param {Intl.NumberFormat} props.formatter
 * @param {TrackerCompany[]} props.rows
 * @param {number} props.largestTrackerCount
 */
export function CompanyList({ rows, formatter, largestTrackerCount }) {
    return (
        <ul class={styles.list} data-testid="CompanyList">
            {rows.map((company) => {
                const percentage = Math.min((company.count * 100) / largestTrackerCount, 100);
                const valueOrMin = Math.max(percentage, 10);
                const inlineStyles = {
                    width: `${valueOrMin}%`,
                };
                const countText = formatter.format(company.count);
                const displayName = displayNameForCompany(company.displayName);

                // We don't actually render the 'other' row in the main loop - it's appended as a separate element later
                if (company.displayName === DDG_STATS_OTHER_COMPANY_IDENTIFIER) {
                    return null;
                }
                return (
                    <li key={company.displayName} class={styles.row}>
                        <div className={styles.company}>
                            <CompanyIcon displayName={displayName} />
                            <span class={styles.name}>{displayName}</span>
                        </div>
                        <span class={styles.count}>{countText}</span>
                        <span class={styles.bar}></span>
                        <span class={styles.fill} style={inlineStyles}></span>
                    </li>
                );
            })}
        </ul>
    );
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const states = /** @type {const} */ ([
    'few_top+other',
    'few_top',
    'few_other',
    'many_top+other_collapsed',
    'many_top+other_expanded',
    'many_top_collapsed',
    'many_top_expanded',
]);

/**
 * Renders a footer element that adapts its content and behavior based on provided data and state.
 *
 * @param {Object} props - The properties passed to the Footer component.
 * @param {TrackerCompany[]} props.all - An array of data objects used to determine content and state of the footer.
 */
export function ListFooter({ all }) {
    const expansion = useBodyExpansion();

    const lastElement = all[all.length - 1];
    const hasOtherRow = lastElement?.displayName === DDG_STATS_OTHER_COMPANY_IDENTIFIER;

    /** @type {states[number]} */
    const state = (() => {
        const comparison = hasOtherRow ? DDG_STATS_DEFAULT_ROWS + 1 : DDG_STATS_DEFAULT_ROWS;
        if (all.length <= comparison) {
            if (hasOtherRow) {
                if (all.length === 1) {
                    return 'few_other';
                }
                return 'few_top+other';
            }
            return 'few_top';
        } else {
            if (hasOtherRow) {
                return expansion === 'collapsed' ? 'many_top+other_collapsed' : 'many_top+other_expanded';
            }
            return expansion === 'collapsed' ? 'many_top_collapsed' : 'many_top_expanded';
        }
    })();

    const contents = (() => {
        switch (state) {
            case 'few_other':
            case 'few_top+other': {
                return <OtherText count={lastElement.count} />;
            }
            case 'many_top_collapsed':
            case 'many_top_expanded':
            case 'many_top+other_collapsed': {
                return <PillShowMoreLess expansion={expansion} />;
            }
            case 'many_top+other_expanded':
                return (
                    <Fragment>
                        <OtherText count={lastElement.count} />
                        <PillShowMoreLess expansion={expansion} />
                    </Fragment>
                );
            case 'few_top':
            default:
                return null;
        }
    })();

    if (contents === null) return null;

    return (
        <div class={styles.listFooter} data-testid="ListFooter">
            {contents}
        </div>
    );
}

/**
 * Renders a pill component that toggles between "Show More" and "Show Less" states.
 *
 * @param {Object} props - The properties object.
 * @param {Expansion} props.expansion - Indicates the current state of expansion.
 */
function PillShowMoreLess({ expansion }) {
    const { t } = useTypedTranslationWith(/** @type {Strings} */ ({}));
    const { showLess, showMore } = useBodyExpansionApi();

    const toggleListExpansion = () => {
        if (expansion === 'collapsed') {
            showMore();
        } else {
            showLess();
        }
    };

    return (
        <div class={styles.listExpander}>
            <ShowHideButtonPill
                onClick={toggleListExpansion}
                label={undefined}
                fill={false}
                text={expansion === 'collapsed' ? t('ntp_show_more') : t('ntp_show_less')}
                buttonAttrs={{
                    'aria-expanded': expansion === 'expanded',
                    'aria-pressed': expansion === 'expanded',
                }}
            />
        </div>
    );
}

/**
 * Generates a localized text element displaying a count.
 *
 * @param {Object} props - The parameters for generating the text.
 * @param {number} props.count - The count to be included in the localized text.
 */
export function OtherText({ count }) {
    const { t } = useTypedTranslationWith(/** @type {Strings} */ ({}));
    const locale = useLocale();
    const [formatter] = useState(() => getLocalizedNumberFormatter(locale));
    const formattedCount = formatter.format(count);

    const otherText = t('stats_otherCount', { count: String(formattedCount) });
    return <div class={styles.otherTrackersRow}>{otherText}</div>;
}
