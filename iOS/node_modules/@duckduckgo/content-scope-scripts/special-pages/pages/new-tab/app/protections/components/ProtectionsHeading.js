import { useTypedTranslationWith } from '../../types.js';
import { useState } from 'preact/hooks';
import styles from '../../privacy-stats/components/PrivacyStats.module.css';
import { ShowHideButtonCircle } from '../../components/ShowHideButton.jsx';
import cn from 'classnames';
import { h } from 'preact';
import { useAdBlocking } from '../../settings.provider.js';
import { Trans } from '../../../../../shared/components/TranslationsProvider.js';
import { getLocalizedNumberFormatter } from '../../../../../shared/utils.js';
import { useLocale } from '../../../../../shared/components/EnvironmentProvider.js';

/**
 * @import enStrings from "../strings.json"
 * @import statsStrings from "../../privacy-stats/strings.json"
 * @import activityStrings from "../../activity/strings.json"
 * @typedef {enStrings & statsStrings & activityStrings} Strings
 * @param {object} props
 * @param {import('../../../types/new-tab.ts').Expansion} props.expansion
 * @param {import("@preact/signals").Signal<number>} props.blockedCountSignal
 * @param {boolean} props.canExpand
 * @param {() => void} props.onToggle
 * @param {import('preact').ComponentProps<'button'>} [props.buttonAttrs]
 */
export function ProtectionsHeading({ expansion, canExpand, blockedCountSignal, onToggle, buttonAttrs = {} }) {
    const { t } = useTypedTranslationWith(/** @type {Strings} */ ({}));
    const locale = useLocale();
    const [formatter] = useState(() => getLocalizedNumberFormatter(locale));
    const adBlocking = useAdBlocking();
    const blockedCount = blockedCountSignal.value;
    const none = blockedCount === 0;
    const some = blockedCount > 0;
    const alltime = formatter.format(blockedCount);

    let alltimeTitle;
    if (blockedCount === 1) {
        alltimeTitle = adBlocking ? t('stats_countBlockedAdsAndTrackersSingular') : t('stats_countBlockedSingular');
    } else {
        alltimeTitle = adBlocking
            ? t('stats_countBlockedAdsAndTrackersPlural', { count: alltime })
            : t('stats_countBlockedPlural', { count: alltime });
    }

    return (
        <div class={styles.heading} data-testid="ProtectionsHeading">
            <div class={styles.control}>
                <span class={styles.headingIcon}>
                    <img src={'./icons/Shield-Check-Color-16.svg'} alt="Privacy Shield" />
                </span>
                <h2 class={styles.caption}>{t('protections_menuTitle')}</h2>
                {canExpand && (
                    <span class={styles.widgetExpander}>
                        <ShowHideButtonCircle
                            buttonAttrs={{
                                ...buttonAttrs,
                                'aria-expanded': expansion === 'expanded',
                                'aria-pressed': expansion === 'expanded',
                            }}
                            onClick={onToggle}
                            label={expansion === 'expanded' ? t('stats_hideLabel') : t('stats_toggleLabel')}
                        />
                    </span>
                )}
            </div>
            <div class={styles.counter}>
                {none && <h3 class={styles.title}>{t('protections_noRecent')}</h3>}
                {some && (
                    <h3 class={styles.title}>
                        {' '}
                        <Trans str={alltimeTitle} values={{ count: alltime }} />
                    </h3>
                )}
                <p class={cn(styles.subtitle, styles.indented)}>{t('stats_feedCountBlockedPeriod')}</p>
            </div>
        </div>
    );
}
