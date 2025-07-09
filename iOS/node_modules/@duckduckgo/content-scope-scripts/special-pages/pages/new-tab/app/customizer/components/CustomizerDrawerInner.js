import { Fragment, h } from 'preact';
import cn from 'classnames';
import styles from './CustomizerDrawerInner.module.css';
import { useDrawerControls } from '../../components/Drawer.js';
import { BackgroundSection } from './BackgroundSection.js';
import { BrowserThemeSection } from './BrowserThemeSection.js';
import { VisibilityMenuSection } from './VisibilityMenuSection.js';
import { ColorSelection } from './ColorSelection.js';
import { GradientSelection } from './GradientSelection.js';
import { batch, useSignal } from '@preact/signals';
import { ImageSelection } from './ImageSelection.js';
import { BorderedSection, CustomizerSection } from './CustomizerSection.js';
import { SettingsLink } from './SettingsLink.js';
import { DismissButton } from '../../components/DismissButton.jsx';
import { InlineErrorBoundary } from '../../InlineErrorBoundary.js';
import { useTypedTranslationWith } from '../../types.js';

/**
 * @import { Widgets, WidgetConfigItem, WidgetVisibility, VisibilityMenuItem, CustomizerData, BackgroundData, UserImageContextMenu } from '../../../types/new-tab.js'
 * @import enStrings from '../strings.json';
 */

/**
 * @param {object} props
 * @param {import('@preact/signals').Signal<CustomizerData>} props.data
 * @param {(bg: BackgroundData) => void} props.select
 * @param {() => void} props.onUpload
 * @param {(theme: import('../../../types/new-tab').ThemeData) => void} props.setTheme
 * @param {(id: string) => void} props.deleteImage
 * @param {(p: UserImageContextMenu) => void} props.customizerContextMenu
 */
export function CustomizerDrawerInner({ data, select, onUpload, setTheme, deleteImage, customizerContextMenu }) {
    const { close } = useDrawerControls();
    const { t } = useTypedTranslationWith(/** @type {enStrings} */ ({}));
    return (
        <div class={styles.root}>
            <header class={cn(styles.header, styles.internal)}>
                <h2>{t('customizer_drawer_title')}</h2>
                <DismissButton
                    onClick={close}
                    className={styles.closeBtn}
                    buttonProps={{
                        'aria-label': 'Close',
                    }}
                />
            </header>
            <InlineErrorBoundary
                format={(message) => `CustomizerDrawerInner threw an exception: ${message}`}
                fallback={(message) => (
                    <div class={styles.internal}>
                        <p>{message}</p>
                    </div>
                )}
            >
                <TwoCol
                    left={({ push }) => (
                        <div class={styles.sections}>
                            <CustomizerSection title={t('customizer_section_title_background')}>
                                <BackgroundSection data={data} onNav={push} onUpload={onUpload} select={select} />
                            </CustomizerSection>
                            <CustomizerSection title={t('customizer_section_title_theme')}>
                                <BrowserThemeSection data={data} setTheme={setTheme} />
                            </CustomizerSection>
                            <CustomizerSection title={t('customizer_section_title_sections')}>
                                <VisibilityMenuSection />
                            </CustomizerSection>
                            <BorderedSection>
                                <SettingsLink />
                            </BorderedSection>
                        </div>
                    )}
                    right={({ id, pop }) => (
                        <Fragment>
                            {id === 'color' && <ColorSelection data={data} select={select} back={pop} />}
                            {id === 'gradient' && <GradientSelection data={data} select={select} back={pop} />}
                            {id === 'image' && (
                                <ImageSelection
                                    data={data}
                                    select={select}
                                    back={pop}
                                    onUpload={onUpload}
                                    deleteImage={deleteImage}
                                    customizerContextMenu={customizerContextMenu}
                                />
                            )}
                        </Fragment>
                    )}
                />
            </InlineErrorBoundary>
        </div>
    );
}

/**
 * @param {object} props
 * @param {(args: {push: (id: string) => void}) => import('preact').ComponentChild} props.left
 * @param {(args: {id: string, pop: () => void}) => import('preact').ComponentChild} props.right
 */
function TwoCol({ left, right }) {
    const visibleScreen = useSignal('home');
    const renderedScreen = useSignal('home');
    const col1 = useSignal(true);

    /**
     * @param {string} id
     */
    function push(id) {
        visibleScreen.value = id;
        requestAnimationFrame(() => {
            renderedScreen.value = id;
        });
    }

    function pop() {
        batch(() => {
            col1.value = true;
            visibleScreen.value = 'home';
        });
    }

    function transitionEnded() {
        if (visibleScreen.value !== 'home') {
            col1.value = false;
        }
        renderedScreen.value = visibleScreen.value;
    }

    return (
        <div class={styles.colwrap}>
            <div class={styles.cols} data-sub={visibleScreen} onTransitionEnd={transitionEnded}>
                <div class={cn(styles.col, styles.col1)}>{col1.value && left({ push })}</div>
                <div class={cn(styles.col, styles.col2)}>{renderedScreen.value !== 'home' && right({ id: renderedScreen.value, pop })}</div>
            </div>
        </div>
    );
}
