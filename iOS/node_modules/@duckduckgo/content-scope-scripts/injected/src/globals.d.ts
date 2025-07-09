declare namespace contentScopeFeatures {
    function init(args: object): void;
    function load(args: object): void;
    function update(args: object): void;
}

/**
 * Allows checks like `import.meta.env === "development"'
 */
interface ImportMeta {
    env: 'production' | 'development';
    platform?: 'windows' | 'macos' | 'android' | 'ios' | 'extension';
    // this represents the different build artifact names
    injectName?:
        | 'firefox'
        | 'apple'
        | 'apple-isolated'
        | 'android'
        | 'windows'
        | 'integration'
        | 'chrome-mv3'
        | 'android-broker-protection'
        | 'android-autofill-password-import';
    trackerLookup?: Record<string, unknown>;
    pageName?: string;
}

declare module '*.svg' {
    const content: string;
    export default content;
}
declare module '*.module.css' {
    const content: Record<string, string>;
    export default content;
}
declare module '*.css' {
    const content: string;
    export default content;
}
declare module '*.riv' {
    const filepath: string;
    export default filepath;
}

declare module 'ddg:platformFeatures' {
    const output: Record<
        string,
        new (featureName: string, importConfig: ImportConfig, args: LoadArgs) => import('./content-feature').default
    >;
    export default output;
}
