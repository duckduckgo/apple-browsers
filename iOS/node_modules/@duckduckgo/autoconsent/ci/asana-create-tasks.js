/* eslint-disable camelcase */
const timersPromises = require('node:timers/promises');
const Asana = require('asana');
const MarkdownIt = require('markdown-it');
const { getLink } = require('./release-utils.js');
const md = new MarkdownIt();

const ASANA_ACCESS_TOKEN = process.env.ASANA_ACCESS_TOKEN;
const version = process.env.TAG;
const releaseUrl = process.env.RELEASE_URL || 'https://example.com/';
const releaseNotesRaw = process.env.RELEASE_NOTES || '<EMPTY RELEASE NOTES>';
const releaseNotes = md.render(releaseNotesRaw);

const templateTaskGid = '1206774921409831';
const autoconsentProjectGid = '1201844467387842';
const releaseSectionGid = '1202253736774466';
const scheduledForReleaseSectionGid = '1207140808076253';
const projectExtractorRegex = /\[\[project_gids=(.*)]]/;

/**
 * @typedef {{taskGid: string, taskUrl: string, displayName: string}} platformData
 *
 * @typedef {{
 *   android: platformData,
 *   windows: platformData,
 *   apple: platformData
 * }} AsanaOutput
 */

/** @type {AsanaOutput} */
const platforms = {
    android: {
        displayName: 'Android',
        taskGid: '',
        taskUrl: '',
    },
    windows: {
        displayName: 'Windows',
        taskGid: '',
        taskUrl: '',
    },
    apple: {
        displayName: 'Apple',
        taskGid: '',
        taskUrl: '',
    },
};

let asana;

const setupAsana = () => {
    asana = Asana.Client.create({
        defaultHeaders: {
            'Asana-Enable': 'new_project_templates,new_user_task_lists,new_goal_memberships',
        },
    }).useAccessToken(ASANA_ACCESS_TOKEN);
};

const duplicateTemplateTask = (templateTaskGid) => {
    const duplicateOption = {
        include: ['notes', 'assignee', 'subtasks', 'projects'],
        name: `Autoconsent release ${version}`,
        opt_fields: 'html_notes',
    };

    return asana.tasks.duplicateTask(templateTaskGid, duplicateOption);
};

const waitForJobSuccess = async (job_gid) => {
    const interval = 1000;
    const maxAttempts = 20;

    // eslint-disable-next-line no-async-promise-executor -- legacy code
    return new Promise(async (resolve, reject) => {
        const innerFn = async function (job_gid, attempts) {
            console.error(`Waiting for job ${job_gid} to complete...`);
            const { status } = await asana.jobs.getJob(job_gid);
            console.error(`Job ${job_gid} status: ${status}`);
            if (status === 'succeeded') {
                return resolve(status);
            }
            attempts += 1;

            if (attempts > maxAttempts) {
                const errMsg = `The job ${job_gid} took too long to execute`;
                console.error(errMsg);
                return reject(new Error(errMsg));
            }

            console.error(`Retrying in ${interval}ms...`);
            await timersPromises.setTimeout(interval);
            console.error(`Attempt ${attempts}`);
            return await innerFn(job_gid, attempts);
        };
        return await innerFn(job_gid, 1);
    });
};

/**
 * Generates an HTML summary of the tasks in the "Scheduled for Release"
 * section, then marks those tasks as completed.
 *
 * @returns {Promise<string>}
 */
const processReleaseTasks = async () => {
    const { data: tasks } = await asana.tasks.getTasksForSection(scheduledForReleaseSectionGid, {
        opt_fields: 'name,permalink_url,completed',
        completed_since: 'now', // Fetch only incomplete tasks
    });

    if (!tasks || tasks.length === 0) {
        return '';
    }

    let taskListHtml = '<strong>Tasks included in this release:</strong>\n<ul>\n';
    for (const task of tasks) {
        taskListHtml += '<li>' + getLink(task.permalink_url) + '</li>\n';
        await asana.tasks.updateTask(task.gid, { completed: true });
    }
    taskListHtml += '</ul>';

    return taskListHtml;
};

