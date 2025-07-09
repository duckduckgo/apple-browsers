## Broker Protection

The following is a high-level description of how the Broker Protection actions are triggered by the native side. 

```mermaid
sequenceDiagram
    participant N as Native 💻
    participant W as Webview (broker-protection.js) 🌐
    participant E as Executor (execute.js) ⚙️
    W->>+W: DOMContentLoaded
    N->>W: 📩 onActionReceived(action, data)
    W->>E: execute(action, data)
    E-->E: Executing action
    Note right of E: ^ reading/writing values - side effects
    E->>W: SuccessResponse(result)
    W->>N: 📤 actionCompleted({ result })
    Note over N,W: ^ if successful, or:
    W->>N: 📤 actionError({ error })
    Note over N: Some time passes...
    N->>W: 📩 onActionReceived(action, data)
```
