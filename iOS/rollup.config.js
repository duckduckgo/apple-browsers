import json from '@rollup/plugin-json';
import { terser } from "rollup-plugin-terser";
import { nodeResolve } from '@rollup/plugin-node-resolve';

export default [
    {
        input: 'DuckDuckGo/Autoconsent/userscript.js',
        output: [
            {
                file: 'DuckDuckGo/Autoconsent/autoconsent-bundle.js',
                format: 'iife'
            },
            {
                // Used while `blankFrameOptimizations` is on; skips about: frames.
                file: 'DuckDuckGo/Autoconsent/autoconsent-bundle-skip-blank-frames.js',
                format: 'iife',
                banner: "'use strict';\n{\nconst ddgAutoconsent = () => {",
                footer: "};\nif (window.location.protocol !== 'about:') {\n    ddgAutoconsent();\n}\n}"
            }
        ],
        plugins: [
            nodeResolve(),
            json(),
            terser(),
        ]
    }
]