const asanaCreateTasks = async () => {
    setupAsana();

    // Duplicating template task...
    const { new_task, gid: duplicateTaskJobGid } = await duplicateTemplateTask(templateTaskGid);

    const { html_notes: notes } = await asana.tasks.getTask(new_task.gid, { opt_fields: 'html_notes' });

    const updatedNotes = notes
        .replace('[[version]]', version)
        .replace('[[release_url]]', getLink(releaseUrl, 'Autoconsent Release'))
        .replace('[[notes]]', [await processReleaseTasks(), releaseNotes].filter(Boolean).join('\n\n'))
        .replace(/<\/?p>/gi, '\n')
        // Asana supports only h1 and h2
        .replace(/<(h3|h4)>/gi, '<h2>')
        .replace(/<\/(h3|h4)>/gi, '</h2>');

    // Updating task and moving to Release section...
    console.error('Updated notes:', JSON.stringify(updatedNotes));

    // set due date 6 days from now
    const dueDate = new Date();
    dueDate.setDate(dueDate.getDate() + 6);
    const dueDateString = dueDate.toISOString().split('T')[0];

    let updateTaskResult = await asana.tasks.updateTask(new_task.gid, { html_notes: updatedNotes, due_on: dueDateString });
    console.error('updateTaskResult:', updateTaskResult);

    const addProjectResult = await asana.tasks.addProjectForTask(new_task.gid, {
        project: autoconsentProjectGid,
        section: releaseSectionGid,
    });
    console.error('addProjectResult:', addProjectResult);

    // The duplicateTask job returns when the task itself has been duplicated, ignoring the subtasks.
    // We want to wait that the job completes so that we can fetch all the subtasks correctly.
    const duplicateTaskResult = await waitForJobSuccess(duplicateTaskJobGid);
    console.error('duplicateTaskResult:', duplicateTaskResult);

    // Getting subtasks...
    const { data: subtasks } = await asana.tasks.getSubtasksForTask(new_task.gid, { opt_fields: 'name,html_notes,permalink_url' });
    console.error('subtasks:', subtasks);

    // Updating subtasks and moving to appropriate projects...
    for (const subtask of subtasks) {
        const { gid, name, html_notes, permalink_url } = subtask;

        const platform = Object.keys(platforms).find((key) => name.includes(platforms[key].displayName));
        if (!platform) throw new Error('Unexpected platform name: ' + name);

        platforms[platform].taskGid = gid;
        platforms[platform].taskUrl = permalink_url;

        const newName = name.replace('[[version]]', version);
        const extractedProjects = html_notes.match(projectExtractorRegex)?.[1];

        const subtaskNotes = html_notes.replace(projectExtractorRegex, '').replace('[[notes]]', updatedNotes);

        console.error(`updating task ${gid} with name ${newName} and notes ${subtaskNotes}`);
        await asana.tasks.updateTask(gid, { name: newName, html_notes: subtaskNotes });

        if (extractedProjects) {
            console.error(`adding projects ${extractedProjects} to task ${gid}`);
            for (const projectGidAndSection of extractedProjects.split(',')) {
                const [projectGid, sectionGid] = projectGidAndSection.split(':');
                await asana.tasks.addProjectForTask(gid, { project: projectGid, section: sectionGid });
            }
        }
    }

    const finalNotes = updatedNotes.replace('<li>[[pr_url]]</li>', version).replace('<li>[[extra_content]]</li>', version);

    console.error('finalNotes:', finalNotes);
    updateTaskResult = await asana.tasks.updateTask(new_task.gid, { html_notes: finalNotes });
    console.error('updateTaskResult:', updateTaskResult);

    const jsonString = JSON.stringify(platforms);
    return { stdout: jsonString };
};

asanaCreateTasks()
    .then((result) => {
        // this log is for visibility in Github web interface
        console.error('stage result:', result.stdout);
        // The log is needed to read the value from the bash context
        console.log(result.stdout);
    })
    .catch((e) => {
        console.error('Failed to create asana tasks:');
        // The Asana API returns errors in e.value.errors. If that's undefined log whatever else we got
        console.error(e.value?.errors || e);
        process.exit(1);
    });

module.exports = { asanaCreateTasks };
