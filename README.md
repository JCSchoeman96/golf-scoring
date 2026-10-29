<img src="assets/icon.svg" width="64" height="64" alt="">

# Golf Scoring

Phoenix and Ash application with PostgreSQL managed locally by DevCore.

## Local development

Run `devcore-project activate` to provision the project databases and render the ignored local environment file. Check connectivity with `devcore-project doctor`.

```sh
devcore-project run dev -- mix setup
devcore-project run dev -- mix ash.setup
devcore-project run dev -- mix phx.server
```

Visit http://localhost:4101. Run tests with `devcore-project run test -- mix test`.

The main checkout uses port 4101. Allocate ports 4102 through 4121 to worktrees, one port per running checkout. For example:

```sh
PORT=4102 devcore-project run dev -- mix phx.server
```

These are project conventions, not operating system reservations. Check for an existing listener before assigning a port. Port 4100 is already used by the local fastcheck service.

## Developer tooling

Tidewave is available in development at `http://127.0.0.1:4101/tidewave/mcp`. Its Codex MCP registration is named `golf_scoring_tidewave` and targets the main checkout. Restart the Phoenix server after installing dependencies so Tidewave loads. For a worktree, use its assigned port in the MCP URL and a distinct MCP name; the main registration always targets port 4101.

Dependency guidance in `AGENTS.md` is managed by usage_rules. Refresh it with `devcore-project run dev -- mix usage_rules.sync --yes` after dependency changes.
