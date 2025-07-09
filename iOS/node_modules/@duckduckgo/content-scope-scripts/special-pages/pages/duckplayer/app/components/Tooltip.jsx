import { h } from 'preact';
import cn from 'classnames';
import styles from './Tooltip.module.css';
import { useTypedTranslation } from '../types.js';

/**
 * @param {object} props
 * @param {string} props.id
 * @param {boolean} props.isVisible
 * @param {'top' | 'bottom'} props.position
 */
export function Tooltip({ id, isVisible, position }) {
    const { t } = useTypedTranslation();
    return (
        <div
            class={cn(styles.tooltip, {
                [styles.top]: position === 'top',
                [styles.bottom]: position === 'bottom',
            })}
            role="tooltip"
            aria-hidden={!isVisible}
            id={id}
        >
            {t('tooltipInfo')}
        </div>
    );
}
