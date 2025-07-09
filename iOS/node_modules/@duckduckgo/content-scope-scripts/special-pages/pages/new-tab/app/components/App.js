import { Fragment, h } from 'preact';
import cn from 'classnames';
import styles from './App.module.css';
import { useCustomizerDrawerSettings, usePlatformName } from '../settings.provider.js';
import { WidgetList } from '../widget-list/WidgetList.js';
import { useGlobalDropzone } from '../dropzone.js';
import { CustomizerButton, CustomizerMenuPositionedFixed, useContextMenu } from '../customizer/components/CustomizerMenu.js';
import { useDrawer, useDrawerControls } from './Drawer.js';
import { CustomizerDrawer } from '../customizer/components/CustomizerDrawer.js';
import { BackgroundConsumer } from './BackgroundProvider.js';
import { useComputed } from '@preact/signals';
import { CustomizerThemesContext } from '../customizer/CustomizerProvider.js';
import { useContext } from 'preact/hooks';
import { InlineErrorBoundary } from '../InlineErrorBoundary.js';

/**
 * Renders the App component.
 *
 * @param {Object} props - The properties of the component.
 * @param {import("preact").ComponentChild} [props.children] - The child components to be rendered within the App component.
 */
export function App() {
    const platformName = usePlatformName();
    const customizerDrawer = useCustomizerDrawerSettings();

    useGlobalDropzone();
    useContextMenu();

    // prettier-ignore
    const {
        buttonRef,
        asideRef,
        visibility,
        displayChildren,
        animating,
        hidden,
        buttonId,
        drawerId
    } = useDrawer(customizerDrawer.autoOpen ? 'visible' : 'hidden');

    const tabIndex = useComputed(() => (hidden.value ? -1 : 0));
    const isOpen = useComputed(() => hidden.value === false);
    const { toggle } = useDrawerControls();
    const { main, browser } = useContext(CustomizerThemesContext);

    return (
        <Fragment>
            <BackgroundConsumer browser={browser} />
            <div class={styles.layout} data-animating={animating} data-drawer-visibility={visibility}>
                <main class={cn(styles.main, styles.mainLayout, styles.mainScroller)} data-main-scroller data-theme={main}>
                    <div class={styles.content}>
                        <div className={styles.tube} data-content-tube data-platform={platformName}>
                            <WidgetList />
                        </div>
                    </div>
                </main>
                <div class={styles.themeContext} data-theme={main}>
                    <CustomizerMenuPositionedFixed>
                        <CustomizerButton
                            buttonId={buttonId}
                            menuId={drawerId}
                            toggleMenu={toggle}
                            buttonRef={buttonRef}
                            isOpen={isOpen}
                            kind={'drawer'}
                        />
                    </CustomizerMenuPositionedFixed>
                </div>
                <aside
                    class={cn(styles.aside, styles.asideLayout, styles.asideScroller)}
                    tabindex={tabIndex}
                    aria-hidden={hidden}
                    data-theme={browser}
                    data-browser-panel
                    ref={asideRef}
                >
                    <div class={styles.asideContent}>
                        <InlineErrorBoundary
                            context={'Customizer Drawer'}
                            fallback={(message) => (
                                <div class={styles.paddedError}>
                                    <p>{message}</p>
                                </div>
                            )}
                        >
                            <CustomizerDrawer displayChildren={displayChildren} />
                        </InlineErrorBoundary>
                    </div>
                </aside>
            </div>
        </Fragment>
    );
}

export function AppLevelErrorBoundaryFallback({ children }) {
    return (
        <div class={styles.paddedError}>
            <p>{children}</p>
            <div class={styles.paddedErrorRecovery}>
                You can try to <button onClick={() => location.reload()}>Reload this page</button>
            </div>
        </div>
    );
}
