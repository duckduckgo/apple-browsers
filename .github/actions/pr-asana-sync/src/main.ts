import asana, {Client} from 'asana'
import {info, setFailed, getInput, debug, setOutput} from '@actions/core'
import {context, getOctokit} from '@actions/github'
import {
  PullRequest,
  PullRequestEvent,
  PullRequestReviewEvent,
  User
} from '@octokit/webhooks-types'

import {renderMD} from './markdown'
import {getDueOn} from './helper'

const CUSTOM_FIELD_NAMES = {
  url: 'Github URL',
  status: 'Github Status'
}

const USER_MAP: {[key: string]: string} = JSON.parse(
  getInput('USER_MAP', {required: false}) || '{}'
)

type PRState = 'Open' | 'Closed' | 'Merged' | 'Approved' | 'Draft'

type PRFields = {
  url: asana.resources.CustomField
  status: asana.resources.CustomField
}

// Extended event types for review request actions
type ReviewRequestedEvent = PullRequestEvent & {
  action: 'review_requested'
  requested_reviewer?: User
}

type ReviewRequestRemovedEvent = PullRequestEvent & {
  action: 'review_request_removed'
  requested_reviewer?: User
}

const client = Client.create({
  defaultHeaders: {
    'asana-enable':
      'new_user_task_lists,new_project_templates,new_goal_memberships'
  }
}).useAccessToken(getInput('ASANA_ACCESS_TOKEN', {required: true}))

const ASANA_WORKSPACE_ID = getInput('ASANA_WORKSPACE_ID', {required: true})
const PROJECT_ID = getInput('ASANA_PROJECT_ID', {required: true})
// Users which will not receive PRs/reviews tasks
const RANDOMIZED_REVIEWERS = getInput('RANDOMIZED_REVIEWERS')
const RANDOMIZED_REVIEWERS_LIST = RANDOMIZED_REVIEWERS.split(',')

function getUserIdFromLogin(login: string): string | undefined {
  const userId = USER_MAP[login]
  return userId
}

function getApprovalStatus(
  prState: PRState,
  author: string
):
  | 'pending'
  | 'commented'
  | 'changes_requested'
  | 'approved'
  | 'rejected'
  | undefined {
  if (context.eventName === 'pull_request_review') {
    switch (prState) {
      case 'Approved':
      case 'Merged':
        return 'approved'
      case 'Closed':
        return 'rejected'
    }

    const reviewPayload = context.payload as PullRequestReviewEvent
    if (reviewPayload.action === 'submitted') {
      if (
        reviewPayload.review.state === 'approved' ||
        reviewPayload.review.state === 'changes_requested' ||
        (reviewPayload.review.state === 'commented' &&
          reviewPayload.review.user.login !== author)
      ) {
        return reviewPayload.review.state
      }
    } else if (reviewPayload.review.state === 'dismissed') {
      return 'pending'
    }
  }

  return undefined
}

/**
 * Find a PR task assigned to a specific reviewer
 */
async function findPRTaskForReviewer(
  customFields: PRFields,
  prURL: string,
  reviewerAsanaId: string
): Promise<asana.resources.Tasks.Type | null> {
  // Search for tasks with the PR URL, then filter by assignee locally
  // (Asana's assignee.any filter may not work reliably with searchInWorkspace)
  try {
    const prTasks = await client.tasks.searchInWorkspace(ASANA_WORKSPACE_ID, {
      [`custom_fields.${customFields.url.gid}.value`]: prURL,
      // eslint-disable-next-line camelcase
      opt_fields: 'name,parent,completed,assignee'
    })

    // Filter locally by assignee to ensure we get the right task
    const matchingTask = prTasks.data.find(
      (task: asana.resources.Tasks.Type) =>
        task.assignee?.gid === reviewerAsanaId
    )

    if (matchingTask) {
      info(
        `Found PR task for reviewer ${reviewerAsanaId} using searchInWorkspace: ${matchingTask.gid}`
      )
      return matchingTask
    }
  } catch (e) {
    info(`searchInWorkspace failed: ${e}`)
  }

  // Fallback to searching recent project tasks
  const projectTasks = await client.tasks.findByProject(PROJECT_ID, {
    // eslint-disable-next-line camelcase
    opt_fields: 'custom_fields,assignee,completed',
    limit: 100
  })

  for (const task of projectTasks.data) {
    // Must match the specific reviewer
    if (task.assignee?.gid !== reviewerAsanaId) continue

    for (const field of task.custom_fields) {
      if (
        field.gid === customFields.url.gid &&
        field.display_value === prURL
      ) {
        info(
          `Found existing task ID ${task.gid} for PR ${prURL} and reviewer ${reviewerAsanaId}`
        )
        return task
      }
    }
  }

  info(
    `No matching Asana task found for PR ${prURL} and reviewer ${reviewerAsanaId}`
  )
  return null
}

