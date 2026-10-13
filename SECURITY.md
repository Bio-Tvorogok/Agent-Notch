# Security

Agent Notch can approve shell commands for your coding agents, so security reports get priority.

Please report a vulnerability privately through [GitHub security advisories](https://github.com/Forichok/Agent-Notch/security/advisories/new) rather than a public issue. Expect a first answer within a few days.

Things that count as a vulnerability:

- any path where a permission request is approved without a human click;
- another local user or process talking to the hook socket;
- a command shown in the list that differs from the one the agent will run;
- the hook installer damaging or leaking the contents of `~/.claude/settings.json` or `~/.codex/hooks.json`.
