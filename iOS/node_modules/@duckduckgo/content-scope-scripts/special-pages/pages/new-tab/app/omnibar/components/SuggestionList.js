import { h } from 'preact';
import { useContext } from 'preact/hooks';
import { eventToTarget } from '../../../../../shared/handlers';
import { BookmarkIcon, BrowserIcon, FavoriteIcon, GlobeIcon, HistoryIcon, SearchIcon } from '../../components/Icons';
import { usePlatformName } from '../../settings.provider';
import { OmnibarContext } from './OmnibarProvider';
import styles from './SuggestionList.module.css';

/**
 * @typedef {import('./useSuggestions').SuggestionModel} SuggestionModel
 */

/**
 * @param {object} props
 * @param {string} props.id
 * @param {SuggestionModel[]} props.suggestions
 * @param {SuggestionModel | null} props.selectedSuggestion
 * @param {(suggestion: SuggestionModel) => void} props.setSelectedSuggestion
 * @param {() => void} props.clearSelectedSuggestion
 */
export function SuggestionsList({ id, suggestions, selectedSuggestion, setSelectedSuggestion, clearSelectedSuggestion }) {
    const { openSuggestion } = useContext(OmnibarContext);
    const platformName = usePlatformName();
    return (
        <div role="listbox" id={id} class={styles.list}>
            {suggestions.map((suggestion) => {
                return (
                    <button
                        key={suggestion.id}
                        role="option"
                        id={suggestion.id}
                        class={styles.item}
                        aria-selected={suggestion === selectedSuggestion}
                        onMouseOver={() => setSelectedSuggestion(suggestion)}
                        onMouseLeave={() => clearSelectedSuggestion()}
                        onClick={(event) => {
                            event.preventDefault();
                            openSuggestion({ suggestion, target: eventToTarget(event, platformName) });
                        }}
                    >
                        <SuggestionIcon suggestion={suggestion} />
                        {suggestion.title}
                    </button>
                );
            })}
        </div>
    );
}

/**
 * @param {object} props
 * @param {SuggestionModel} props.suggestion
 */
function SuggestionIcon({ suggestion }) {
    switch (suggestion.kind) {
        case 'phrase':
            return <SearchIcon />;
        case 'website':
            return <GlobeIcon />;
        case 'historyEntry':
            return <HistoryIcon />;
        case 'bookmark':
            return suggestion.isFavorite ? <FavoriteIcon /> : <BookmarkIcon />;
        case 'openTab':
        case 'internalPage':
            return <BrowserIcon />;
        default:
            throw new Error('Unknown suggestion kind');
    }
}
