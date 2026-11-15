## This is retry {{ATTEMPT}}

Your change from the previous run is already applied in the repository, along with your .agent-evidence/ files and .agent-pr.md. The worker built it and ran your evidence plan, and something failed. The results are below. Fix what failed, then finish as before:

- When the code is wrong, fix the code. When a test you added is wrong, fix or replace that test.
- Don't delete, skip or weaken tests you didn't add to make them pass.
- When a test you didn't add fails, your change doesn't touch the code it tests, and the failure looks unrelated (for example a timeout), you may take it out of tests.txt. Add a line to .agent-evidence/excluded.txt for it, in the form `UnitTests/Class/testMethod: why it's unrelated`. The approver sees these. If your change mentions the test's class, the worker puts the test back.
- When the Maestro flow failed on a selector or timing, fix the flow.
- Update tests.txt, flow.yaml and .agent-pr.md when your fix changes what they should say.
- Your final message replaces the previous one. Describe the whole change, not just this retry, then add one sentence on what this retry fixed.

Results from the previous run:

{{RESULTS}}