/**
 * Find all PR tasks for a given PR URL (any reviewer)
 */
async function findAllPRTasks(
  customFields: PRFields,
  prURL: string
): Promise<asana.resources.Tasks.Type[]> {
  const tasks: asana.resources.Tasks.Type[] = []

  try {
    const prTasks = await client.tasks.searchInWorkspace(ASANA_WORKSPACE_ID, {
      [`custom_fields.${customFields.url.gid}.value`]: prURL,
      // eslint-disable-next-line camelcase
      opt_fields: 'name,parent,completed,assignee'
    })
    tasks.push(...prTasks.data)
  } catch (e) {
    info(`searchInWorkspace failed: ${e}`)
  }

  // Also check recent project tasks for eventual consistency
  if (tasks.length === 0) {
    const projectTasks = await client.tasks.findByProject(PROJECT_ID, {
      // eslint-disable-next-line camelcase
      opt_fields: 'custom_fields,assignee,completed',
      limit: 100
    })

    for (const task of projectTasks.data) {
      for (const field of task.custom_fields) {
        if (
          field.gid === customFields.url.gid &&
          field.display_value === prURL
        ) {
          tasks.push(task)
          break
        }
      }
    }
  }

  info(`Found ${tasks.length} existing tasks for PR ${prURL}`)
  return tasks
}

/**
 * Create a PR review task for a specific reviewer
 */
async function createPRTaskForReviewer(
  parentTaskId: string | null,
  reviewerGithubLogin: string,
  reviewerAsanaId: string,
  prNumber: number,
  prTitle: string,
  prURL: string,
  prStatus: string,
  customFields: PRFields,
  automatedPR: boolean,
  followers: string[] | undefined
): Promise<asana.resources.Tasks.Type> {
  const title = `Code review for PR #${prNumber} (@${reviewerGithubLogin}): ${prTitle}`
  info(`Creating new PR task for reviewer ${reviewerGithubLogin}`)

  const data: asana.resources.Tasks.CreateParams & {workspace: string} = {
    workspace: ASANA_WORKSPACE_ID,
    // eslint-disable-next-line camelcase
    resource_subtype: 'approval',
    // eslint-disable-next-line camelcase
    custom_fields: {
      [customFields.url.gid]: prURL,
      [customFields.status.gid]: prStatus
    },
    name: title,
    projects: [PROJECT_ID],
    assignee: reviewerAsanaId,
    followers
  }

  if (!automatedPR) {
    // eslint-disable-next-line camelcase
    data.due_on = getDueOn(1)
  }

  if (parentTaskId) {
    data.parent = parentTaskId
  }

  return client.tasks.create(data)
}

/**
 * Reopen a closed task
 */
async function reopenTask(
  task: asana.resources.Tasks.Type,
  prStatus: string,
  customFields: PRFields
): Promise<void> {
  info(`Reopening task ${task.gid}`)
  await client.tasks.updateTask(task.gid, {
    completed: false,
    // eslint-disable-next-line camelcase
    approval_status: 'pending',
    // eslint-disable-next-line camelcase
    due_on: getDueOn(1),
    // eslint-disable-next-line camelcase
    custom_fields: {
      [customFields.status.gid]: prStatus
    }
  })
}

/**
 * Close a task (mark as rejected since review request was removed)
 */
async function closeTask(task: asana.resources.Tasks.Type): Promise<void> {
  info(`Closing task ${task.gid}`)
  await client.tasks.updateTask(task.gid, {
    completed: true,
    // eslint-disable-next-line camelcase
    approval_status: 'rejected'
  })
}

function isImportantAutomatedPR(payload: PullRequestEvent): boolean {
  const githubAuthor = payload.pull_request.user.login
  // WebView2 update
  return (
    githubAuthor === 'daxmobile' &&
    payload.pull_request.head.ref.startsWith('webview2/')
  )
}

function getFollowers(
  githubAuthor: string,
  automatedPR: boolean
): string[] | undefined {
  const authorId = getUserIdFromLogin(githubAuthor)
  if (authorId) {
    return [authorId]
  }

  // if it's a PR created by automation add everyone to it
  if (automatedPR) {
    return Object.values(USER_MAP)
  }

  return undefined
}

