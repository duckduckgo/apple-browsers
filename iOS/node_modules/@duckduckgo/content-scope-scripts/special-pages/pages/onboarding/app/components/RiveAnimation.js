import { h } from 'preact';
import { useEffect, useRef } from 'preact/hooks';
import { Rive } from '@rive-app/canvas-single';

/**
 * Renders a Rive animation on a canvas element and provides functionality to toggle inputs.
 *
 * @param {Object} props - The options for the RiveAnimation.
 * @param {'before' | 'after'} props.state - The name of the state machine to load.
 * @param {string} [props.stateMachine] - The name of the state machine to load. (optional)
 * @param {string} props.animation - The path to the animation file
 * @param {string} [props.artboard] - The name of the artboard to display. (optional)
 * @param {string} [props.inputName] - The name of the input to toggle. (optional)
 * @param {boolean} [props.autoplay=true] - Whether to autoplay the animation
 * @param {boolean} props.isDarkMode - Indicates if dark mode is enabled.
 */
export function RiveAnimation({ animation, state, stateMachine, artboard, inputName, autoplay = true, isDarkMode }) {
    const ref = useRef(/** @type {null | HTMLCanvasElement} */ (null));
    const rive = useRef(/** @type {null | Rive} */ (null));

    // create the instance
    useEffect(() => {
        if (!ref.current) return;
        rive.current = new Rive({
            src: ['dist', animation].join('/'),
            canvas: ref.current,
            enableRiveAssetCDN: false,
            autoplay,
            artboard,
            stateMachines: stateMachine,
        });
        return () => {
            rive.current?.cleanup();
        };
    }, [stateMachine, inputName, artboard, autoplay]);

    // handle a before/after value
    useEffect(() => {
        if (!stateMachine) return;
        const inputs = rive.current?.stateMachineInputs(stateMachine);
        if (!inputs) return;
        if (!inputName) return;

        const toggle = inputs.find((i) => i.name === inputName);
        if (!toggle) return console.warn('could not find input');
        if (state === 'after') toggle.value = true;
        if (state === 'before') toggle.value = false;
    }, [state]);

    // handle light/dark mode
    useEffect(() => {
        function handle() {
            if (!stateMachine) return;
            const inputs = rive.current?.stateMachineInputs(stateMachine);
            const themeInput = inputs?.find((i) => i.name.startsWith('Light'));
            if (themeInput) {
                themeInput.value = !isDarkMode;
            }
        }
        handle();
        rive.current?.on(/** @type {any} */ ('load'), handle);
        return () => {
            rive.current?.off(/** @type {any} */ ('load'), handle);
        };
    }, [isDarkMode]);

    return <canvas width="432" height="208" ref={ref} style="border-radius: 12px; overflow: hidden"></canvas>;
}
