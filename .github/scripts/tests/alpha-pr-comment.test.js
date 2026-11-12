const assert = require('node:assert/strict');
const { test } = require('node:test');
const commentOnAlphaPRs = require('../alpha-pr-comment.js');

function fixture({ runs = [], jobs = {}, commits = ['head'], prs = {}, files = {}, comments = {}, failPR } = {}) {
    const calls = [];
    const warnings = [];
    const rest = Object.fromEntries(Object.entries({
        actions: ['listWorkflowRuns', 'listJobsForWorkflowRun'],
        repos: ['compareCommitsWithBasehead', 'listPullRequestsAssociatedWithCommit'],
        pulls: ['listFiles'],
        issues: ['listComments', 'createComment', 'updateComment'],
    }).map(([group, names]) => [group, Object.fromEntries(names.map(name => [name, async params => {
        calls.push({ name, ...params });
        if (params.issue_number === failPR) throw new Error('Comments unavailable');
    }]))]));
    const paginate = async (method, params, map) => {
        calls.push({ name: Object.values(rest).flatMap(Object.entries).find(([, fn]) => fn === method)[0], ...params });
        if (method === rest.actions.listJobsForWorkflowRun) return jobs[params.run_id] || [];
        if (method === rest.repos.compareCommitsWithBasehead) {
            return map({ data: { commits: commits.map(sha => ({ sha })) } });
        }
        if (method === rest.repos.listPullRequestsAssociatedWithCommit) return prs[params.commit_sha] || [];
        if (method === rest.pulls.listFiles) return files[params.pull_number] || [{ filename: 'iOS/App.swift' }];
        if (method === rest.issues.listComments) return comments[params.issue_number] || [];
        throw new Error('Unexpected API call');
    };
    paginate.iterator = async function* (method, params) {
        calls.push({ name: 'listWorkflowRuns', ...params });
        for (const data of runs) yield { data };
    };
    return {
        calls,
        warnings,
        options: {
            github: { rest, paginate },
            context: { repo: { owner: 'duckduckgo', repo: 'apple-browsers' }, sha: 'head', runId: 100, serverUrl: 'https://github.com' },
            core: { warning: message => warnings.push(message) },
            version: '7.244.0-23',
            platform: 'ios',
        },
    };
}

function pr(number, merge_commit_sha = 'head', overrides = {}) {
    return { number, merge_commit_sha, merged_at: '2026-11-12', base: { ref: 'main' }, ...overrides };
}

test('posts the target version and build link for the merged PR on the first run', async () => {
    const { options, calls } = fixture({ prs: { head: [pr(1)] } });
    await commentOnAlphaPRs(options);
    const comments = calls.filter(call => call.name === 'createComment');
    assert.equal(comments.length, 1);
    assert.equal(comments[0].issue_number, 1);
    assert.match(comments[0].body, /\*\*7\.244\.0-23\*\*/);
    assert.match(comments[0].body, /https:\/\/github.com\/duckduckgo\/apple-browsers\/actions\/runs\/100/);
    assert.match(comments[0].body, /once.*succeed/);
});

test('catches up cancelled and skipped builds using the last successful upload, across pages', async () => {
    const { options, calls } = fixture({
        runs: [[{ id: 110 }, { id: 99 }], [{ id: 98, head_sha: 'uploaded' }]],
        jobs: { 99: [{ name: 'Upload to TestFlight', conclusion: 'skipped' }], 98: [{ name: 'Upload to TestFlight', conclusion: 'success' }] },
        commits: ['earlier', 'head'],
        prs: { earlier: [pr(1, 'earlier')], head: [pr(1, 'earlier'), pr(2)] },
    });
    await commentOnAlphaPRs(options);
    assert.equal(calls.find(call => call.name === 'compareCommitsWithBasehead').basehead, 'uploaded...head');
    assert.deepEqual(calls.filter(call => call.name === 'createComment').map(call => call.issue_number), [1, 2]);
    assert.ok(!calls.some(call => call.run_id === 110));
});

test('ignores open PRs, other branches, unrelated merge commits and macOS-only changes', async () => {
    const { options, calls } = fixture({
        prs: { head: [pr(1, 'head', { merged_at: null }), pr(2, 'head', { base: { ref: 'release' } }), pr(3, 'other'), pr(4), pr(5)] },
        files: { 4: [{ filename: 'macOS/App.swift' }], 5: [{ filename: 'SharedPackages/Feature.swift' }] },
    });
    await commentOnAlphaPRs(options);
    assert.deepEqual(calls.filter(call => call.name === 'createComment').map(call => call.issue_number), [5]);
});

test('includes a PR moving a file out of iOS', async () => {
    const { options, calls } = fixture({
        prs: { head: [pr(1)] },
        files: { 1: [{ filename: 'macOS/Moved.swift', previous_filename: 'iOS/Moved.swift' }] },
    });
    await commentOnAlphaPRs(options);
    assert.equal(calls.filter(call => call.name === 'createComment').length, 1);
});

