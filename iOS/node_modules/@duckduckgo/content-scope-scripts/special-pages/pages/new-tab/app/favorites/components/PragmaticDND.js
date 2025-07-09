import { h, createContext } from 'preact';
import { useContext, useEffect, useRef, useState } from 'preact/hooks';

import { monitorForElements, draggable, dropTargetForElements } from '@atlaskit/pragmatic-drag-and-drop/element/adapter';
import { extractClosestEdge, attachClosestEdge } from '@atlaskit/pragmatic-drag-and-drop-hitbox/closest-edge';
import { reorderWithEdge } from '@atlaskit/pragmatic-drag-and-drop-hitbox/util/reorder-with-edge';
import { getReorderDestinationIndex } from '@atlaskit/pragmatic-drag-and-drop-hitbox/util/get-reorder-destination-index';
import { monitorForExternal, dropTargetForExternal } from '@atlaskit/pragmatic-drag-and-drop/external/adapter';
import { combine } from '@atlaskit/pragmatic-drag-and-drop/combine';
import { getHTML } from '@atlaskit/pragmatic-drag-and-drop/external/html';
import { DDG_MIME_TYPE } from '../constants.js';
import { setCustomNativeDragPreview } from '@atlaskit/pragmatic-drag-and-drop/element/set-custom-native-drag-preview';
import { centerUnderPointer } from '@atlaskit/pragmatic-drag-and-drop/element/center-under-pointer';

/** @type {import("preact").Context<symbol>} */
const InstanceIdContext = createContext(getInstanceId());

/**
 * Entry point for Pragmatic DND
 * https://github.com/atlassian/pragmatic-drag-and-drop
 *
 * Wrap your list in this, and then `useItemState` on your individual items
 *
 * @template {{id: string, url: string}} T
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 * @param {T[]} props.items
 * @param {(args: {id: string; list: T[], fromIndex: number, targetIndex: number}) => void} props.itemsDidReOrder
 */
export function PragmaticDND({ children, items, itemsDidReOrder }) {
    /**
     * Unique id for this instance
     */
    const [instanceId] = useState(getInstanceId);

    /**
     * Register the event handlers for drag-n-drop
     */
    useGridState(items, itemsDidReOrder, instanceId);

    return <InstanceIdContext.Provider value={instanceId}>{children}</InstanceIdContext.Provider>;
}

/**
 * @template {{id: string; url: string}} T
 * @param {T[]} favorites
 * @param {(args: {id: string; list: T[], fromIndex: number, targetIndex: number}) => void} itemsDidReOrder
 * @param {symbol} instanceId
 */
function useGridState(favorites, itemsDidReOrder, instanceId) {
    useEffect(() => {
        return combine(
            monitorForExternal({
                onDrop(payload) {
                    // const data = '<meta name="application/vnd.duckduckgo.bookmark-by-id" content="3" />';
                    const id = idFromPayload(payload);
                    if (!id) return;

                    const location = payload.location;
                    const target = location.current.dropTargets[0];

                    if (!target || !target.data || typeof target.data.url !== 'string') {
                        return console.warn('missing data from target');
                    }

                    const closestEdgeOfTarget = extractClosestEdge(target.data);
                    const destinationSrc = target.data.url;
                    let indexOfTarget = favorites.findIndex((item) => item.url === destinationSrc);
                    if (indexOfTarget === -1 && destinationSrc.includes('PLACEHOLDER-URL')) {
                        indexOfTarget = favorites.length;
                    }
                    const targetIndex = getReorderDestinationIndex({
                        closestEdgeOfTarget,
                        startIndex: favorites.length,
                        indexOfTarget,
                        axis: 'horizontal',
                    });

                    itemsDidReOrder({
                        list: favorites,
                        id,
                        fromIndex: favorites.length,
                        targetIndex,
                    });
                },
            }),
            monitorForElements({
                canMonitor({ source }) {
                    return source.data.instanceId === instanceId;
                },
                onDrop({ source, location }) {
                    const target = location.current.dropTargets[0];
                    if (!target) {
                        return;
                    }

                    const destinationSrc = target.data.url;
                    const destinationId = target.data.id;
                    const startId = source.data.id;

                    if (typeof startId !== 'string') {
                        return console.warn('could not access startId');
                    }

                    if (typeof destinationSrc !== 'string') {
                        return console.warn('could not access the destinationSrc');
                    }

                    const startIndex = favorites.findIndex((item) => item.id === startId);
                    let indexOfTarget = favorites.findIndex((item) => item.id === destinationId);

                    if (indexOfTarget === -1 && destinationSrc.includes('PLACEHOLDER-URL')) {
                        indexOfTarget = favorites.length;
                    }

                    const closestEdgeOfTarget = extractClosestEdge(target.data);

                    // where should the element be inserted?
                    // we only use this value to send to the native side
                    const targetIndex = getReorderDestinationIndex({
                        closestEdgeOfTarget,
                        startIndex,
                        indexOfTarget,
                        axis: 'horizontal',
                    });

                    // reorder the list using the helper from the dnd lib
                    const reorderedList = reorderWithEdge({
                        list: favorites,
                        startIndex,
                        indexOfTarget,
                        closestEdgeOfTarget,
                        axis: 'horizontal',
                    });

                    itemsDidReOrder({
                        list: reorderedList,
                        id: startId,
                        fromIndex: startIndex,
                        targetIndex,
                    });
                },
            }),
        );
    }, [instanceId, favorites]);
}

