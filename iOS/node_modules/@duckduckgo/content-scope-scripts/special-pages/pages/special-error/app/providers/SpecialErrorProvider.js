import { createContext, h } from 'preact';
import { useContext } from 'preact/hooks';

export const SpecialErrorContext = createContext(/** @type {import('../specialError.js').SpecialError} */ ({}));

/**
 * A component that provides information about the error page.
 *
 * @param {Object} props - The component props.
 * @param {import("preact").ComponentChild} [props.children] - The child elements.
 * @param {import('../specialError.js').SpecialError} props.specialError - The special error object.
 */
export function SpecialErrorProvider({ children, specialError }) {
    return <SpecialErrorContext.Provider value={specialError}>{children}</SpecialErrorContext.Provider>;
}

export function useErrorData() {
    return useContext(SpecialErrorContext).data;
}
