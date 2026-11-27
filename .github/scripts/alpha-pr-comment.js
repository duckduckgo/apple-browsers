const platforms = {
    ios: {
        name: 'iOS',
        directory: 'iOS',
        workflow: 'ios_alpha.yml',
        uploadJobs: ['Upload to TestFlight'],
        availability: 'in TestFlight',
    },
    macos: {
        name: 'macOS',
        directory: 'macOS',
        workflow: 'macos_alpha_release.yml',
        uploadJobs: ['Publish Alpha DMG', 'Upload App Store Connect Release'],
        availability: 'through alpha updates and in TestFlight',
    },
};

module.exports = async function commentOnAlphaPRs({ github, context, core, version, platform }) {
    const config = platforms[platform];
    if (!config) throw new Error(`Unsupported alpha platform: ${platform}`);
    const marker = `<!-- ${platform}-alpha-version -->`;
    const repo = context.repo;
    let previousRun;
    for await (const { data } of github.paginate.iterator(github.rest.actions.listWorkflowRuns, {
        ...repo,
        workflow_id: config.workflow,
        branch: 'main',
        status: 'completed',
        per_page: 100,
    })) {
        for (const run of data.filter(run => run.id < context.runId)) {
            const jobs = await github.paginate(github.rest.actions.listJobsForWorkflowRun, {
                ...repo,
                run_id: run.id,
                per_page: 100,
            });
            if (config.uploadJobs.every(name => jobs.some(job =>
                (job.name === name || job.name.endsWith(` / ${name}`)) && job.conclusion === 'success'))) {
                previousRun = run;
                break;
            }
        }
        if (previousRun) break;
    }

    const commits = previousRun
        ? await github.paginate(github.rest.repos.compareCommitsWithBasehead, {
            ...repo,
            basehead: `${previousRun.head_sha}...${context.sha}`,
            per_page: 100,
        }, response => response.data.commits)
        : [{ sha: context.sha }];
    const commitSHAs = new Set(commits.map(commit => commit.sha));
    const pullRequests = new Map();

    for (const commit_sha of commitSHAs) {
        const associatedPRs = await github.paginate(github.rest.repos.listPullRequestsAssociatedWithCommit, {
            ...repo,
            commit_sha,
            per_page: 100,
        });
        for (const pr of associatedPRs) {
            if (pr.merged_at && pr.base.ref === 'main' && commitSHAs.has(pr.merge_commit_sha)) {
                pullRequests.set(pr.number, pr);
            }
        }
    }

    const runURL = `${context.serverUrl}/${repo.owner}/${repo.repo}/actions/runs/${context.runId}`;
    const body = `${marker}\nThis PR is included in the ${config.name} alpha targeting **${version}**.\n\n`
        + `It will be available ${config.availability} once the [alpha build and upload](${runURL}) succeed.`;

    for (const pull_number of pullRequests.keys()) {
        try {
            const files = await github.paginate(github.rest.pulls.listFiles, {
                ...repo,
                pull_number,
                per_page: 100,
            });
            if (!files.some(file => [file.filename, file.previous_filename]
                .some(path => path && [config.directory, 'SharedPackages'].some(directory => path.startsWith(`${directory}/`))))) continue;

            const comments = await github.paginate(github.rest.issues.listComments, {
                ...repo,
                issue_number: pull_number,
                per_page: 100,
            });
            const existing = comments.find(comment => comment.user.type === 'Bot' && comment.body?.startsWith(marker));
            if (existing) {
                await github.rest.issues.updateComment({ ...repo, comment_id: existing.id, body });
            } else {
                await github.rest.issues.createComment({ ...repo, issue_number: pull_number, body });
            }
        } catch (error) {
            core.warning(`Could not comment on PR #${pull_number}: ${error.message}`);
        }
    }
};
