import { useEffect } from 'preact/hooks';

/**
 * Device orientation
 * @param {object} props
 * @param {(orientation: 'portrait' | 'landscape') => void} props.onChange
 */
export function OrientationProvider({ onChange }) {
    useEffect(() => {
        if (!screen.orientation?.type) {
            onChange(getOrientationFromWidth());
            return;
        }
        onChange(getOrientationFromScreen());
        const handleOrientationChange = () => {
            onChange(getOrientationFromScreen());
        };
        screen.orientation.addEventListener('change', handleOrientationChange);
        return () => screen.orientation.removeEventListener('change', handleOrientationChange);
    }, []);

    useEffect(() => {
        let timer;
        const listener = () => {
            clearTimeout(timer);
            timer = setTimeout(() => onChange(getOrientationFromWidth()), 300);
        };
        window.addEventListener('resize', listener);
        return () => window.removeEventListener('resize', listener);
    }, []);

    return null;
}

/**
 * Retrieves the current orientation of the screen.
 *
 * The orientation can either be 'portrait' or 'landscape' based on the height and width of the window.
 *
 * If the height of the window is greater than 500, then the orientation is considered 'portrait'. Otherwise,
 * if the screen.orientation.type includes the word 'landscape', then the orientation is considered 'landscape'.
 * Otherwise, the orientation is 'portrait'.
 *
 * @return {"portrait" | "landscape"} The current orientation of the screen. It can be either 'portrait' or 'landscape'.
 */
function getOrientationFromWidth() {
    return window.innerWidth > window.innerHeight ? 'landscape' : 'portrait';
}

/**
 * @return {"portrait" | "landscape"} The current orientation of the screen. It can be either 'portrait' or 'landscape'.
 */
function getOrientationFromScreen() {
    return screen.orientation.type.includes('landscape') ? 'landscape' : 'portrait';
}
