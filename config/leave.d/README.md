# leave.d — custom actions when Agent Ready turns off

Put executable `*.sh` scripts here. They run **after** the built-in restore
actions, in filename order. A script that fails is logged and does not stop the
others.

Available environment variables:

```
AGENT_READY_ACTION=leave
AGENT_READY_CONFIG_DIR   ~/.config/omarchy/agent-ready
AGENT_READY_STATE_DIR    ~/.local/state/omarchy/agent-ready
AGENT_READY_STATE_FILE   .../state.json
```

Use these to undo anything you started in `../enter.d/`.

Output goes to `~/.local/state/omarchy/agent-ready/log`.
