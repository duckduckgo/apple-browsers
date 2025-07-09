import { useContext, useState } from 'preact/hooks';
import { h, createContext } from 'preact';
import { useMessaging } from '../types.js';
import { useEffect } from 'preact/hooks';

/**
 * @typedef {import("../../types/duckplayer.js").UserValues} UserValues
 */

const UserValuesContext = createContext({
    /** @type {UserValues} */
    value: {
        privatePlayerMode: { alwaysAsk: {} },
        overlayInteracted: false,
    },
    /**
     * @type {() => void}
     */
    setEnabled: () => {
        // throw new Error('must implement')
    },
});

/**
 * @param {object} props
 * @param {UserValues} props.initial
 * @param {import("preact").ComponentChild} props.children
 */
export function UserValuesProvider({ initial, children }) {
    // initial state
    const [value, setValue] = useState(initial);
    const messaging = useMessaging();

    // listen for updates
    useEffect(() => {
        window.addEventListener('toggle-user-values-enabled', () => {
            setValue({ privatePlayerMode: { enabled: {} }, overlayInteracted: false });
        });
        window.addEventListener('toggle-user-values-ask', () => {
            setValue({ privatePlayerMode: { alwaysAsk: {} }, overlayInteracted: false });
        });
        const unsubscribe = messaging.onUserValuesChanged((userValues) => {
            setValue(userValues);
        });
        return () => unsubscribe();
    }, [messaging]);

    // API for consumers
    function setEnabled() {
        const values = {
            privatePlayerMode: { enabled: {} },
            overlayInteracted: false,
        };
        messaging
            .setUserValues(values)
            .then((next) => {
                console.log('response after setUserValues...', next);
                console.log('will set', values);
                setValue(values);
            })
            .catch((err) => {
                console.error('could not set the enabled flag', err);
                messaging.reportPageException({ message: 'could not set the enabled flag: ' + err.toString() });
            });
    }

    return <UserValuesContext.Provider value={{ value, setEnabled }}>{children}</UserValuesContext.Provider>;
}

export function useUserValues() {
    return useContext(UserValuesContext).value;
}

export function useSetEnabled() {
    return useContext(UserValuesContext).setEnabled;
}
