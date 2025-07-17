#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// Paths
const ROOT_DIR = path.resolve(__dirname, '../../..');
const SOURCE_DIR = path.join(ROOT_DIR, 'node_modules/@duckduckgo/content-scope-scripts/build/apple');
const TARGET_DIR = path.join(__dirname, '../Sources/ContentScopeScripts/Resources');

function copyRecursive(src, dest) {
    if (!fs.existsSync(src)) {
        console.error(`Source directory does not exist: ${src}`);
        process.exit(1);
    }

    // Create destination directory
    if (!fs.existsSync(dest)) {
        fs.mkdirSync(dest, { recursive: true });
    }

    const entries = fs.readdirSync(src, { withFileTypes: true });

    for (const entry of entries) {
        const srcPath = path.join(src, entry.name);
        const destPath = path.join(dest, entry.name);

        if (entry.isDirectory()) {
            copyRecursive(srcPath, destPath);
        } else {
            fs.copyFileSync(srcPath, destPath);
        }
    }
}

function main() {
    console.log('Copying content-scope-scripts...');
    console.log(`From: ${SOURCE_DIR}`);
    console.log(`To: ${TARGET_DIR}`);

    // Clean target directory first
    if (fs.existsSync(TARGET_DIR)) {
        fs.rmSync(TARGET_DIR, { recursive: true, force: true });
    }

    // Copy files
    copyRecursive(SOURCE_DIR, TARGET_DIR);

    console.log('✅ Content-scope-scripts copied successfully!');
    
    // List what was copied
    const files = fs.readdirSync(TARGET_DIR);
    console.log('Copied files/directories:', files);
}

if (require.main === module) {
    main();
} 