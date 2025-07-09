import { h } from 'preact';
import cn from 'classnames';
import styles from './SwitchBarMobile.module.css';
import { useContext, useId } from 'preact/hooks';
import { SwitchContext } from '../providers/SwitchProvider.jsx';
import { Switch } from './Switch.jsx';
import { useTypedTranslation } from '../types.js';

/**
 * Renders a switch bar component.
 *
 * @param {Object} props - The properties for the switch bar component.
 * @param {ImportMeta['platform']} props.platformName - The name of the platform.
 */
export function SwitchBarMobile({ platformName }) {
    const { onChange, onDone, state } = useContext(SwitchContext);
    const { t } = useTypedTranslation();
    const inputId = useId();

    function blockClick(e) {
        if (state === 'exiting') {
            return e.preventDefault();
        }
    }

    function onTransitionEnd(e) {
        // check it's the root element that's finished animating
        if (e.target?.dataset?.state === 'exiting') {
            onDone();
        }
    }

    const classes = cn({
        [styles.switchBar]: true,
        [styles.stateExiting]: state === 'exiting',
        [styles.stateHidden]: state === 'completed',
    });

    return (
        <div class={classes} data-state={state} data-allow-animation="true" onTransitionEnd={onTransitionEnd}>
            <div class={styles.labelRow} onClick={blockClick}>
                <label for={inputId} class={styles.label}>
                    <span className={styles.text}>{t('keepEnabled')}</span>
                </label>
                <Switch checked={state !== 'showing'} onChange={onChange} platformName={platformName} id={inputId} />
            </div>
        </div>
    );
}
