# Marketplace submission notes

These notes summarize what a maintainer needs to know when reviewing
`eclipse.agent-ready` for the Omarchy plugin marketplace.

## Manual setup is required

Agent Ready has two runtime components:

1. `Widget.qml` — the Omarchy bar widget.
2. `bin/omarchy-agent-ready` — the Bash CLI that owns all state and power actions.

The marketplace's standard `omarchy plugin add ... --enable` path only clones and
enables the QML entry point. It does **not** run `install.sh`, so it leaves the
widget without the required CLI, default config, or hooks. The widget is
nonfunctional in that state.

A working install requires:

```bash
git clone https://github.com/menmer0859/omarchy-agent-ready.git
cd omarchy-agent-ready
./install.sh
```

For a marketplace listing, please use the manual-installation override
(`installation.mode = "manual"`) rather than showing an automatic install command,
and note that users must run `install.sh` from the full checkout.

## Suggested maintainer note

> Manual setup required. The widget depends on a Bash CLI that the default
> clone-and-enable path does not install. Run `./install.sh` from the repository
> checkout to install the CLI, default config, and widget together.

## Listing metadata

- Plugin id: `eclipse.agent-ready`
- Name: Agent Ready
- Version: 1.1.0
- Author: Haomeng Kang (GitHub: `menmer0859`)
- License: MIT
- Kind: `bar-widget`
- Suggested category: `System`
- Suggested tags: `ai`, `bar`, `power-management`
- Preview: `preview.png` in the repository root

## Contest status

This project is **not** part of Plugin Contest #2; the 2026 autumn list was
frozen before submission. Marketplace publication is a long-term channel and can
be used for future contests or general discovery.