/**
 * @typedef {{ type: 'idle' }
 *         | { type: 'dragging' }
 *         | { type: 'is-dragging-over'; closestEdge: null | import("@atlaskit/pragmatic-drag-and-drop-hitbox/closest-edge").Edge }
 * } DNDState
 */

/**
 * @param {string} url
 * @param {string} id
 * @param {{kind: "draggable" | "target"; class?: string; theme?: string}} opts
 * @return {{ ref: import("preact").RefObject<any>; state: DNDState }}
 */
export function useItemState(url, id, opts) {
    const instanceId = useContext(InstanceIdContext);
    /** @type {import("preact").Ref<HTMLAnchorElement>} */
    const ref = useRef(null);
    const [state, setState] = useState(/** @type {DNDState} */ ({ type: 'idle' }));

    useEffect(() => {
        const el = ref.current;
        if (!el) throw new Error('unreachable');
        let draggableCleanup = () => {};

        if (opts.kind === 'draggable') {
            draggableCleanup = draggable({
                element: el,
                getInitialData: () => ({ type: 'grid-item', url, id, instanceId }),
                getInitialDataForExternal: () => ({
                    'text/plain': url,
                    [DDG_MIME_TYPE]: id,
                }),
                onDragStart: () => setState({ type: 'dragging' }),
                onDrop: () => setState({ type: 'idle' }),
                onGenerateDragPreview: ({ nativeSetDragImage, source }) => {
                    setCustomNativeDragPreview({
                        getOffset: ({ container }) => centerUnderPointer({ container }),
                        render: ({ container }) => {
                            const clone = /** @type {HTMLElement} */ (source.element.cloneNode(true));
                            const outer = document.createElement('div');
                            outer.classList.add(opts.class ?? '');
                            outer.dataset.theme = opts.theme;
                            outer.appendChild(clone);
                            container.appendChild(outer);
                            return () => {
                                container.removeChild(outer);
                            };
                        },
                        nativeSetDragImage,
                    });
                },
            });
        }

        return combine(
            draggableCleanup,
            dropTargetForExternal({
                element: el,
                canDrop: ({ source }) => {
                    return source.types.some((type) => type === 'text/html');
                },
                getData: ({ input }) => {
                    return attachClosestEdge(
                        { url, id },
                        {
                            element: el,
                            input,
                            allowedEdges: ['left', 'right'],
                        },
                    );
                },
                onDrop: () => {
                    setState({ type: 'idle' });
                },
                onDragLeave: () => setState({ type: 'idle' }),
                onDrag: ({ self }) => {
                    const closestEdge = extractClosestEdge(self.data);
                    // Only need to update react state if nothing has changed.
                    // Prevents re-rendering.
                    setState((current) => {
                        if (current.type === 'is-dragging-over' && current.closestEdge === closestEdge) {
                            return current;
                        }
                        return { type: 'is-dragging-over', closestEdge };
                    });
                },
            }),
            dropTargetForElements({
                element: el,
                getData: ({ input }) => {
                    return attachClosestEdge(
                        { url, id },
                        {
                            element: el,
                            input,
                            allowedEdges: ['left', 'right'],
                        },
                    );
                },
                getIsSticky: () => false,
                canDrop: ({ source }) => {
                    return source.data.instanceId === instanceId && source.data.type === 'grid-item' && source.data.id !== id;
                },
                onDragEnter: ({ self }) => {
                    const closestEdge = extractClosestEdge(self.data);
                    setState({ type: 'is-dragging-over', closestEdge });
                },
                onDrag({ self }) {
                    const closestEdge = extractClosestEdge(self.data);
                    // Only need to update react state if nothing has changed.
                    // Prevents re-rendering.
                    setState((current) => {
                        if (current.type === 'is-dragging-over' && current.closestEdge === closestEdge) {
                            return current;
                        }
                        return { type: 'is-dragging-over', closestEdge };
                    });
                },
                onDragLeave: () => setState({ type: 'idle' }),
                onDrop: () => setState({ type: 'idle' }),
            }),
        );
    }, [instanceId, url, id, opts.kind, opts.class, opts.theme]);

    return { ref, state };
}

function getInstanceId() {
    return Symbol('instance-id');
}

/**
 * @import {ContainsSource} from "@atlaskit/pragmatic-drag-and-drop/dist/types/public-utils/external/native-types.js"
 * @param {ContainsSource} payload
 */
function idFromPayload(payload) {
    // return the external DDG type first
    const ddg = payload.source.getStringData(DDG_MIME_TYPE);
    if (ddg && ddg.length > 0) return ddg;

    // now try and parse the HTML, which might be `<meta name="application/vnd.duckduckgo.bookmark-by-id" content="3" />`
    const html = getHTML(payload);
    if (!html) return console.warn(`missing text/html payload + missing ${DDG_MIME_TYPE} mime type`);

    // Create a document fragment using the safer createContextualFragment
    const fragment = document.createRange().createContextualFragment(html);

    // Get the first element
    const node = fragment.firstElementChild;
    if (!node) return console.warn('missing first element');

    // check the name attribute
    if (node.getAttribute('name') !== DDG_MIME_TYPE) return console.warn(`attribute name was not ${DDG_MIME_TYPE}`);

    // check the id
    const id = node.getAttribute('content');
    if (!id) return console.warn('id missing from `content` attribute');

    return id;
}
