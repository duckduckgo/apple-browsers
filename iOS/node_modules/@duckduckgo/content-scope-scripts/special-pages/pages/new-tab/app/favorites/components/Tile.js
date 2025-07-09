import { h } from 'preact';
import cn from 'classnames';
import { useId } from 'preact/hooks';
import { memo } from 'preact/compat';
import styles from './Tile.module.css';
import { DDG_DEFAULT_ICON_SIZE, DDG_FALLBACK_ICON, DDG_FALLBACK_ICON_DARK } from '../constants.js';
import { useItemState } from './PragmaticDND.js';
import { useTypedTranslationWith } from '../../types.js';
import { PlusIcon } from '../../components/Icons.js';
import { FaviconWithState } from '../../../../../shared/components/FaviconWithState.js';

/**
 * @import {Favorite} from '../../../types/new-tab'
 * @import enStrings from '../../strings.json'
 */

export const Tile = memo(
    /**
     * @param {object} props
     * @param {Favorite['url']} props.url
     * @param {Favorite['etldPlusOne']} props.etldPlusOne
     * @param {Favorite['id']} props.id
     * @param {Favorite['title']} props.title
     * @param {string|null|undefined} props.faviconSrc
     * @param {number|null|undefined} props.faviconMax
     * @param {Document['visibilityState']} props.visibility - whether this item is actually visible on screen, or not
     * @param {"dark"|"light"} props.theme
     * @param {number} props.index
     * @param {boolean} props.animateItems
     */
    function Tile({ url, etldPlusOne, faviconSrc, faviconMax, theme, index, title, id, visibility, animateItems }) {
        const { state, ref } = useItemState(url, id, {
            kind: 'draggable',
            class: styles.preview,
            theme,
        });

        const tileId = useId();

        return (
            <a
                class={styles.item}
                tabindex={0}
                href={url}
                data-id={id}
                data-index={index}
                data-edge={'closestEdge' in state && state.closestEdge}
                aria-labelledby={tileId}
                style={animateItems ? { viewTransitionName: `Tile-${id}` } : undefined}
                ref={ref}
            >
                <div class={cn(styles.icon, styles.draggable)}>
                    {visibility === 'visible' && (
                        <FaviconWithState
                            faviconSrc={faviconSrc}
                            faviconMax={faviconMax || DDG_DEFAULT_ICON_SIZE}
                            theme={theme}
                            etldPlusOne={etldPlusOne}
                            displayKind={'favorite-tile'}
                            fallback={DDG_FALLBACK_ICON}
                            fallbackDark={DDG_FALLBACK_ICON_DARK}
                        />
                    )}
                </div>
                <div class={styles.text} id={tileId}>
                    {title}
                </div>
                {state.type === 'is-dragging-over' && state.closestEdge ? (
                    <div class={styles.dropper} data-edge={state.closestEdge} />
                ) : null}
            </a>
        );
    },
);

/**
 * Dotted-outline placeholder
 */
export function Placeholder() {
    const id = useId();
    const { state, ref } = useItemState(`PLACEHOLDER-URL-${id}`, `PLACEHOLDER-ID-${id}`, { kind: 'target' });
    return (
        <div class={styles.item} ref={ref} data-edge={'closestEdge' in state && state.closestEdge}>
            <div class={cn(styles.icon, styles.placeholder)}>&nbsp;</div>
            {state.type === 'is-dragging-over' && state.closestEdge ? <div class={styles.dropper} data-edge={state.closestEdge} /> : null}
        </div>
    );
}

/**
 * @param {object} props
 * @param {() => void} props.onClick
 */
function PlusIconWrapper({ onClick }) {
    const id = useId();
    const { t } = useTypedTranslationWith(/** @type {import('../strings.json')} */ ({}));
    const { state, ref } = useItemState(`PLACEHOLDER-URL-${id}`, `PLACEHOLDER-ID-${id}`, { kind: 'target' });
    return (
        <div class={styles.item} ref={ref} data-edge={'closestEdge' in state && state.closestEdge}>
            <button class={cn(styles.icon, styles.plus, styles.draggable)} aria-labelledby={id} onClick={onClick}>
                <PlusIcon />
            </button>
            <div class={styles.text} id={id}>
                {t('favorites_add')}
            </div>
            {state.type === 'is-dragging-over' && state.closestEdge ? <div class={styles.dropper} data-edge={state.closestEdge} /> : null}
        </div>
    );
}

export const PlusIconMemo = memo(PlusIconWrapper);
