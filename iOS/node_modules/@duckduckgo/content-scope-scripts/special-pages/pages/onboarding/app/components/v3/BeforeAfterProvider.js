import { h, createContext } from 'preact';
import { useContext, useState } from 'preact/hooks';
import { ORDER_V3 as steps } from '../../types';

/** @typedef {'before'|'after'} BeforeAfter */
/** @typedef {Partial<Record<steps[number], BeforeAfter>>} StepStates */

/** @type {BeforeAfter[]} */
const beforeAfterValues = ['before', 'after'];

const BeforeAfterContext = createContext({
    /**
     * @type {StepStates}
     */
    stepStates: {},

    /**
     * @param {steps[number]} step
     * @returns {BeforeAfter|null}
     */
    getStep: (step) => {
        console.log(step);
        return null;
    },

    /**
     * @param {steps[number]} step
     * @param {BeforeAfter} value
     */
    setStep: (step, value) => {
        console.log(step, value);
    },

    /**
     * @param {steps[number]} step
     */
    toggleStep: (step) => {
        console.log(step);
    },
});

/**
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function BeforeAfterProvider({ children }) {
    const [stepStates, setStepStates] = useState({});

    function getStep(step) {
        return stepStates[step] || null;
    }

    function setStep(step, value) {
        if (steps.includes(step) && beforeAfterValues.includes(value)) {
            setStepStates((prevState) => ({ ...prevState, [step]: value }));
        }
    }

    function toggleStep(step) {
        if (steps.includes(step)) {
            setStepStates((prevState) => {
                const newValue = prevState[step] === 'before' ? 'after' : 'before';
                return { ...prevState, [step]: newValue };
            });
        }
    }

    return <BeforeAfterContext.Provider value={{ stepStates, getStep, setStep, toggleStep }}>{children}</BeforeAfterContext.Provider>;
}

export function useBeforeAfter() {
    return useContext(BeforeAfterContext);
}
