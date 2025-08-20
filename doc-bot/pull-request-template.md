---
alwaysApply: false
title: "Pull Request Guidelines & Workflow"
description: "Comprehensive guidelines for creating pull requests, assignment workflows, review processes, and maintaining clean PR lists for Apple browser repositories"
keywords: ["pull request", "pr", "template", "workflow", "code review", "assignment", "asana", "github", "auto-merge", "feature flags", "projects", "tasks"]
---

# Pull Request Guidelines & Workflow

## Objective

- **Maintain a clear and maintainable list** of open PRs in the Apple repositories
- **Improve PR review turnaround time** through proper assignment and notification processes
- **Establish clear rules** for internal (Apple team) and external (FrontEnd, etc.) contributions
- **Remove PR assignment** as part of the Apple Weekly process

## PR Types and Assignment Strategy

We have **two different types** of code contributions:

### **Projects**
Large features or significant changes with designated technical reviewers.

### **Tasks** 
Small improvements or bug fixes that require flexible reviewer assignment.

**Key Principle**: A PR **assignee** is the PR author, a PR **reviewer** is whoever will review it.

## Assignment Workflows

### Projects Workflow

For significant features and planned work:

1. **Use Technical Reviewer**: The technical reviewer should be the default person to assign the PR review
2. **No MM Posting**: There's no need to post the PR link on MM (Mattermost)
3. **Review Assignment Process**:
   - Once the PR is ready for review, assign the technical reviewer as the reviewer on the PR
   - Ping them on Asana on the appropriate task
4. **Shared Responsibility**: Both the technical reviewer and developer are responsible for staying in sync
5. **Fallback**: If the technical reviewer can't review the PR, use the Tasks workflow below

### Tasks Workflow

For bug fixes and small improvements:

1. **Pre-Agreement**: Think about who's the best person to review this task and **agree with them to be the reviewer even before posting the PR** (similar to choosing technical reviewer for projects)

2. **When Uncertain**: If you don't know who would be the best person, or the problem is generic and doesn't require domain knowledge, use **GitHub auto assignment** (see below)

3. **Assignment Process**:
   - Once someone is assigned, ping that person on **Asana** letting them know there's a PR for review
   - If that person is AFK, run the process again to find a new reviewer
   - Feel free to ask the original reviewer for suggestions

4. **Availability Management**:
   - Set your GitHub to "away" to prevent auto-selection if unavailable
   - Use your best judgment for availability

5. **Reviewer Flexibility**: If assigned as reviewer but can't review or don't feel comfortable with the area, discuss reassignment with the PR author

## Auto Review Assignment

**Algorithm**: Load balance routing to equally distribute review work

**Process**:
1. Manually select the **"Apple-dev" team** as the reviewer on the PR
2. GitHub will automatically assign based on load balancing
3. Create an Asana task with the PR link and assign to the selected reviewer

### Assignment on Asana

For both auto and manual assignment:
- **Create an Asana task** with the PR link in the description
- **Assign the task** to the person you want to review
- **Reviewer completes** the code review subtask once review is finished
- **Communication**: Use best judgment to contact PR author via Asana, MM, or PR comments for review feedback

## Draft PRs

**Purpose**: Share in-progress work for early feedback

**Guidelines**:
- Use Draft PRs for work-in-progress sharing
- **Your responsibility**: Don't let drafts stay around for long periods
- **No rigid timeframes**: Use best judgment on when to close drafts
- **Goal**: Keep open PR list as clean as possible

## PR Labels

Use pre-defined labels to classify PR intention/state:

### Current Available Labels

- **`[Hacktoberfest]` & `[hacktoberfest-accepted]`**: For PRs related to Hacktoberfest event
- **`[Pending Product Review]`**: PR is being reviewed in Ship Reviews - **NEVER merge** if this tag is present
- **`[dependencies]`**: Automatically used by Dependabot

**Adding New Labels**: Discuss with the team before creating new labels

## Auto-Merge on Approval

**Feature**: Automatically merge PR after review approval

