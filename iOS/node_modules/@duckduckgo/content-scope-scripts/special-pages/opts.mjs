import { join } from 'node:path';
import { cwd } from '../scripts/script-utils.js';
const CWD = cwd(import.meta.url);

/**
 * @param {string} page
 * @param {ImportMeta['injectName']} injectName
 * @param {'development' | 'production'} nodeEnv
 * @param {string} [output] - optionally change the output folder
 * @return {import('esbuild').BuildOptions}
 */
export function baseEsbuildOptions(page, injectName, nodeEnv, output) {
    const pageDir = join(CWD, 'pages', page);
    const publicDir = join(pageDir, 'public');
    const srcDir = join(pageDir, 'src');
    const distDir = output || join(publicDir, 'dist');
    const entry = [join(srcDir, 'index.js'), join(srcDir, 'inline.js')];
    return {
        entryPoints: entry,
        outdir: distDir,
        bundle: true,
        format: 'iife',
        sourcemap: nodeEnv === 'development',
        target: 'safari14',
        logOverride: { 'unsupported-css-nesting': 'silent' },
        loader: {
            '.js': 'jsx',
            '.module.css': 'local-css',
            '.svg': 'file',
            '.data.svg': 'dataurl',
            '.jpg': 'file',
            '.png': 'file',
            '.riv': 'file',
            '.txt': 'file',
        },
        define: {
            'import.meta.env': JSON.stringify(nodeEnv),
            'import.meta.injectName': JSON.stringify(injectName),
            'import.meta.pageName': JSON.stringify(page),
        },
        // prettier-ignore
        dropLabels: injectName === 'integration'
            ? ['$WATCH']
            : ['$WATCH', '$INTEGRATION'],
    };
}