test('updates the existing bot comment while leaving user comments alone', async () => {
    const { options, calls } = fixture({
        prs: { head: [pr(1)] },
        comments: { 1: [
            { id: 10, user: { type: 'User' }, body: '<!-- ios-alpha-version -->' },
            { id: 11, user: { type: 'Bot' }, body: '<!-- ios-alpha-version -->\nOld target' },
        ] },
    });
    await commentOnAlphaPRs(options);
    assert.equal(calls.find(call => call.name === 'updateComment').comment_id, 11);
    assert.ok(!calls.some(call => call.name === 'createComment'));
});

test('a comment failure does not prevent notifying other PRs', async () => {
    const { options, calls, warnings } = fixture({
        prs: { head: [pr(1), pr(2)] },
        failPR: 1,
    });
    await commentOnAlphaPRs(options);
    assert.match(warnings[0], /PR #1/);
    assert.ok(calls.some(call => call.name === 'createComment' && call.issue_number === 2));
});

test('does not change comments when rerunning an already uploaded commit', async () => {
    const { options, calls } = fixture({
        runs: [[{ id: 90, head_sha: 'head' }]],
        jobs: { 90: [{ name: 'Upload to TestFlight', conclusion: 'success' }] },
        commits: [],
    });
    await commentOnAlphaPRs(options);
    assert.ok(!calls.some(call => ['createComment', 'updateComment'].includes(call.name)));
});

test('macOS comments include its alpha version and both distribution channels, excluding iOS-only PRs', async () => {
    const { options, calls } = fixture({
        prs: { head: [pr(1), pr(2), pr(3)] },
        files: {
            1: [{ filename: 'iOS/App.swift' }],
            2: [{ filename: 'macOS/App.swift' }],
            3: [{ filename: 'SharedPackages/Feature.swift' }],
        },
    });
    await commentOnAlphaPRs({ ...options, platform: 'macos', version: '9999.9.9-123' });
    const comments = calls.filter(call => call.name === 'createComment');
    assert.deepEqual(comments.map(call => call.issue_number), [2, 3]);
    assert.match(comments[0].body, /^<!-- macos-alpha-version -->\nThis PR is included in the macOS alpha/);
    assert.match(comments[0].body, /\*\*9999\.9\.9-123\*\*/);
    assert.match(comments[0].body, /through alpha updates and in TestFlight/);
    assert.equal(calls.find(call => call.name === 'listWorkflowRuns').workflow_id, 'macos_alpha_release.yml');
});

test('shared PRs get separate iOS and macOS comments, and macOS reruns only update macOS', async () => {
    const comments = { 1: [] };
    const { options, calls } = fixture({
        prs: { head: [pr(1)] },
        files: { 1: [{ filename: 'SharedPackages/Feature.swift' }] },
        comments,
    });
    await commentOnAlphaPRs(options);
    comments[1].push({ id: 10, user: { type: 'Bot' }, body: calls.find(call => call.name === 'createComment').body });

    await commentOnAlphaPRs({ ...options, platform: 'macos', version: '9999.9.9-123' });
    const created = calls.filter(call => call.name === 'createComment');
    assert.equal(created.length, 2);
    assert.match(created[1].body, /^<!-- macos-alpha-version -->/);
    comments[1].push({ id: 11, user: { type: 'Bot' }, body: created[1].body });

    await commentOnAlphaPRs({ ...options, platform: 'macos', version: '9999.9.9-124' });
    const updated = calls.filter(call => call.name === 'updateComment');
    assert.equal(updated.length, 1);
    assert.equal(updated[0].comment_id, 11);
    assert.match(updated[0].body, /9999\.9\.9-124/);
});

test('macOS catches up partially published builds using the last run with both uploads successful', async () => {
    const { options, calls } = fixture({
        runs: [[{ id: 99 }, { id: 98 }, { id: 97, head_sha: 'published' }]],
        jobs: {
            99: [
                { name: 'Publish Alpha DMG', conclusion: 'success' },
                { name: 'Prepare AppStore Release / Upload App Store Connect Release', conclusion: 'cancelled' },
            ],
            98: [
                { name: 'Publish Alpha DMG', conclusion: 'failure' },
                { name: 'Prepare AppStore Release / Upload App Store Connect Release', conclusion: 'success' },
            ],
            97: [
                { name: 'Publish Alpha DMG', conclusion: 'success' },
                { name: 'Prepare AppStore Release / Upload App Store Connect Release', conclusion: 'success' },
            ],
        },
        commits: ['earlier', 'head'],
        prs: { earlier: [pr(1, 'earlier')], head: [pr(2)] },
        files: { 1: [{ filename: 'macOS/App.swift' }], 2: [{ filename: 'macOS/Feature.swift' }] },
    });
    await commentOnAlphaPRs({ ...options, platform: 'macos', version: '9999.9.9-123' });
    assert.equal(calls.find(call => call.name === 'compareCommitsWithBasehead').basehead, 'published...head');
    assert.deepEqual(calls.filter(call => call.name === 'createComment').map(call => call.issue_number), [1, 2]);
});

test('macOS includes a PR moving a file out of macOS', async () => {
    const { options, calls } = fixture({
        prs: { head: [pr(1)] },
        files: { 1: [{ filename: 'iOS/Moved.swift', previous_filename: 'macOS/Moved.swift' }] },
    });
    await commentOnAlphaPRs({ ...options, platform: 'macos', version: '9999.9.9-123' });
    assert.equal(calls.filter(call => call.name === 'createComment').length, 1);
});
