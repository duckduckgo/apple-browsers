import { h } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import { useTelemetry } from '../types.js';
import { useCustomizer } from '../customizer/components/CustomizerMenu.js';
import { Telemetry } from './telemetry.js';

export function DebugCustomized({ index, isOpenInitially = false }) {
    const [isOpen, setOpen] = useState(isOpenInitially);
    const telemetry = useTelemetry();
    useCustomizer({
        title: '🐞 Debug',
        id: 'debug',
        icon: 'shield',
        visibility: isOpen ? 'visible' : 'hidden',
        toggle: (_id) => setOpen((prev) => !prev),
        index,
    });
    return <div>{isOpen && <Debug telemetry={telemetry} isOpen={true} />}</div>;
}

/**
 * @param {object} props
 * @param {import("./telemetry.js").Telemetry} props.telemetry
 * @param {boolean} props.isOpen
 */
export function Debug({ telemetry, isOpen }) {
    /** @type {import("preact").Ref<HTMLTextAreaElement>} */
    const textRef = useRef(null);
    useEvents(textRef, telemetry);
    return (
        <div hidden={!isOpen}>
            <textarea style={{ width: '100%' }} rows={20} ref={textRef}></textarea>
        </div>
    );
}

/**
 * @param {import("preact").RefObject<HTMLTextAreaElement>} ref
 * @param {import("./telemetry.js").Telemetry} telemetry
 */
function useEvents(ref, telemetry) {
    useEffect(() => {
        if (!ref.current) return;
        const elem = ref.current;
        const pre = '```json\n';
        const post = '\n```\n';
        function handle(/** @type {CustomEvent<any>} */ { detail }) {
            elem.value += pre + JSON.stringify(detail, null, 2) + post;
        }
        for (const beforeElement of telemetry.eventStore) {
            elem.value += pre + JSON.stringify(beforeElement, null, 2) + post;
        }
        telemetry.eventStore = [];
        telemetry.storeEnabled = false;
        telemetry.eventTarget.addEventListener(Telemetry.EVENT_BROADCAST, handle);
        return () => {
            telemetry.eventTarget.removeEventListener(Telemetry.EVENT_BROADCAST, handle);
            telemetry.storeEnabled = true;
        };
    }, [ref, telemetry]);
}
