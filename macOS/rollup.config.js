import json from '@rollup/plugin-json';
import { terser } from "rollup-plugin-terser";
import { nodeResolve } from '@rollup/plugin-node-resolve';

export default [
    {
        input: 'DuckDuckGo/Autoconsent/Resources/userscript.js',
        output: [
            {
                file: 'DuckDuckGo/Autoconsent/Resources/autoconsent-bundle.js',
                format: 'iife'
            }
        ],
        plugins: [
            nodeResolve(),
            json(),
            terser(),
        ]
    }
]
