import { h } from 'preact';
import cn from 'classnames';

import { useState } from 'preact/hooks';
import { DismissButton } from '../../components/DismissButton';
import { CheckColor } from '../../components/Icons';
import { useTypedTranslationWith } from '../../types';
import { variants, additionalCardStates } from '../nextsteps.data';
import styles from './NextSteps.module.css';

/**
 * @typedef {import('../../../types/new-tab').NextStepsCardTypes} NextStepsCardTypes
 *
 * @param {object} props
 * @param {NextStepsCardTypes} props.type
 * @param {(id: string) => void} props.dismiss
 * @param {(id: string) => void} props.action
 */

export function NextStepsCard({ type, dismiss, action }) {
    const { t } = useTypedTranslationWith(/** @type {import("../strings.json")} */ ({}));
    const message = variants[type]?.(t);
    const [showConfirmation, setShowConfirmation] = useState(false);
    const hasConfirmationState = additionalCardStates.hasConfirmationText(type);

    const handleClick = () => {
        if (!hasConfirmationState) {
            return action(message.id);
        }

        action(message.id);
        setShowConfirmation(true);
    };
    return (
        <div class={styles.card}>
            <img src={`./icons/${message.icon}-128.svg`} alt="" class={styles.icon} />
            <h3 class={styles.title}>{message.title}</h3>
            <p class={styles.description}>{message.summary}</p>
            {hasConfirmationState && !!showConfirmation ? (
                <div class={styles.confirmation}>
                    <CheckColor />
                    <p>{message.confirmationText}</p>
                </div>
            ) : (
                <button
                    class={cn(styles.btn, hasConfirmationState && styles.supressActiveStateForSwitchToConfirmationText)}
                    onClick={handleClick}
                >
                    {message.actionText}
                </button>
            )}

            <DismissButton className={styles.dismissBtn} onClick={() => dismiss(message.id)} />
        </div>
    );
}
