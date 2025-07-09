import { useContext, useEffect, useState } from 'preact/hooks';
import { createContext, h } from 'preact';

const DocumentVisibilityContext = createContext(
    /** @type {DocumentVisibilityState} */
    ('hidden'),
);

/**
 * A component that provides the current document visibility state using a context.
 * Tracks changes in the document visibility (e.g., visible, hidden) and updates its state accordingly.
 *
 * @param {object} props - The properties object.
 * @param {import("preact").ComponentChild} props.children - The child elements to render within the provider.
 */
export function DocumentVisibilityProvider({ children }) {
    /** @type {Document['visibilityState']} */
    const initial = document.visibilityState;
    const [documentVisibility, setDocumentVisibility] = useState(initial);

    useEffect(() => {
        const handleVisibilityChange = () => {
            setDocumentVisibility(document.visibilityState);
        };

        document.addEventListener('visibilitychange', handleVisibilityChange);

        return () => {
            document.removeEventListener('visibilitychange', handleVisibilityChange);
        };
    }, []);

    return <DocumentVisibilityContext.Provider value={documentVisibility}>{children}</DocumentVisibilityContext.Provider>;
}

export function useDocumentVisibility() {
    return useContext(DocumentVisibilityContext);
}
