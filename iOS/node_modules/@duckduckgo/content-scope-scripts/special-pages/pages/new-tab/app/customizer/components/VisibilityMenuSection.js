import { useLayoutEffect, useState } from 'preact/hooks';
import { getItems, UPDATE_EVENT } from './CustomizerMenu.js';
import { EmbeddedVisibilityMenu } from './VisibilityMenu.js';
import { h } from 'preact';

export function VisibilityMenuSection() {
    const [rowData, setRowData] = useState(() => {
        const items = /** @type {import("./CustomizerMenu.js").VisibilityRowData[]} */ (getItems());
        return items;
    });
    useLayoutEffect(() => {
        function handler() {
            setRowData(getItems());
        }

        window.addEventListener(UPDATE_EVENT, handler);
        return () => {
            window.removeEventListener(UPDATE_EVENT, handler);
        };
    }, []);

    return <EmbeddedVisibilityMenu rows={rowData} />;
}
