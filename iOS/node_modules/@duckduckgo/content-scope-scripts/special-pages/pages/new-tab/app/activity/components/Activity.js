import { h } from 'preact';
import styles from './Activity.module.css';
import { useContext, useEffect, useRef } from 'preact/hooks';
import { memo } from 'preact/compat';
import { ActivityContext, ActivityServiceContext } from '../ActivityProvider.js';
import { useTypedTranslationWith } from '../../types.js';
import { useOnMiddleClick } from '../../utils.js';
import { useAdBlocking, useBatchedActivityApi, usePlatformName } from '../../settings.provider.js';
import { CompanyIcon } from '../../components/CompanyIcon.js';
import { Trans } from '../../../../../shared/components/TranslationsProvider.js';
import { ActivityItem } from './ActivityItem.js';
import { ActivityBurningSignalContext, BurnProvider } from '../../burning/BurnProvider.js';
import { useEnv } from '../../../../../shared/components/EnvironmentProvider.js';
import { useComputed } from '@preact/signals';
import { ActivityItemAnimationWrapper } from './ActivityItemAnimationWrapper.js';
import { useDocumentVisibility } from '../../../../../shared/components/DocumentVisibility.js';
import { HistoryItems } from './HistoryItems.js';
import { NormalizedDataContext, SignalStateProvider } from '../NormalizeDataProvider.js';
import { ActivityInteractionsContext } from '../../burning/ActivityInteractionsContext.js';
import { ProtectionsEmpty } from '../../protections/components/Protections.js';

/**
 * @import enStrings from "../strings.json"
 * @typedef {import('../../../types/new-tab').Expansion} Expansion
 */

/**
 * Renders the Activity component with associated heading and body, managing interactivity and state.
 *
 * @param {Object} props - Object containing all properties required by the Activity component.
 * @param {number} props.itemCount - Object representing the count of items in the activity.
 * @param {boolean} props.batched - Boolean indicating whether the activity uses batched loading.
 * @param {import("preact").ComponentChild} [props.children]
 */
export function Activity({ itemCount, batched, children }) {
    return (
        <div class={styles.root} data-testid="Activity">
            {itemCount === 0 && <ActivityEmptyState />}
            {itemCount > 0 && children}
            {batched && itemCount > 0 && <Loader />}
        </div>
    );
}

export function ActivityEmptyState() {
    const { t } = useTypedTranslationWith(/** @type {import("../strings.json")} */ ({}));
    return (
        <ProtectionsEmpty>
            <p>{t('activity_empty')}</p>
        </ProtectionsEmpty>
    );
}

/**
 * @param {object} props
 * @param {boolean} props.canBurn
 * @param {DocumentVisibilityState} props.visibility
 */
export function ActivityBody({ canBurn, visibility }) {
    const { isReducedMotion } = useEnv();
    const { keys } = useContext(NormalizedDataContext);
    const { burning, exiting } = useContext(ActivityBurningSignalContext);
    const busy = useComputed(() => burning.value.length > 0 || exiting.value.length > 0);

    // see: https://www.w3.org/WAI/ARIA/apg/patterns/accordion/examples/accordion/
    const { didClick } = useContext(ActivityInteractionsContext);

    const ref = useRef(null);
    useOnMiddleClick(ref, didClick);

    return (
        <ul class={styles.activity} data-busy={busy} ref={ref} onClick={didClick}>
            {keys.value.map((id, _index) => {
                if (canBurn && !isReducedMotion) return <BurnableItem id={id} key={id} documentVisibility={visibility} />;
                return <RemovableItem id={id} key={id} canBurn={canBurn} documentVisibility={visibility} />;
            })}
        </ul>
    );
}

function Loader() {
    const loaderRef = useRef(/** @type {HTMLDivElement|null} */ (null));

    useEffect(() => {
        const observer = new IntersectionObserver(([entry]) => {
            if (entry.isIntersecting) {
                window.dispatchEvent(new Event('activity.next'));
            }
        });

        if (loaderRef.current) {
            observer.observe(loaderRef.current);
        }

        return () => {
            if (loaderRef.current) {
                observer.unobserve(loaderRef.current);
            }
        };
    }, []);

    return (
        <div class={styles.loader} ref={loaderRef}>
            Loading...
        </div>
    );
}

const BurnableItem = memo(
    /**
     * @param {object} props
     * @param {string} props.id
     * @param {'visible' | 'hidden'} props.documentVisibility
     */
    function BurnableItem({ id, documentVisibility }) {
        const { activity } = useContext(NormalizedDataContext);
        const item = useComputed(() => activity.value.items[id]);
        if (!item.value) {
            return null;
        }
        return (
            <ActivityItemAnimationWrapper url={id}>
                <ActivityItem
                    title={item.value.title}
                    url={id}
                    favoriteSrc={item.value.favoriteSrc}
                    faviconMax={item.value.faviconMax}
                    etldPlusOne={item.value.etldPlusOne}
                    canBurn={true}
                    documentVisibility={documentVisibility}
                >
                    <TrackerStatus id={id} trackersFound={item.value.trackersFound} />
                    <HistoryItems id={id} />
                </ActivityItem>
            </ActivityItemAnimationWrapper>
        );
    },
);

