import { h } from 'preact';
import cn from 'classnames';
import { Cross } from './Icons';
import { useTypedTranslation } from '../types';
import styles from './DismissButton.module.css';

/**
 * @param {object} props
 * @param {string} [props.className]
 * @param {() => void} [props.onClick]
 * @param {import("preact").ComponentProps<"button"> & Record<string, string>} [props.buttonProps]
 */
export function DismissButton({ className, onClick, buttonProps = {} }) {
    const { t } = useTypedTranslation();

    return (
        <button class={cn(styles.btn, className)} onClick={onClick} aria-label={t('ntp_dismiss')} data-testid="dismissBtn" {...buttonProps}>
            <Cross />
        </button>
    );
}