/**
 * Find the parent task ID from the PR description
 */
async function findParentTaskId(
  body: string
): Promise<{parentTaskId: string | null; openShipReviewTask: asana.resources.Tasks.Type | null}> {
  const asanaTaskMatch = body.match(
    /Task\/Issue URL:.*https:\/\/app.asana.*\/([0-9]+).*/
  )
  let parentTaskId = asanaTaskMatch && asanaTaskMatch[1]
  let openShipReviewTask: asana.resources.Tasks.Type | null = null

  if (parentTaskId) {
    info(`Found Asana task mention with parent ID: ${parentTaskId}`)

    try {
      const subTasks = await client.tasks.subtasks(parentTaskId, {
        // eslint-disable-next-line camelcase
        opt_fields: 'name,completed',
        limit: 100
      })
      openShipReviewTask =
        subTasks.data.find(
          (t: asana.resources.Tasks.Type) =>
            t.name.startsWith('Ship Review') && !t.completed
        ) || null
    } catch (e) {
      info(`Can't access parent task: ${parentTaskId}: ${e}`)
      info(`Add 'dax' user to respective projects to enable this feature`)
      parentTaskId = null
    }
  }

  return {
    parentTaskId,
    openShipReviewTask
  }
}

/**
 * Get or create a task for a specific reviewer
 */
async function getOrCreateTaskForReviewer(
  payload: PullRequestEvent,
  reviewerLogin: string,
  customFields: PRFields,
  prStatus: string,
  parentTaskId: string | null,
  automatedPR: boolean
): Promise<asana.resources.Tasks.Type | null> {
  const prURL = payload.pull_request.html_url
  const reviewerAsanaId = getUserIdFromLogin(reviewerLogin)

  if (!reviewerAsanaId) {
    info(
      `Skipping task creation for reviewer ${reviewerLogin} - not in USER_MAP`
    )
    return null
  }

  // Check if a task already exists for this reviewer
  const existingTask = await findPRTaskForReviewer(
    customFields,
    prURL,
    reviewerAsanaId
  )

  if (existingTask) {
    if (existingTask.completed) {
      // Reopen the existing task
      await reopenTask(existingTask, prStatus, customFields)
      info(`Reopened existing task ${existingTask.gid} for reviewer ${reviewerLogin}`)
    } else {
      info(`Task ${existingTask.gid} already exists and is open for reviewer ${reviewerLogin}`)
    }
    return existingTask
  }

  // Create a new task
  const githubAuthor = payload.pull_request.user.login
  const followers = getFollowers(githubAuthor, automatedPR)

  const task = await createPRTaskForReviewer(
    parentTaskId,
    reviewerLogin,
    reviewerAsanaId,
    payload.pull_request.number,
    payload.pull_request.title,
    prURL,
    prStatus,
    customFields,
    automatedPR,
    followers
  )

  info(`Created new task ${task.gid} for reviewer ${reviewerLogin}`)
  return task
}

/**
 * Handle review_requested action - create or reopen task for the new reviewer
 */
async function handleReviewRequested(
  payload: ReviewRequestedEvent,
  customFields: PRFields,
  prStatus: string
): Promise<asana.resources.Tasks.Type | null> {
  const requestedReviewer = payload.requested_reviewer
  if (!requestedReviewer) {
    info('No requested_reviewer in payload')
    return null
  }

  info(`Handling review request for reviewer: ${requestedReviewer.login}`)

  const githubAuthor = payload.pull_request.user.login
  const automatedPR = isImportantAutomatedPR(payload)
  const authorAsanaId = getUserIdFromLogin(githubAuthor)

  if (!authorAsanaId && !automatedPR) {
    info(
      `Skipping Asana sync for PR created by ${githubAuthor} as they are not in USER_MAP`
    )
    return null
  }

  const body = payload.pull_request.body || ''
  const {parentTaskId} = await findParentTaskId(body)

  const task = await getOrCreateTaskForReviewer(
    payload,
    requestedReviewer.login,
    customFields,
    prStatus,
    parentTaskId,
    automatedPR
  )

  if (task) {
    setOutput('result', 'created_or_reopened')
    setOutput('task_url', task.permalink_url)
  }

  return task
}

/**
 * Handle review_request_removed action - close the task for the removed reviewer
 */
