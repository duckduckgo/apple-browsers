import { Fragment, h } from 'preact';
import { WidgetConfigContext, WidgetVisibilityProvider } from './widget-config.provider.js';
import { useContext } from 'preact/hooks';
import { useMessaging } from '../types.js';
import { ErrorBoundary } from '../../../../shared/components/ErrorBoundary.js';
import { Centered, VerticalSpace } from '../components/Layout.js';
import { INLINE_ERROR } from '../InlineErrorBoundary.js';
import { DebugCustomized } from '../telemetry/Debug.js';
import { useEnv } from '../../../../shared/components/EnvironmentProvider.js';

/**
 * @return {{factory: () => import("preact").ComponentChild}}
 */
function placeholderWidget() {
    return {
        factory: () => {
            return null;
        },
    };
}

/**
 * @param {string} id
 * @param {(message: string) => void} didCatch
 * @return {Promise<{factory: () => import("preact").ComponentChild}>}
 */
export async function widgetEntryPoint(id, didCatch) {
    try {
        const mod = await import(`../entry-points/${id}.js`);
        if (typeof mod.factory !== 'function') {
            console.error(`module found for ${id}, but missing 'factory' export`);
            return placeholderWidget();
        }
        return mod;
    } catch (e) {
        console.error(e);
        didCatch(e.toString());
        return placeholderWidget();
    }
}

export function WidgetList() {
    const { widgets, widgetConfigItems, entryPoints } = useContext(WidgetConfigContext);
    const messaging = useMessaging();
    const { env } = useEnv();

    /**
     * @param {string} message
     * @param {string} id
     */
    const didCatch = (message, id) => {
        const composed = `Widget '${id}' threw an exception: ` + message;
        messaging.reportPageException({ message: composed });
    };

    return (
        <Fragment>
            {widgets.map((widget, index) => {
                const isUserConfigurable = widgetConfigItems.find((item) => item.id === widget.id);
                const matchingEntryPoint = entryPoints[widget.id];
                /**
                 * If there's no config, it means the user does not control the visibility of the elements in question.
                 */
                if (!isUserConfigurable) {
                    return (
                        <ErrorBoundary key={widget.id} didCatch={({ message }) => didCatch(message, widget.id)} fallback={null}>
                            <WidgetLoader fn={matchingEntryPoint.factory} />
                        </ErrorBoundary>
                    );
                }

                /**
                 * This section is for elements that the user controls the visibility of
                 */
                return (
                    <WidgetVisibilityProvider key={widget.id} id={widget.id} index={index}>
                        <ErrorBoundary
                            key={widget.id}
                            didCatch={({ message }) => didCatch(message, widget.id)}
                            fallback={
                                <Centered data-entry-point={widget.id}>
                                    <VerticalSpace>
                                        <p>{INLINE_ERROR}</p>
                                        <p>Widget ID: {widget.id}</p>
                                    </VerticalSpace>
                                </Centered>
                            }
                        >
                            <WidgetLoader fn={matchingEntryPoint.factory} />
                        </ErrorBoundary>
                    </WidgetVisibilityProvider>
                );
            })}
            {env === 'development' && (
                <Centered data-entry-point="debug">
                    <DebugCustomized index={widgets.length} isOpenInitially={window.location.search.includes('debugWidget')} />
                </Centered>
            )}
        </Fragment>
    );
}

/**
 * This defers the call to `.factory`, which would otherwise not be caught
 * by the error boundaries.
 *
 * @param {object} props
 * @return {any}
 */
function WidgetLoader({ fn }) {
    const result = fn?.();
    return result;
}
