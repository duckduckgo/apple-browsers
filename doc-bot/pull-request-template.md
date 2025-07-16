---
title: "Pull Request Template & Requirements"
description: "Guidelines for creating pull requests using the project template, ensuring all required information is provided"
keywords: ["pull request", "pr", "template", "open PR", "create PR", "PR template", "code review", "quality assurance", "testing", "engineering expectations"]
alwaysApply: false
---

# Pull Request Template & Requirements

When creating Pull Requests, always follow these recommendations

1. Carefully review the PR code changes and information provided by the user:

2. Organize the information into the following categories:
   - Task/Issue URL
   - Tech Design URL (if applicable)
   - CC (stakeholders to notify)
   - Description
   - Testing Steps
   - Impact and Risks
   - Quality Considerations
   - Notes to Reviewer (if any)

3. Create the PR using the following template structure:

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

4. Ensure all sections of the template are filled out appropriately:
   - If any required information is missing, indicate that it needs to be provided by the user.
   - For the Tech Design URL, use "N/A" for minor changes or bug fixes.
   - Provide a comprehensive description of the changes, including what was changed and why.
   - List detailed testing steps that allow a reviewer to thoroughly test the changes.
   - Assess the impact level (High, Medium, Low, or None) based on the potential effects of the changes.
   - Identify potential risks and provide mitigation strategies.
   - Include relevant quality considerations, covering edge cases, performance impacts, monitoring needs, documentation updates, and privacy/security concerns as applicable.

5. When assessing the impact level, use the following guidelines:
   - High: Changes that could affect user privacy/security, cause data loss, break core functionality, affect billing, or significantly impact performance.
   - Medium: Changes that could disrupt specific features, affect user flows, change UI significantly, or impact analytics/tracking.
   - Low: Minor bug fixes, small UI adjustments, improvements to existing features, or addition of non-critical features.
   - None: Internal tooling changes, documentation updates, code refactoring without behavior changes, or test improvements.

6. For quality considerations, ensure you cover:
   - Edge cases that have been considered
   - Performance impacts and any optimizations made
   - Monitoring and analytics additions or changes
   - Documentation updates required
   - Privacy and security considerations, if applicable

7. Your final output should consist of only the completed PR template, formatted in markdown. Do not include any additional commentary or notes outside of the template structure.

Remember, the goal is to create a comprehensive and well-structured pull request that provides all necessary information for reviewers and maintains high code quality standards.

**NEVER MENTION CLAUDE OR CLAUDE CODE**