async function handleReviewRequestRemoved(
  payload: ReviewRequestRemovedEvent,
  customFields: PRFields
): Promise<void> {
  const removedReviewer = payload.requested_reviewer
  if (!removedReviewer) {
    info('No requested_reviewer in payload')
    return
  }

  info(`Handling review request removal for reviewer: ${removedReviewer.login}`)

  const reviewerAsanaId = getUserIdFromLogin(removedReviewer.login)
  if (!reviewerAsanaId) {
    info(
      `Skipping task close for reviewer ${removedReviewer.login} - not in USER_MAP`
    )
    return
  }

  const prURL = payload.pull_request.html_url
  const existingTask = await findPRTaskForReviewer(
    customFields,
    prURL,
    reviewerAsanaId
  )

  if (existingTask && !existingTask.completed) {
    await closeTask(existingTask)
    setOutput('result', 'closed')
    setOutput('task_url', existingTask.permalink_url)
    info(`Closed task ${existingTask.gid} for removed reviewer ${removedReviewer.login}`)
  } else if (existingTask) {
    info(`Task ${existingTask.gid} for reviewer ${removedReviewer.login} is already closed`)
  } else {
    info(`No task found for reviewer ${removedReviewer.login}`)
  }
}

/**
 * Handle PR opened - only create tasks if reviewers are already assigned
 * If no reviewers, assign a random one (which triggers review_requested event)
 */
async function handlePROpened(
  payload: PullRequestEvent,
  customFields: PRFields,
  prStatus: string
): Promise<asana.resources.Tasks.Type[]> {
  const githubAuthor = payload.pull_request.user.login
  const automatedPR = isImportantAutomatedPR(payload)
  const authorAsanaId = getUserIdFromLogin(githubAuthor)

  if (!authorAsanaId && !automatedPR) {
    info(
      `Skipping Asana sync for PR created by ${githubAuthor} as they are not in USER_MAP`
    )
    return []
  }

  // Get all requested reviewers
  const requestedReviewers = (payload.pull_request.requested_reviewers as User[])
    .filter((user: User) => user !== undefined && user.login !== githubAuthor)

  // Also include assignees as potential reviewers
  const assignees = payload.pull_request.assignees.filter(
    (user: User) => user.login !== githubAuthor
  )

  // Combine and deduplicate
  const allReviewers = new Map<string, string>()
  for (const reviewer of [...requestedReviewers, ...assignees]) {
    allReviewers.set(reviewer.login, reviewer.login)
  }

  // If no reviewers yet, try to assign a random reviewer
  // The random reviewer assignment triggers a review_requested event which will create the task
  if (allReviewers.size === 0) {
    if (!automatedPR && RANDOMIZED_REVIEWERS_LIST.includes(githubAuthor)) {
      const possibleReviewers = RANDOMIZED_REVIEWERS_LIST.filter(
        (reviewer: string) => reviewer !== githubAuthor
      )
      if (possibleReviewers.length > 0) {
        const randomReviewer =
          possibleReviewers[Math.floor(Math.random() * possibleReviewers.length)]

        const octokit = getOctokit(getInput('GITHUB_TOKEN'))
        try {
          const reviewerResponse = await octokit.rest.pulls.requestReviewers({
            owner: context.repo.owner,
            repo: context.repo.repo,
            // eslint-disable-next-line camelcase
            pull_number: payload.pull_request.number,
            reviewers: [randomReviewer]
          })

          const assigneeResponse = await octokit.rest.issues.addAssignees({
            owner: context.repo.owner,
            repo: context.repo.repo,
            // eslint-disable-next-line camelcase
            issue_number: payload.pull_request.number,
            assignees: [randomReviewer]
          })

          if (
            reviewerResponse.status === 201 &&
            assigneeResponse.status === 201
          ) {
            info(`PR assigned to random reviewer: ${randomReviewer}. Task will be created via review_requested event.`)
          }
        } catch (e) {
          info(`Could not assign to a random reviewer: ${e}`)
        }
      }
    }

    // No reviewers assigned - don't create any tasks
    // Tasks will be created when reviewers are assigned via review_requested events
    info('No reviewers assigned to PR. Skipping task creation.')
    return []
  }

  // Create tasks for reviewers that were assigned when the PR was opened
  const body = payload.pull_request.body || ''
  const {parentTaskId} = await findParentTaskId(body)
  const createdTasks: asana.resources.Tasks.Type[] = []

  for (const reviewerLogin of allReviewers.keys()) {
    const task = await getOrCreateTaskForReviewer(
      payload,
      reviewerLogin,
      customFields,
      prStatus,
      parentTaskId,
      automatedPR
    )
    if (task) {
      createdTasks.push(task)
    }
  }

  if (createdTasks.length > 0) {
    setOutput('result', 'created')
    setOutput(
      'task_url',
      createdTasks.map(t => t.permalink_url).join(', ')
    )
  }

  // Update PR description with Asana task link if it's an automated PR
  if (automatedPR && createdTasks.length > 0) {
    const prBody = payload.pull_request.body || ''
    if (!prBody.includes('Issue URL:')) {
      const octokit = getOctokit(getInput('GITHUB_TOKEN'))
      const newBody = `Task/Issue URL: ${createdTasks[0].permalink_url}
Copy for release note: N/A
CC:

**Description**:
${prBody}
`
      await octokit.rest.pulls.update({
        owner: context.repo.owner,
        repo: context.repo.repo,
        // eslint-disable-next-line camelcase
        pull_number: payload.pull_request.number,
        body: newBody
      })
    }
  }

  return createdTasks
}

