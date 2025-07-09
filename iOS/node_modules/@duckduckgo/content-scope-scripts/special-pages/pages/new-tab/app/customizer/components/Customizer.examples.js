import { h } from 'preact';
import { noop } from '../../utils.js';
import { CustomizerButton } from './CustomizerMenu.js';
import { EmbeddedVisibilityMenu } from './VisibilityMenu.js';
import { BackgroundSection } from './BackgroundSection.js';
import { ColorSelection } from './ColorSelection.js';
import { GradientSelection } from './GradientSelection.js';
import { useSignal } from '@preact/signals';
import { ImageSelection } from './ImageSelection.js';

/** @type {Record<string, {factory: () => import("preact").ComponentChild}>} */
export const customizerExamples = {
    'customizer.backgroundSection': {
        factory: () => {
            return (
                <Provider>
                    {({ data, select }) => {
                        return <BackgroundSection data={data} onNav={noop('onNav')} onUpload={noop('onUpload')} select={select} />;
                    }}
                </Provider>
            );
        },
    },
    'customizer.colorSelection': {
        factory: () => {
            return (
                <Provider>
                    {({ data, select }) => {
                        return <ColorSelection data={data} select={select} back={noop('back')} />;
                    }}
                </Provider>
            );
        },
    },
    'customizer.gradientSelection': {
        factory: () => {
            return (
                <Provider>
                    {({ data, select }) => {
                        return <GradientSelection data={data} select={select} back={noop('back')} />;
                    }}
                </Provider>
            );
        },
    },
    'customizer.imageSelection': {
        factory: () => {
            return (
                <Provider>
                    {({ data, select }) => {
                        return (
                            <ImageSelection
                                data={data}
                                select={select}
                                back={noop('back')}
                                onUpload={noop('onUpload')}
                                deleteImage={noop('deleteImage')}
                                customizerContextMenu={noop('customizerContextMenu')}
                            />
                        );
                    }}
                </Provider>
            );
        },
    },
    'customizer-menu': {
        factory: () => (
            <MaxContent>
                <CustomizerButton isOpen={true} kind="menu" />
                <br />
                <div style="width: 206px; border: 1px dotted black">
                    <EmbeddedVisibilityMenu
                        rows={[
                            {
                                id: 'favorites',
                                title: 'Favorites',
                                icon: 'star',
                                toggle: noop('toggle favorites'),
                                visibility: 'hidden',
                                index: 0,
                            },
                            {
                                id: 'privacyStats',
                                title: 'Privacy Stats',
                                icon: 'shield',
                                toggle: noop('toggle favorites'),
                                visibility: 'visible',
                                index: 1,
                            },
                        ]}
                    />
                </div>
            </MaxContent>
        ),
    },
};

function MaxContent({ children }) {
    return <div style={{ display: 'grid', gridTemplateColumns: 'max-content' }}>{children}</div>;
}

function Provider({ children }) {
    /** @type {import('../../../types/new-tab.js').CustomizerData} */
    const data = {
        background: { kind: 'hex', value: '#17afa8' },
        theme: 'system',
        userImages: [],
        userColor: null,
    };
    const dataSignal = useSignal(data);
    function select(bg) {
        dataSignal.value = { ...dataSignal.value, background: bg };
    }
    function showPicker() {
        console.log('no-op');
    }
    return children({ data: dataSignal, select, showPicker });
}
