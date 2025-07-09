import cn from 'classnames';
import { Fragment, h } from 'preact';
import { useContext, useId } from 'preact/hooks';
import { eventToTarget } from '../../../../../shared/handlers';
import { AiChatIcon, SearchIcon } from '../../components/Icons.js';
import { usePlatformName } from '../../settings.provider';
import { useTypedTranslationWith } from '../../types';
import styles from './Omnibar.module.css';
import { OmnibarContext } from './OmnibarProvider';
import { SuggestionsList } from './SuggestionList.js';
import { useSuggestionInput } from './useSuggestionInput.js';
import { useSuggestions } from './useSuggestions';

/**
 * @typedef {import('../strings.json')} Strings
 */

/**
 * @param {object} props
 * @param {boolean} props.enableAi
 * @param {string} props.term
 * @param {(term: string) => void} props.setTerm
 */
export function SearchForm({ enableAi, term, setTerm }) {
    const { submitSearch, submitChat } = useContext(OmnibarContext);

    const { t } = useTypedTranslationWith(/** @type {Strings} */ ({}));
    const platformName = usePlatformName();
    const suggestionsListId = useId();

    const {
        suggestions,
        selectedSuggestion,
        setSelectedSuggestion,
        clearSelectedSuggestion,
        inputBase,
        inputSuggestion,
        onInputChange,
        onInputKeyDown,
        onInputClick,
        onFormBlur,
    } = useSuggestions({
        term,
        setTerm,
    });

    const inputRef = useSuggestionInput(inputBase, inputSuggestion);

    /** @type {(event: SubmitEvent) => void} */
    const onFormSubmit = (event) => {
        event.preventDefault();
        submitSearch({
            term,
            target: 'same-tab',
        });
    };

    return (
        <div class={styles.formWrap}>
            <form class={styles.form} onBlur={onFormBlur} onSubmit={onFormSubmit}>
                <div class={styles.inputRoot} style={{ viewTransitionName: 'omnibar-input-transition' }}>
                    <div class={styles.inputContainer} style={{ viewTransitionName: 'omnibar-input-transition2' }}>
                        <input
                            ref={inputRef}
                            type="text"
                            role="combobox"
                            class={styles.input}
                            placeholder={t('searchForm_placeholder')}
                            aria-label={t('searchForm_placeholder')}
                            aria-expanded={suggestions.length > 0}
                            aria-haspopup="listbox"
                            aria-controls={suggestionsListId}
                            aria-activedescendant={selectedSuggestion?.id}
                            spellcheck={false}
                            autoComplete="off"
                            autoCorrect="off"
                            autoCapitalize="off"
                            onChange={onInputChange}
                            onKeyDown={onInputKeyDown}
                            onClick={onInputClick}
                        />
                        <div class={styles.inputActions}>
                            <button type="submit" class={cn(styles.inputAction)} aria-label={t('searchForm_searchButtonLabel')} inert>
                                <SearchIcon />
                            </button>
                            {enableAi && (
                                <>
                                    <div class={styles.separator}></div>
                                    <button
                                        class={cn(styles.inputAction, styles.squareButton)}
                                        aria-label={t('searchForm_aiButtonLabel')}
                                        onClick={(event) => {
                                            event.preventDefault();
                                            submitChat({
                                                chat: term,
                                                target: eventToTarget(event, platformName),
                                            });
                                        }}
                                    >
                                        <AiChatIcon className={styles.aiChatIcon} />
                                    </button>
                                </>
                            )}
                        </div>
                    </div>
                </div>
                <SuggestionsList
                    id={suggestionsListId}
                    suggestions={suggestions}
                    selectedSuggestion={selectedSuggestion}
                    setSelectedSuggestion={setSelectedSuggestion}
                    clearSelectedSuggestion={clearSelectedSuggestion}
                />
            </form>
        </div>
    );
}