/**
 * Handle pull request review event - update the reviewer's task
 */
async function handlePullRequestReview(
  payload: PullRequestReviewEvent,
  customFields: PRFields,
  prStatus: string,
  approvalStatus:
    | 'pending'
    | 'commented'
    | 'changes_requested'
    | 'approved'
    | 'rejected'
    | undefined
): Promise<void> {
  const reviewerLogin = payload.review.user.login
  const reviewerAsanaId = getUserIdFromLogin(reviewerLogin)

  if (!reviewerAsanaId) {
    info(`Reviewer ${reviewerLogin} is not in USER_MAP, skipping update`)
    return
  }

  const prURL = payload.pull_request.html_url
  const task = await findPRTaskForReviewer(customFields, prURL, reviewerAsanaId)

  if (!task) {
    info(`No task found for reviewer ${reviewerLogin}`)
    return
  }

  const updateParams: asana.resources.Tasks.UpdateParams = {
    // eslint-disable-next-line camelcase
    custom_fields: {
      [customFields.status.gid]: prStatus
    }
  }

  if (approvalStatus && approvalStatus !== 'commented') {
    // eslint-disable-next-line camelcase
    updateParams.approval_status = approvalStatus
  }

  // Close task if approved
  if (approvalStatus === 'approved') {
    updateParams.completed = true
  }

  // Move to in-progress if changes requested or commented
  if (approvalStatus === 'commented' || approvalStatus === 'changes_requested') {
    const sectionId = getInput('ASANA_IN_PROGRESS_SECTION_ID')
    if (sectionId) {
      await client.sections.addTask(sectionId, {task: task.gid})
    }
  }

  await client.tasks.updateTask(task.gid, updateParams)
  info(`Updated task ${task.gid} for reviewer ${reviewerLogin}`)
  setOutput('result', 'updated')
  setOutput('task_url', task.permalink_url)
}

/**
 * Handle other PR events (synchronize, edited, etc.) - update all existing tasks
 */
async function handlePRUpdate(
  payload: PullRequestEvent,
  customFields: PRFields,
  prStatus: string
): Promise<void> {
  const prURL = payload.pull_request.html_url
  const tasks = await findAllPRTasks(customFields, prURL)

  if (tasks.length === 0) {
    info(`No existing tasks found for PR ${prURL}`)
    return
  }

  let body = payload.pull_request.body || 'Empty description'
  const htmlUrl = payload.pull_request.html_url
  const preamble = `**Note:** This description is automatically updated from Github. **Changes will be LOST**.

PR: ${htmlUrl}`

  // Asana has limits on size of notes. Let's be very conservative and trim the text
  const truncatedBody = (
    body.length > 5000 ? `${body.slice(0, 5000)}…` : body
  ).replace(/^---$[\s\S]*/gm, '')

  // Unformatted plaintext notes for fallback
  const notes = `
${preamble}

${truncatedBody}`

  // Rich-text notes with some custom "fixes" for Asana to render things
  const htmlNotes = `<body>${renderMD(notes)}</body>`

  // Close tasks if PR is closed/merged
  const shouldClose =
    ['closed'].includes(payload.pull_request.state) ||
    payload.pull_request.merged

  for (const task of tasks) {
    const updateParams: asana.resources.Tasks.UpdateParams = {
      // eslint-disable-next-line camelcase
      custom_fields: {
        [customFields.status.gid]: prStatus
      }
    }

    if (payload.action === 'ready_for_review') {
      // eslint-disable-next-line camelcase
      updateParams.due_on = getDueOn(1)
    }

    if (shouldClose && !task.completed) {
      updateParams.completed = true
      // eslint-disable-next-line camelcase
      updateParams.approval_status = payload.pull_request.merged
        ? 'approved'
        : 'rejected'
    }

    try {
      // Update description only for non-Ship Review tasks
      if (task.name !== 'Ship Review: Pull Request(s)') {
        // eslint-disable-next-line camelcase
        updateParams.html_notes = htmlNotes
      }
      await client.tasks.updateTask(task.gid, updateParams)
      info(`Updated task ${task.gid}`)
    } catch (err) {
      if (updateParams.html_notes) {
        delete updateParams.html_notes
        updateParams.notes = notes
        info(`Updating task with HTML notes failed. Retrying with plaintext`)
        await client.tasks.updateTask(task.gid, updateParams)
      } else {
        throw err
      }
    }
  }

  setOutput('result', 'updated')
  setOutput(
    'task_url',
    tasks.map(t => t.permalink_url).join(', ')
  )
}

