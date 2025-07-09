import * as esbuild from 'esbuild';
import { join, relative } from 'node:path';
import { spawn } from 'node:child_process';
import { rmSync, writeFileSync, mkdirSync } from 'node:fs';
import { watch } from 'chokidar';
import { baseEsbuildOptions } from './opts.mjs';
import { parseArgs, cwd } from '../scripts/script-utils.js';

const args = parseArgs(process.argv.slice(2), ['page']);
const CWD = cwd(import.meta.url);

const publicDir = join(CWD, 'pages', args.page, 'public');
const dist = join(publicDir, 'dist');
const timestamp = join(CWD, 'timestamp.json');
const timestampDist = join(dist, 'timestamp.json');

// start wirth clean folders
rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });

// run types+translations outside of esbuild
runNodeScript('translations.mjs');
runNodeScript('types.mjs');

// record the start
writeTimestamp();

// setup esbuild in serve+watch mode
{
    /** @type {import('esbuild').BuildOptions} */
    const opts = baseEsbuildOptions(args.page, 'integration', 'development');
    opts.dropLabels = [];
    opts.plugins ??= [];
    opts.plugins.push({
        name: 'verbose-logging',
        setup(build) {
            if (args.v) {
                let last = Date.now();
                build.onStart(() => {
                    last = Date.now();
                    console.log('🛠️ + started');
                });
                build.onEnd(() => {
                    console.log('🛠️ - finished', Date.now() - last, 'ms');
                });
            }
        },
    });

    const ctx = await esbuild.context(opts);
    const { hosts, port } = await ctx.serve({
        servedir: publicDir,
    });
    await ctx.watch({});
    for (const host of hosts) {
        console.log(`serving '${relative(CWD, publicDir)}' at http://${host}:${port}`);
    }
}

// also watch things outside of esbuild, like translations/types
watchNode('translations.mjs', `pages/${args.page}`, (_event, path) => path.endsWith('strings.json'));
watchNode('types.mjs', `pages/${args.page}/messages`, (_event, path) => path.endsWith('.json'));

// prevent overlapping jobs
const jobs = new Map();

function watchNode(named, pathToWatch, predicate) {
    console.log(`will run ${named} following changes in ${pathToWatch}`);
    watch(pathToWatch, { ignoreInitial: true }).on('all', (event, path) => {
        if (!predicate(event, path)) return;
        if (jobs.has(named)) clearTimeout(jobs.get(named));
        jobs.set(
            named,
            setTimeout(() => {
                runNodeScript(named, event, path);
            }, 100),
        );
    });
}

/**
 * @param {string} named
 * @param {string|null} [event]
 * @param {string|null} [path]
 */
function runNodeScript(named, event = null, path = null) {
    const chunks = [];
    const errChunks = [];
    const f = spawn('node', [named], { stdio: 'pipe' });
    f.stdout?.on('data', (c) => chunks.push(c.toString()));
    f.stderr?.on('data', (c) => errChunks.push(c.toString()));

    function done(code) {
        if (code === 0) {
            if (args.v) {
                console.log(` - done: ${named}`);
            }
            writeTimestamp({});
        } else {
            writeTimestamp({
                didError: named,
                stdout: chunks.join(''),
                stderr: errChunks.join(''),
                event,
                path,
            });
            console.log(chunks.join(''));
            console.error(errChunks.join(''));
        }
    }

    f.on('close', done);
    f.on('disconnect', () => {
        console.log(`${named} disconnect`);
    });
    f.on('spawn', () => {
        if (args.v) {
            console.log(`+ start ${named}`);
        }
    });
    f.on('message', () => {
        console.log(`${named} message`);
    });
    f.on('error', () => {
        console.log(`${named} error`);
    });
}

function writeTimestamp(fields = {}) {
    writeFileSync(timestamp, JSON.stringify({ now: Date.now(), ...fields }));
    writeFileSync(timestampDist, JSON.stringify({ now: Date.now(), ...fields }));
}
