import styles from './SwitchBarDesktop.module.css';
import { h } from 'preact';
import cn from 'classnames';
import { useContext } from 'preact/hooks';
import { SwitchContext } from '../providers/SwitchProvider.jsx';
import { useTypedTranslation } from '../types.js';

/**
 * Renders the desktop version of the switch bar component.
 */
export function SwitchBarDesktop() {
    const { onChange, onDone, state } = useContext(SwitchContext);
    const { t } = useTypedTranslation();
    function blockClick(e) {
        if (state === 'exiting') {
            return e.preventDefault();
        }
    }

    const classes = cn({
        [styles.switchBarDesktop]: true,
        [styles.stateExiting]: state === 'exiting',
        [styles.stateCompleted]: state === 'completed',
    });

    return (
        <div class={classes} data-state={state} data-allow-animation={true} onTransitionEnd={onDone}>
            <label class={styles.label} onClick={blockClick}>
                <span class={styles.checkbox}>
                    <input class={styles.input} onChange={onChange} name="enabled" type="checkbox" checked={state !== 'showing'} />
                </span>
                <span class={styles.text}>{t('alwaysWatchHere')}</span>
            </label>
        </div>
    );
}
