import { promises } from 'node:fs';

/**
 * @returns {import("esbuild").Plugin}
 */
export function commentPlugin() {
    const PLUGIN_ID = 'comment-override';

    /** @type {import("esbuild").Plugin} */
    const plugin = {
        name: PLUGIN_ID,
        setup(build) {
            build.onLoad({ filter: /.*/ }, async (args) => {
                if (!args.path.includes('node_modules')) return undefined;
                const text = await promises.readFile(args.path, 'utf8');
                return {
                    contents: convertToLegalComments(text.toString()),
                    loader: 'js',
                };
            });
        },
    };
    return plugin;
}

/**
 * Detect the start of a particular comment and change the
 * lines to have the prefix `//!` - this allows esbuild to keep it
 *
 * When a line is matched, continue to match further lines until a non-comment is seen.
 *
 * @param {string} source
 */
export function convertToLegalComments(source) {
    // Process block comments - find all block comments
    const blockComments = source.match(/\/\*[\s\S]*?\*\//g) || [];

    // Selectively replace only block comments that contain "copyright"
    let modifiedSource = source;
    for (const comment of blockComments) {
        if (/copyright/i.test(comment)) {
            // Replace only the block comments with copyright
            modifiedSource = modifiedSource.replace(comment, comment.replace(/\/\*/, '/*!'));
        }
    }

    // Process line comments
    const lines = modifiedSource.split('\n');
    const result = [];
    let inCommentBlock = false;

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];

        // Check if the line contains a block comment - this breaks any line comment sequence
        if (line.includes('/*') || line.includes('*/')) {
            inCommentBlock = false;
            result.push(line);
        }
        // Check if this line starts a line comment block with "copyright"
        else if (!inCommentBlock && /^\s*\/\/(?=.*copyright.*$)/i.test(line)) {
            // Start of a copyright comment - mark it and convert
            inCommentBlock = true;
            result.push(line.replace(/^\s*\/\//, (match) => match.replace('//', '//!')));
        }
        // Check if we're continuing a line comment block
        else if (inCommentBlock && /^\s*\/\//.test(line)) {
            // Continue the comment block - convert the prefix
            result.push(line.replace(/^\s*\/\//, (match) => match.replace('//', '//!')));
        }
        // Check if we're exiting a comment block
        else {
            // Not a comment line or doesn't match our criteria, end the block
            inCommentBlock = false;
            result.push(line);
        }
    }

    return result.join('\n');
}