async function run(): Promise<void> {
  try {
    info(`Event: ${context.eventName}.`)
    if (
      !['pull_request', 'pull_request_target', 'pull_request_review'].includes(
        context.eventName
      )
    ) {
      info('Only runs for PR changes and reviews')
      return
    }

    info(`Event JSON: \n${JSON.stringify(context, null, 2)}`)
    const payload = context.payload as PullRequestEvent
    const githubAuthor = payload.pull_request.user.login

    // PR metadata
    const customFields = await findCustomFields(ASANA_WORKSPACE_ID)
    const prState = getPRState(payload.pull_request)
    const prStatus =
      customFields.status.enum_options?.find(
        (f: {name: string; gid: string}) => f.name === prState
      )?.gid || ''
    const approvalStatus = getApprovalStatus(prState, githubAuthor)

    // Route to appropriate handler based on action
    if (context.eventName === 'pull_request_review') {
      const reviewPayload = context.payload as PullRequestReviewEvent
      await handlePullRequestReview(
        reviewPayload,
        customFields,
        prStatus,
        approvalStatus
      )
      return
    }

    const action = payload.action

    if (action === 'review_requested') {
      await handleReviewRequested(
        payload as ReviewRequestedEvent,
        customFields,
        prStatus
      )
      return
    }

    if (action === 'review_request_removed') {
      await handleReviewRequestRemoved(
        payload as ReviewRequestRemovedEvent,
        customFields
      )
      return
    }

    if (action === 'opened') {
      await handlePROpened(payload, customFields, prStatus)
      return
    }

    // Handle other actions (synchronize, edited, ready_for_review, closed, reopened, etc.)
    await handlePRUpdate(payload, customFields, prStatus)
  } catch (error) {
    if (error instanceof Error) {
      setFailed(`${error.message}\nStacktrace:\n${error.stack}`)
    }
  }
}

async function findCustomFields(workspaceGid: string): Promise<PRFields> {
  const apiResponse = await client.customFields.getCustomFieldsForWorkspace(
    workspaceGid
  )
  // pull all fields from the API with the streaming
  const stream = apiResponse.stream()
  const customFields: asana.resources.CustomFields.Type[] = []
  stream.on('data', (field: asana.resources.CustomFields.Type) => {
    customFields.push(field)
  })
  await new Promise<void>(resolve => stream.on('end', resolve))

  const githubUrlField = customFields.find(
    f => f.name === CUSTOM_FIELD_NAMES.url
  )
  const githubStatusField = customFields.find(
    f => f.name === CUSTOM_FIELD_NAMES.status
  )
  if (!githubUrlField || !githubStatusField) {
    debug(JSON.stringify(customFields))
    throw new Error('Custom fields are missing. Please create them')
  } else {
    debug(`${CUSTOM_FIELD_NAMES.url} field GID: ${githubUrlField?.gid}`)
    debug(`${CUSTOM_FIELD_NAMES.status} field GID: ${githubStatusField?.gid}`)
  }
  return {
    url: githubUrlField as asana.resources.CustomField,
    status: githubStatusField as asana.resources.CustomField
  }
}

function getPRState(pr: PullRequest): PRState {
  if (pr.merged) {
    return 'Merged'
  }
  if (pr.state === 'open') {
    if (pr.draft) {
      return 'Draft'
    }
    return 'Open'
  }
  return 'Closed'
}

run()
