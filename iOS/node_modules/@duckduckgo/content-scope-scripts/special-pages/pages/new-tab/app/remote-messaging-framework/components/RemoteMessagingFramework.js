import { h, Fragment } from 'preact';
import cn from 'classnames';
import styles from './RemoteMessagingFramework.module.css';
import { useContext } from 'preact/hooks';
import { RMFContext } from '../RMFProvider.js';
import { DismissButton } from '../../components/DismissButton';
import { Button } from '../../../../../shared/components/Button/Button';
import { usePlatformName } from '../../settings.provider';

/**
 * @import { RMFMessage } from "../../../types/new-tab"
 * @param {object} props
 * @param {RMFMessage} props.message
 * @param {(id: string) => void} props.dismiss
 * @param {(id: string) => void} [props.primaryAction]
 * @param {(id: string) => void} [props.secondaryAction]
 */

export function RemoteMessagingFramework({ message, primaryAction, secondaryAction, dismiss }) {
    const { id, messageType, titleText, descriptionText } = message;
    const platform = usePlatformName();

    return (
        <div id={id} class={cn(styles.root, messageType !== 'small' && message.icon && styles.icon)}>
            {messageType !== 'small' && message.icon && (
                <span class={styles.iconBlock}>
                    <img src={`./icons/${message.icon}.svg`} alt="" />
                </span>
            )}
            <div class={styles.content}>
                <h2 class={styles.title}>{titleText}</h2>
                <p class={styles.description}>{descriptionText}</p>
                {messageType === 'big_two_action' && (
                    <div class={styles.btnRow}>
                        {platform === 'windows' ? (
                            <Fragment>
                                {primaryAction && message.primaryActionText.length > 0 && (
                                    <Button variant={'accentBrand'} onClick={() => primaryAction(id)}>
                                        {message.primaryActionText}
                                    </Button>
                                )}
                                {secondaryAction && message.secondaryActionText.length > 0 && (
                                    <Button variant={'standard'} onClick={() => secondaryAction(id)}>
                                        {message.secondaryActionText}
                                    </Button>
                                )}
                            </Fragment>
                        ) : (
                            <Fragment>
                                {secondaryAction && message.secondaryActionText.length > 0 && (
                                    <Button variant={'standard'} onClick={() => secondaryAction(id)}>
                                        {message.secondaryActionText}
                                    </Button>
                                )}
                                {primaryAction && message.primaryActionText.length > 0 && (
                                    <Button variant={'accentBrand'} onClick={() => primaryAction(id)}>
                                        {message.primaryActionText}
                                    </Button>
                                )}
                            </Fragment>
                        )}
                    </div>
                )}
            </div>
            {messageType === 'big_single_action' && message.primaryActionText && primaryAction && (
                <div class={styles.btnBlock}>
                    <Button variant="standard" onClick={() => primaryAction(id)}>
                        {message.primaryActionText}
                    </Button>
                </div>
            )}
            <DismissButton className={styles.dismissBtn} onClick={() => dismiss(id)} />
        </div>
    );
}

export function RMFConsumer() {
    const { state, primaryAction, secondaryAction, dismiss } = useContext(RMFContext);

    // `state.data.content` can be empty - meaning there's no message to display!
    if (state.status === 'ready' && state.data.content) {
        return (
            <RemoteMessagingFramework
                message={state.data.content}
                primaryAction={primaryAction}
                secondaryAction={secondaryAction}
                dismiss={dismiss}
            />
        );
    }
    return null;
}
