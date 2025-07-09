import { h } from 'preact';
import { useState } from 'preact/hooks';
import { AiChatIcon, SearchIcon } from '../../components/Icons.js';
import { useTypedTranslationWith } from '../../types';
import { viewTransition } from '../../utils';
import { AiChatForm } from './AiChatForm';
import styles from './Omnibar.module.css';
import { SearchForm } from './SearchForm';

/**
 * @typedef {import('../strings.json')} Strings
 * @typedef {import('../../../types/new-tab.js').OmnibarConfig} OmnibarConfig
 */

/**
 * @param {object} props
 * @param {OmnibarConfig['mode']} props.mode
 * @param {(mode: OmnibarConfig['mode']) => void} props.setMode
 * @param {boolean} props.enableAi
 */
export function Omnibar({ mode, setMode, enableAi }) {
    const { t } = useTypedTranslationWith(/** @type {Strings} */ ({}));
    const [query, setQuery] = useState(/** @type {String} */ (''));
    return (
        <div class={styles.root} data-mode={mode}>
            <div class={styles.logoWrap}>
                <img src="./icons/Logo-Stacked.svg" alt={t('omnibar_logoAlt')} width={144} height={115.9} />
            </div>
            {enableAi && (
                <div class={styles.tabListWrap}>
                    <div class={styles.tabList} role="tablist" aria-label={t('omnibar_tabSwitcherLabel')}>
                        <button
                            class={styles.tab}
                            role="tab"
                            aria-selected={mode === 'search'}
                            onClick={() => {
                                viewTransition(() => {
                                    setMode('search');
                                });
                            }}
                        >
                            <SearchIcon className={styles.searchIcon} />
                            {t('omnibar_searchTabLabel')}
                        </button>
                        <button
                            class={styles.tab}
                            role="tab"
                            aria-selected={mode === 'ai'}
                            onClick={() => {
                                viewTransition(() => {
                                    setMode('ai');
                                });
                            }}
                        >
                            <AiChatIcon className={styles.aiChatIcon} />
                            {t('omnibar_aiTabLabel')}
                        </button>
                    </div>
                </div>
            )}
            {mode === 'search' ? (
                <SearchForm enableAi={enableAi} term={query} setTerm={setQuery} />
            ) : (
                <AiChatForm chat={query} setChat={setQuery} />
            )}
        </div>
    );
}
