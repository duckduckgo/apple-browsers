import { h } from 'preact';
import styles from './CustomizerDrawer.module.css';
import { useContext } from 'preact/hooks';
import { CustomizerContext } from '../CustomizerProvider.js';
import { CustomizerDrawerInner } from './CustomizerDrawerInner.js';

/**
 * @param {object} props
 * @param {import("@preact/signals").Signal<boolean>} props.displayChildren
 */
export function CustomizerDrawer({ displayChildren }) {
    return <div class={styles.root}>{displayChildren.value === true && <CustomizerConsumer />}</div>;
}

function CustomizerConsumer() {
    const { data, select, upload, setTheme, deleteImage, customizerContextMenu } = useContext(CustomizerContext);
    return (
        <CustomizerDrawerInner
            data={data}
            select={select}
            onUpload={upload}
            setTheme={setTheme}
            deleteImage={deleteImage}
            customizerContextMenu={customizerContextMenu}
        />
    );
}
