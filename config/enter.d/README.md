# enter.d — custom actions when Agent Ready turns on

Put executable `*.sh` scripts here. They run **after** the built-in actions,
in filename order. A script that fails is logged and does not stop the others.

Available environment variables:

```
AGENT_READY_ACTION=enter
AGENT_READY_CONFIG_DIR   ~/.config/omarchy/agent-ready
AGENT_READY_STATE_DIR    ~/.local/state/omarchy/agent-ready
AGENT_READY_STATE_FILE   .../state.json
```

Remember to add a matching script in `../leave.d/` to undo whatever you do
here, because Agent Ready restores only the things it changed itself.

Output goes to `~/.local/state/omarchy/agent-ready/log`.
