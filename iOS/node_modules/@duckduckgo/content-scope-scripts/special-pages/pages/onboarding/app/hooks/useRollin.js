import { useEffect, useReducer } from 'preact/hooks';

import { useEnv } from '../../../../shared/components/EnvironmentProvider';

/**
 * @typedef {Object} RollInState
 * @property {number} current
 * @property {boolean} isLast
 * @property {'start-trigger' | number} frame
 * @property {('start-trigger' | number)[]} frames
 */

/**
 * @param {('start-trigger' | number)[]} frames - An array of frames to be iterated over.
 * @return {{state: RollInState, advance: () => void}} - An object containing the current state and an 'advance' function.
 */
export function useRollin(frames) {
    const { isReducedMotion } = useEnv();
    const [state, dispatch] = useReducer((/** @type {RollInState} */ prev) => {
        if (prev.current === prev.frames.length) {
            return prev;
        }
        const next = prev.current + 1;
        return {
            ...prev,
            current: next,
            frame: prev.frames[next],
            isLast: next === prev.frames.length,
        };
    }, /** @type {RollInState} */ ({ current: 0, frames, frame: frames[0], isLast: false }));

    const current = state.current;
    const frame = state.frame;

    useEffect(() => {
        if (frame === 'start-trigger') return;
        if (typeof frame === 'number') {
            const i = setTimeout(() => dispatch('advance'), isReducedMotion ? 0 : frame);
            return () => clearTimeout(i);
        }
        return () => {
            // 'no-op'
        };
    }, [current, frame]);

    return {
        state,
        advance: () => {
            dispatch('advance');
        },
    };
}
