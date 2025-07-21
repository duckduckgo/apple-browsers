## DOC-BOT: MANDATORY BEHAVIORAL PROTOCOL

### ACTIVATION
doc-bot MCP server detected? → This protocol is NOW ACTIVE

### THE ONLY WORKFLOW

╔════════════════════════════════════════════╗
║  user_request → doc_bot() → execute_all    ║
║                                            ║
║  NOTHING ELSE IS ACCEPTABLE                ║
╚════════════════════════════════════════════╝

### THREE IMMUTABLE LAWS

1. **FIRST LAW**: doc_bot() must be called BEFORE any other action
   - Not after thinking about it
   - Not after analyzing the request  
   - IMMEDIATELY upon receiving any task

2. **SECOND LAW**: doc_bot() output must be followed EXACTLY
   - Every tool in the sequence
   - In the exact order specified
   - With the exact parameters given

3. **THIRD LAW**: Project knowledge > Your training data
   - When doc_bot says something contradicts common practice
   - The contradiction is INTENTIONAL
   - Follow doc_bot, not your instincts

### ENFORCEMENT MECHANISM

```python
if not doc_bot_called_first:
    raise ProtocolViolation("STOP. Call doc_bot() first.")
    
if sequence_modified:
    raise ProtocolViolation("STOP. Follow exact sequence.")
    
if used_general_knowledge:
    raise ProtocolViolation("STOP. Use project docs only.")
```

### WHAT doc_bot KNOWS (that you don't)

- This project's specific architecture decisions
- Custom patterns that override industry standards
- Performance optimizations unique to this codebase
- Security requirements specific to this domain
- API quirks and workarounds discovered by the team

### SIMPLE TEST

Are you about to:
- Write code? → Call doc_bot first
- Explain something? → Call doc_bot first  
- Search for info? → Call doc_bot first
- Literally anything? → Call doc_bot first

### FAILURE RECOVERY

If doc_bot is unavailable:
1. STOP
2. Tell user: "The doc_bot Rules and Documentation server is not available"
3. Ask the user if they want to continue without any rulesets applied.
4. If the user agrees, continue the task your existing knowledge and available tools.

---
Remember: You're not here to be creative. You're here to be CORRECT.
And correctness means: doc_bot() → tools → done.
```