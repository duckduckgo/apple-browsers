import { h } from 'preact';
import cn from 'classnames';
import { useContext } from 'preact/hooks';

import { DuckFoot, SearchIcon, Shield } from '../../components/Icons.js';
import styles from './VisibilityMenu.module.css';
import { Switch } from '../../../../../shared/components/Switch/Switch.js';
import { usePlatformName } from '../../settings.provider.js';
import { CustomizerThemesContext } from '../CustomizerProvider.js';

/**
 * @import { Widgets, WidgetConfigItem } from '../../../types/new-tab.js'
 * @import { VisibilityRowData } from './CustomizerMenu.js'
 */

/**
 * @param {object} props
 * @param {VisibilityRowData[]} props.rows
 */
export function EmbeddedVisibilityMenu({ rows }) {
    const platformName = usePlatformName();
    const { browser } = useContext(CustomizerThemesContext);
    return (
        <ul className={cn(styles.list, styles.embedded)}>
            {rows.map((row) => {
                return (
                    <li key={row.id}>
                        <div class={cn(styles.menuItemLabel, styles.menuItemLabelEmbedded)}>
                            <span className={styles.svg}>
                                {row.icon === 'shield' && <DuckFoot />}
                                {row.icon === 'star' && <Shield />}
                                {row.icon === 'search' && <SearchIcon />}
                            </span>
                            <span>{row.title ?? row.id}</span>
                            <Switch
                                theme={browser.value}
                                platformName={platformName}
                                checked={row.visibility === 'visible'}
                                size="medium"
                                onChecked={() => row.toggle?.(row.id)}
                                onUnchecked={() => row.toggle?.(row.id)}
                                ariaLabel={`Toggle ${row.title}`}
                                pending={false}
                            />
                        </div>
                    </li>
                );
            })}
        </ul>
    );
}
