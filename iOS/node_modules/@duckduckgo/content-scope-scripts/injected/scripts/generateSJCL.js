import { readFile, writeFile } from 'fs/promises';
import { existsSync } from 'fs';
import util from 'util';
import { exec as callbackExec } from 'child_process';
const exec = util.promisify(callbackExec);

async function init() {
    if (!existsSync('node_modules/sjcl/')) {
        // If content scope scripts is installed as a module there is no need to copy sjcl
        return;
    }

    if (process.platform === 'win32') {
        console.log('skipping sjcl on windows');
        return;
    }

    await exec('cd node_modules/sjcl/ && perl ./configure --no-export --compress=none --without-all --with-hmac --with-codecHex && make');
    const sjclFileContents = await readFile('node_modules/sjcl/sjcl.js');
    // Reexport the file as es6 module format
    const contents = `// @ts-nocheck
    export const sjcl = (() => {
    ${sjclFileContents}
    return sjcl;
  })()`;
    writeFile('lib/sjcl.js', contents);
}

init();
