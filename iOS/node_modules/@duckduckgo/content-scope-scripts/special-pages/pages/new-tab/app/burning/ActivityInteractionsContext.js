import { createContext } from 'preact';

export const ActivityInteractionsContext = createContext({
    /**
     * @type {(evt: MouseEvent) => void} _event
     */
    didClick(_event) {},
});
