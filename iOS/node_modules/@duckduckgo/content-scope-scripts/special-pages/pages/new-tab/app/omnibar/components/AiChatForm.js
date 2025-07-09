import cn from 'classnames';
import { h } from 'preact';
import { useContext } from 'preact/hooks';
import { ArrowRightIcon } from '../../components/Icons';
import { useTypedTranslationWith } from '../../types';
import styles from './Omnibar.module.css';
import { OmnibarContext } from './OmnibarProvider';

/**
 * @typedef {import('../strings.json')} Strings
 */

/**
 * @param {object} props
 * @param {string} props.chat
 * @param {(chat: string) => void} props.setChat
 */
export function AiChatForm({ chat, setChat }) {
    const { submitChat } = useContext(OmnibarContext);
    const { t } = useTypedTranslationWith(/** @type {Strings} */ ({}));

    /** @type {(event: SubmitEvent) => void} */
    const onSubmit = (event) => {
        event.preventDefault();
        submitChat({
            chat,
            target: 'same-tab',
        });
    };

    return (
        <div class={styles.formWrap}>
            <form onSubmit={onSubmit} class={styles.form}>
                <div class={styles.inputRoot} style={{ viewTransitionName: 'omnibar-input-transition' }}>
                    <div class={styles.inputContainer} style={{ viewTransitionName: 'omnibar-input-transition2' }}>
                        <input
                            type="text"
                            class={styles.input}
                            value={chat}
                            placeholder={t('aiChatForm_placeholder')}
                            aria-label={t('aiChatForm_placeholder')}
                            autoComplete="off"
                            onChange={(event) => setChat(event.currentTarget.value)}
                        />
                        <div class={styles.inputActions}>
                            <button
                                class={cn(styles.inputAction, styles.squareButton, styles.aiSubmitButton)}
                                aria-label={t('aiChatForm_submitButtonLabel')}
                            >
                                <ArrowRightIcon />
                            </button>
                        </div>
                    </div>
                </div>
            </form>
        </div>
    );
}