const RemovableItem = memo(
    /**
     * @param {object} props
     * @param {string} props.id
     * @param {boolean} props.canBurn
     * @param {"visible" | "hidden"} props.documentVisibility
     */
    function RemovableItem({ id, canBurn, documentVisibility }) {
        const { activity } = useContext(NormalizedDataContext);
        const item = useComputed(() => activity.value.items[id]);
        if (!item.value) {
            return (
                <p data-testid="ActivityItem" data-state="loading" data-id={id} hidden>
                    Loading: {id}
                </p>
            );
        }
        return (
            <ActivityItem
                title={item.value.title}
                url={id}
                favoriteSrc={item.value.favoriteSrc}
                faviconMax={item.value.faviconMax}
                etldPlusOne={item.value.etldPlusOne}
                canBurn={canBurn}
                documentVisibility={documentVisibility}
            >
                <TrackerStatus id={id} trackersFound={item.value.trackersFound} />
                <HistoryItems id={id} />
            </ActivityItem>
        );
    },
);

const DDG_MAX_TRACKER_ICONS = 3;
/**
 * @param {object} props
 * @param {string} props.id
 * @param {boolean} props.trackersFound
 */
function TrackerStatus({ id, trackersFound }) {
    const { t } = useTypedTranslationWith(/** @type {enStrings} */ ({}));
    const { activity } = useContext(NormalizedDataContext);
    const status = useComputed(() => activity.value.trackingStatus[id]);
    const other = status.value.trackerCompanies.slice(DDG_MAX_TRACKER_ICONS - 1);
    const companyIconsMax = other.length === 0 ? DDG_MAX_TRACKER_ICONS : DDG_MAX_TRACKER_ICONS - 1;
    const adBlocking = useAdBlocking();

    const icons = status.value.trackerCompanies.slice(0, companyIconsMax).map((item, _index) => {
        return <CompanyIcon displayName={item.displayName} key={item} />;
    });

    let otherIcon = null;
    if (other.length > 0) {
        const title = other.map((item) => item.displayName).join('\n');
        otherIcon = (
            <span title={title} class={styles.otherIcon}>
                +{other.length}
            </span>
        );
    }

    if (status.value.totalCount === 0) {
        let text;
        if (trackersFound) {
            text = adBlocking ? t('activity_no_adsAndTrackers_blocked') : t('activity_no_trackers_blocked');
        } else {
            text = adBlocking ? t('activity_no_adsAndTrackers') : t('activity_no_trackers');
        }
        return (
            <p class={styles.companiesIconRow} data-testid="TrackerStatus">
                {text}
            </p>
        );
    }

    return (
        <div class={styles.companiesIconRow} data-testid="TrackerStatus">
            <div class={styles.companiesIcons}>
                {icons}
                {otherIcon}
            </div>
            <div class={styles.companiesText}>
                {adBlocking ? (
                    <Trans str={t('activity_countBlockedAdsAndTrackersPlural', { count: String(status.value.totalCount) })} values={{}} />
                ) : (
                    <Trans str={t('activity_countBlockedPlural', { count: String(status.value.totalCount) })} values={{}} />
                )}
            </div>
        </div>
    );
}

/**
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function ActivityConfigured({ children }) {
    const batched = useBatchedActivityApi();

    const { activity } = useContext(NormalizedDataContext);

    const itemCount = useComputed(() => {
        return Object.keys(activity.value.items).length;
    });

    return (
        <Activity batched={batched} itemCount={itemCount.value}>
            {children}
        </Activity>
    );
}

/**
 * Use this when you want to render the UI from a context where
 * the service is available + initial data is ready
 *
 * for example:
 *
 * ```jsx
 * <ActivityProvider>
 *     <ActivityConsumer />
 * </ActivityProvider>
 * ```
 * @param {object} props
 * @param {boolean} props.showBurnAnimation
 */
export function ActivityConsumer({ showBurnAnimation }) {
    const { state } = useContext(ActivityContext);
    const service = useContext(ActivityServiceContext);
    const platformName = usePlatformName();
    const visibility = useDocumentVisibility();
    if (service && state.status === 'ready') {
        if (platformName === 'windows') {
            return (
                <SignalStateProvider>
                    <ActivityConfigured>
                        <ActivityBody canBurn={false} visibility={visibility} />
                    </ActivityConfigured>
                </SignalStateProvider>
            );
        }
        return (
            <SignalStateProvider>
                <BurnProvider service={service} showBurnAnimation={showBurnAnimation}>
                    <ActivityConfigured>
                        <ActivityBody canBurn={true} visibility={visibility} />
                    </ActivityConfigured>
                </BurnProvider>
            </SignalStateProvider>
        );
    }
    return null;
}
