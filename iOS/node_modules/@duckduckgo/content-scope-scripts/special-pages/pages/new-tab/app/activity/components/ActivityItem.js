import { h } from 'preact';
import { useTypedTranslationWith } from '../../types.js';
import cn from 'classnames';
import styles from './Activity.module.css';
import { FaviconWithState } from '../../../../../shared/components/FaviconWithState.js';
import { ACTION_ADD_FAVORITE, ACTION_REMOVE, ACTION_REMOVE_FAVORITE } from '../constants.js';
import { Star, StarFilled } from '../../components/icons/Star.js';
import { Fire } from '../../components/icons/Fire.js';
import { Cross } from '../../components/Icons.js';
import { useContext } from 'preact/hooks';
import { memo } from 'preact/compat';
import { useComputed } from '@preact/signals';
import { NormalizedDataContext } from '../NormalizeDataProvider.js';
import { ACTION_BURN } from '../../burning/BurnProvider.js';
import { DDG_FALLBACK_ICON, DDG_FALLBACK_ICON_DARK } from '../../favorites/constants.js';

export const ActivityItem = memo(
    /**
     * @param {object} props
     * @param {boolean} props.canBurn
     * @param {"visible"|"hidden"} props.documentVisibility
     * @param {import("preact").ComponentChild} props.children
     * @param {string} props.title
     * @param {string} props.url
     * @param {string|null|undefined} props.favoriteSrc
     * @param {number} props.faviconMax
     * @param {string} props.etldPlusOne
     */
    function ActivityItem({ canBurn, documentVisibility, title, url, favoriteSrc, faviconMax, etldPlusOne, children }) {
        return (
            <li key={url} class={cn(styles.item)} data-testid="ActivityItem">
                <div class={styles.heading}>
                    <a class={styles.title} href={url} data-url={url}>
                        <span className={styles.favicon} data-url={url}>
                            {documentVisibility === 'visible' && (
                                <FaviconWithState
                                    faviconSrc={favoriteSrc}
                                    faviconMax={faviconMax}
                                    etldPlusOne={etldPlusOne}
                                    theme={'light'}
                                    displayKind={'history-favicon'}
                                    key={`${favoriteSrc}:${faviconMax}`}
                                    fallback={DDG_FALLBACK_ICON}
                                    fallbackDark={DDG_FALLBACK_ICON_DARK}
                                />
                            )}
                        </span>
                        {title}
                    </a>
                    <Controls canBurn={canBurn} url={url} title={title} />
                </div>
                <div class={styles.body}>{children}</div>
            </li>
        );
    },
);

/**
 * Renders a set of control buttons that handle actions related to favorites and burn/removal features.
 *
 * @import enStrings from "../strings.json"
 * @param {Object} props - The input properties for the control buttons.
 * @param {boolean} props.canBurn - Indicates whether the burn action is allowed.
 * @param {string} props.url - The unique URL identifier for the associated item.
 * @param {string} props.title - The title or domain name displayed in the button tooltips.
 */
function Controls({ canBurn, url, title }) {
    const { t } = useTypedTranslationWith(/** @type {enStrings} */ ({}));
    const { activity } = useContext(NormalizedDataContext);
    const favorite = useComputed(() => activity.value.favorites[url]);

    // prettier-ignore
    const favoriteTitle = favorite.value
        ? t('activity_favoriteRemove', { domain: title })
        : t('activity_favoriteAdd', { domain: title });

    // prettier-ignore
    const secondaryTitle = canBurn
        ? t('activity_burn', { domain: title })
        : t('activity_itemRemove', { domain: title });
    return (
        <div className={styles.controls}>
            <button
                class={cn(styles.icon, styles.controlIcon, styles.disableWhenBusy)}
                title={favoriteTitle}
                data-action={favorite.value ? ACTION_REMOVE_FAVORITE : ACTION_ADD_FAVORITE}
                data-title={title}
                value={url}
                type="button"
            >
                {favorite.value ? <StarFilled /> : <Star />}
            </button>
            <button
                class={cn(styles.icon, styles.controlIcon, styles.disableWhenBusy)}
                title={secondaryTitle}
                data-action={canBurn ? ACTION_BURN : ACTION_REMOVE}
                value={url}
                type="button"
            >
                {canBurn ? <Fire /> : <Cross />}
            </button>
        </div>
    );
}
