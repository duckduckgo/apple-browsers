import { useId, useMemo } from 'preact/hooks';
import { Fragment, h } from 'preact';
import cn from 'classnames';
import styles from './Protections.module.css';
import { ProtectionsHeading } from './ProtectionsHeading.js';
import { useTypedTranslationWith } from '../../types.js';

/**
 * @import enStrings from "../strings.json"
 * @typedef {enStrings} Strings
 * @typedef {import('../../../types/new-tab.js').TrackerCompany} TrackerCompany
 * @typedef {import('../../../types/new-tab.js').Expansion} Expansion
 * @typedef {import('../../../types/new-tab.js').ProtectionsData} ProtectionsData
 * @typedef {import('../../../types/new-tab.js').ProtectionsConfig} ProtectionsConfig
 */

/**
 * @param {object} props
 * @param {Expansion} props.expansion
 * @param {import("@preact/signals").Signal<number>} props.blockedCountSignal
 * @param {ProtectionsConfig['feed']} props.feed
 * @param {(feed: ProtectionsConfig['feed']) => void} props.setFeed
 * @param {import("preact").ComponentChild} [props.children]
 * @param {()=>void} props.toggle
 */
export function Protections({ expansion = 'expanded', children, blockedCountSignal, feed, toggle, setFeed }) {
    const WIDGET_ID = useId();
    const TOGGLE_ID = useId();

    const attrs = useMemo(() => {
        return {
            'aria-controls': WIDGET_ID,
            id: TOGGLE_ID,
        };
    }, [WIDGET_ID, TOGGLE_ID]);

    return (
        <div class={styles.root}>
            <ProtectionsHeading
                blockedCountSignal={blockedCountSignal}
                onToggle={toggle}
                expansion={expansion}
                canExpand={true}
                buttonAttrs={attrs}
            />
            <ProtectionsBody feed={feed} setFeed={setFeed} id={WIDGET_ID} expansion={expansion}>
                {children}
            </ProtectionsBody>
        </div>
    );
}

/**
 * @param {object} props
 * @param {ProtectionsConfig['feed']} props.feed
 * @param {string} props.id
 * @param {Expansion} props.expansion
 * @param {import("preact").ComponentChild} props.children
 * @param {(feed: ProtectionsConfig['feed']) => void} props.setFeed
 */
function ProtectionsBody({ feed, id, expansion, setFeed, children }) {
    const hidden = expansion === 'collapsed';
    const showing = expansion === 'expanded';
    const { t } = useTypedTranslationWith(/** @type {enStrings} */ ({}));
    return (
        <div class={styles.body} id={id} aria-hidden={hidden} aria-expanded={showing}>
            {expansion === 'expanded' && (
                <Fragment>
                    <div class={cn(styles.switcher, styles.block)}>
                        <button
                            class={cn(styles.button, feed === 'privacy-stats' && styles.active)}
                            onClick={() => setFeed('privacy-stats')}
                        >
                            {t('protections_statsSwitchTitle')}
                        </button>
                        <button class={cn(styles.button, feed === 'activity' && styles.active)} onClick={() => setFeed('activity')}>
                            {t('protections_activitySwitchTitle')}
                        </button>
                    </div>
                    <div class={styles.feed}>{children}</div>
                </Fragment>
            )}
        </div>
    );
}

/**
 * Use this for empty-state text
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function ProtectionsEmpty({ children }) {
    return <div class={cn(styles.block, styles.empty)}>{children}</div>;
}
