import tseslint from 'typescript-eslint';
import ddgConfig from '@duckduckgo/eslint-config';
import globals from 'globals';

// @ts-check
const c = tseslint.config(
    ...tseslint.configs.recommended,
    ...ddgConfig,

    {
        ignores: ['lib/consentomatic/**/*', 'dist/**/*'],
    },

    {
        languageOptions: {
            parserOptions: {
                projectService: true,
                tsconfigRootDir: import.meta.dirname,
            },
        },
    },

    {
        languageOptions: {
            globals: {
                ...globals.browser,
                ...globals.node,
            },

            ecmaVersion: 2021,
            sourceType: 'module',
        },

        rules: {
            '@typescript-eslint/no-explicit-any': 0,
            'no-unused-expressions': 0,
            '@typescript-eslint/no-unused-expressions': 0,
            '@typescript-eslint/no-require-imports': 0,
            '@typescript-eslint/no-unused-vars': [
                'error',
                {
                    args: 'none',
                    caughtErrors: 'none',
                    ignoreRestSiblings: true,
                    vars: 'all',
                },
            ],
            'no-undef': 'off',
        },
    },

    {
        files: ['addon/**/*'],
        languageOptions: {
            globals: {
                ...globals.webextensions,
            },
        },
    },

    {
        files: ['tests/**/*', 'tests-wtr/**/*'],
        languageOptions: {
            globals: {
                ...globals.jasmine,
                ...globals.chai,
                before: 'readonly',
            },
        },
    },
);

export default c;