**Setup Process**:
1. Set PR to auto-merge using GitHub's built-in functionality
2. No specific labels required
3. **Documentation**: [GitHub Auto-merge Guide](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request)

**Requirement**: At least one green review is required due to branch protection

## Branch Protection

**Requirement**: **At least one green review** is required to merge any PR

## Feature Flags & PR Size Guidelines

### PR Size Best Practices

- **Keep PRs as short as possible** for efficiency and respectful time management
- **Use feature flags** (static or dynamic) so changes can be merged without affecting the final product
- **Smaller PRs = better feedback**: More likely to receive constructive review comments

### When Uncertain

- **Talk with technical reviewer** and/or project advisor about breaking down PRs
- **Use feature flags** to enable gradual rollout and safe merging

## Pull Request Template

When creating Pull Requests, always follow this template structure:

```markdown
Task/Issue URL: [Insert URL or ask user if not provided]
Tech Design URL: [Insert URL, N/A, or ask user if not provided for significant changes]
CC: [Insert stakeholders or N/A]

### Description
[Provide a clear and comprehensive description of the changes]

### Testing Steps
[List detailed steps for testing the changes]

### Impact and Risks
**Impact Level: [Assess as High, Medium, Low, or None]**

#### What could go wrong?
[List potential risks and mitigation strategies]

### Quality Considerations
[Include relevant considerations for edge cases, performance, monitoring, documentation, and privacy/security]

### Notes to Reviewer
[Include any specific notes for the reviewer, if applicable]
```

### Template Guidelines

#### Required Information
- **Task/Issue URL**: Always provide the related task or issue
- **Tech Design URL**: Required for significant changes, use "N/A" for minor changes/bug fixes
- **CC**: List relevant stakeholders or use "N/A"
- **Description**: Clear explanation of what was changed and why
- **Testing Steps**: Detailed steps for thorough testing
- **Impact Assessment**: Use guidelines below
- **Risk Analysis**: Potential issues and mitigation strategies
- **Quality Considerations**: Edge cases, performance, monitoring, documentation, privacy/security

#### Impact Level Assessment

- **High**: Changes affecting user privacy/security, data loss potential, core functionality breaks, billing impacts, significant performance effects
- **Medium**: Feature disruption, user flow changes, significant UI changes, analytics/tracking impacts
- **Low**: Minor bug fixes, small UI adjustments, existing feature improvements, non-critical feature additions
- **None**: Internal tooling, documentation, refactoring without behavior changes, test improvements

#### Quality Considerations Checklist

- **Edge cases** that have been considered
- **Performance impacts** and optimizations made
- **Monitoring and analytics** additions or changes
- **Documentation updates** required
- **Privacy and security** considerations, if applicable

## Review Process Best Practices

### For PR Authors
1. **Pre-review checklist**: Ensure all template sections are complete
2. **Self-review**: Review your own changes before requesting review
3. **Context**: Provide sufficient context for reviewers
4. **Responsive**: Address review comments promptly
5. **Asana updates**: Keep related Asana tasks updated

### For PR Reviewers
1. **Timely reviews**: Prioritize PR reviews to maintain good turnaround time
2. **Thorough but efficient**: Balance thoroughness with review speed
3. **Constructive feedback**: Provide actionable suggestions
4. **Asana completion**: Mark code review subtasks as complete
5. **Communication**: Use appropriate channels (Asana, MM, PR comments) for feedback

## Workflow Summary

### For Projects:
1. Technical reviewer assigned by default
2. Ready for review → Assign technical reviewer → Ping on Asana
3. No MM posting required

### For Tasks:
1. Pre-agree on reviewer OR use auto-assignment
2. Assign "Apple-dev" team for auto-assignment
3. Create Asana task → Assign to reviewer → Ping on Asana
4. Handle AFK reviewers by reassigning

### For All PRs:
1. Use feature flags for safe merging
2. Keep PRs small and focused
3. Apply appropriate labels
4. Set auto-merge if desired
5. Follow template requirements
6. Maintain clean draft PR list

---

**Goal**: Efficient, clear, and maintainable PR workflows that respect everyone's time while maintaining code quality.