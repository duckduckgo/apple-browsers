const glob = require('glob');
const fs = require('fs');
const path = require('path');
const { exit } = require('process');
const Ajv = require('ajv').default;
const ajv = new Ajv();
const checkTrackerRadar = require('./helpers/tracker-radar-checks');

const FOLDER_FORMAT = /^([a-z]+\-)*[a-z]+$/;
const TEST_FILE_SCHEMA = JSON.parse(fs.readFileSync('./schemas/tests.json'))
const testValidate = ajv.compile(TEST_FILE_SCHEMA);
const SKIP_FOLDERS = ['_scripts'];
const IGNORE_FOLDER_FORMAT = ['_template-new-feature'];
const SKIP_TEST_FILES = ['tracker_allowlist_matching_tests.json']; // doesn't follow the format, skip

const root = path.resolve(__dirname, '../');
const dirs = glob.sync("/*/", { root });
let featuresCount = 0;
let testsCount = 0;

dirs.forEach(dir => {
    const featureFolderName = path.basename(dir);

    if (SKIP_FOLDERS.includes(featureFolderName)) {
        return;
    }

    if (!IGNORE_FOLDER_FORMAT.includes(featureFolderName) && !FOLDER_FORMAT.test(featureFolderName)) {
        console.error(`❌ ${featureFolderName} doesn't follow the folder naming format`);
        exit(1);
    }

    console.log('Processing feature directory:', featureFolderName);

    featuresCount++;

    const testFiles = glob.sync("/**/?(*_)tests.json", { root: path.resolve(root, featureFolderName) });

    if (testFiles.length === 0) {
        console.error(`❌ tests file missing in the feature folder ${featureFolderName}`);
        exit(1);
    }

    testFiles.forEach(testFile => {
        const testBasename = path.basename(testFile);

        if (SKIP_TEST_FILES.includes(testBasename)) {
            console.log(` - ⚠️ skipping ${testBasename}`)
            return;
        }

        console.log(` - validating ${testBasename}`);

        const testFileObject = JSON.parse(fs.readFileSync(testFile));

        if (!testValidate(testFileObject)) {
            console.error(` ❌ ${testFile} doesn't follow the expected format:`);
            console.error(testValidate.errors.map(item => `  - ${item.instancePath}: ${item.message}`).join('\n'));
            exit(1);
        }

        Object.keys(testFileObject).forEach(set => testsCount += testFileObject[set].tests.length);
    });

    const trackerRadarFiles = glob.sync("/**/tracker_radar*.json", { root: path.resolve(root, featureFolderName) });;

    trackerRadarFiles.forEach(testFile => {
        const testBasename = path.basename(testFile);

        console.log(` - validating ${testBasename}`);

        const trackerRadarObject = JSON.parse(fs.readFileSync(testFile));

        const errors = checkTrackerRadar(trackerRadarObject);

        if (errors.length) {
            console.error(` ❌ ${testFile} is not a valid Tracker Radar blocklist:`);
            console.error(errors.map(item => `  - ${item.location}: ${item.message}`).join('\n'));
            exit(1);
        }
    })

});

console.log(`
Number of features: ${featuresCount}
Number of tests: ${testsCount}
All good ✅`);