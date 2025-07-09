import { esbuildPlugin } from '@web/dev-server-esbuild';
import { fileURLToPath } from 'url';

export default {
    files: ['tests-wtr/**/*.html', 'tests-wtr/**/*.test.ts'],
    nodeResolve: true,
    plugins: [
        esbuildPlugin({
            ts: true,
            tsconfig: fileURLToPath(new URL('./tsconfig.json', import.meta.url)),
            target: 'es2021',
            define: {
                BUNDLE_FILTERLIST: 'false',
            },
            json: true,
        }),
    ],
};
