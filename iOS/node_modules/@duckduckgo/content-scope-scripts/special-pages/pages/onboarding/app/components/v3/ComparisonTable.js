import { h } from 'preact';
import cn from 'classnames';
import { comparisonTableData, tableIconPrefix } from './data-comparison-table';
import { useTypedTranslation } from '../../types';
import { useGlobalState } from '../../global';

import styles from './ComparisonTable.module.css';

/**
 * @param {object} props
 * @param {string} props.title
 */
export function ComparisonTableColumnHeading({ title }) {
    const className = `browserIcon${title}`;

    return (
        <th>
            <span className={cn(styles.browserIcon, styles[className])} aria-label={title}></span>
        </th>
    );
}

/**
 * @param {Omit<import('./data-comparison-table').FeatureSupportData, 'statuses'>} props
 */
export function ComparisonTableRowHeading({ icon, title }) {
    const path = tableIconPrefix + icon;

    return (
        <th scope="row" className={styles.rowHeading}>
            <div className={styles.rowHeadingContents}>
                <img className={styles.rowIcon} src={path} aria-hidden="true" />
                {title}
            </div>
        </th>
    );
}

/**
 * @param {object} props
 * @param {import('./data-comparison-table').SupportStatus} props.status
 */
export function ComparisonTableCell({ status }) {
    const { t } = useTypedTranslation();
    // eslint-disable-next-line
    // @ts-ignore TODO: Fix type
    const arialLabel = t(`comparison_${status}`);

    return (
        <td className={styles.rowCell}>
            <span className={cn(styles.status, styles[status])} aria-label={arialLabel}></span>
        </td>
    );
}

/**
 * @param {import('./data-comparison-table').FeatureSupportData} props
 */
export function ComparisonTableRow({ icon, title, statuses }) {
    const { chrome, ddg } = statuses;

    return (
        <tr className={styles.row}>
            <ComparisonTableRowHeading icon={icon} title={title} />
            <ComparisonTableCell status={chrome} />
            <ComparisonTableCell status={ddg} />
        </tr>
    );
}

export function ComparisonTable() {
    const { t } = useTypedTranslation();
    const state = useGlobalState();

    const systemSettingsStep = /** @type {import('../../types').SystemSettingsStep|undefined} */ (state.stepDefinitions.systemSettings);
    const adBlockingEnabled =
        systemSettingsStep?.rows?.some((row) => row === 'aggressive-ad-blocking' || row === 'youtube-ad-blocking') ?? false;
    const tableData = comparisonTableData(t, adBlockingEnabled);

    return (
        <table className={styles.table}>
            <caption></caption>
            <thead>
                <tr>
                    <th></th>
                    <ComparisonTableColumnHeading title="Chrome" />
                    <ComparisonTableColumnHeading title="DuckDuckGo" />
                </tr>
            </thead>
            <tbody>
                {tableData.map((data) => (
                    <ComparisonTableRow {...data} />
                ))}
            </tbody>
        </table>
    );
}
