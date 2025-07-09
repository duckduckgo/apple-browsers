const Asana = require('asana');
const { replaceAllInString, getLink } = require('./release-utils.js');

const ASANA_ACCESS_TOKEN = process.env.ASANA_ACCESS_TOKEN;
const prUrls = {
    android: process.env.ANDROID_PR_URL,
    apple: process.env.APPLE_PR_URL,
    windows: process.env.WINDOWS_PR_URL,
};
const asanaOutputRaw = process.env.ASANA_OUTPUT;

let asana;

const setupAsana = () => {
    asana = Asana.Client.create({
        defaultHeaders: {
            'Asana-Enable': 'new_project_templates,new_user_task_lists,new_goal_memberships',
        },
    }).useAccessToken(ASANA_ACCESS_TOKEN);
};

const asanaUpdateTasks = async () => {
    let asanaOutput;
    try {
        asanaOutput = JSON.parse(asanaOutputRaw || '');
    } catch (e) {
        throw new Error(`Unable to parse Asana output JSON: ${asanaOutputRaw}`);
    }

    setupAsana();

    const platformEntries = Object.entries(asanaOutput);
    for (const [platformName, platformObj] of platformEntries) {
        // If we're missing required data, either we haven't implemented automation for that platform yet,
        // or something went wrong in a previous job
        if (!platformObj.taskGid || !prUrls[platformName]) {
            console.error(`Skipping ${platformName} task update`);
            continue;
        }

        const { html_notes: notes } = await asana.tasks.getTask(platformObj.taskGid, { opt_fields: 'html_notes' });

        const prLink = getLink(prUrls[platformName], `${platformObj.displayName} PR`);
        /** @type {[[RegExp, string]]} */
        const taskDescriptionSubstitutions = [[/\[\[pr_url]]/, prLink]];

        const updatedNotes = replaceAllInString(notes, taskDescriptionSubstitutions);

        await asana.tasks.updateTask(platformObj.taskGid, { html_notes: updatedNotes });
    }
};

asanaUpdateTasks().catch((e) => {
    // The Asana API returns errors in e.value.errors. If that's undefined log whatever else we got
    console.error(e.value?.errors || e);
    process.exit(1);
});
