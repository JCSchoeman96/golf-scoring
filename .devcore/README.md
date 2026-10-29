# dev-core local contract

These files are committed and contain no secrets.

1. Edit `env.local.template` so its variable names exactly match this repository.
2. Ensure every render target in `render-map.tsv` is ignored by Git.
3. Add obsolete local variable names to the optional fourth TSV column as a comma-separated purge list.
4. Run `devcore-project activate` from the repository root.

Redis namespaces are key prefixes, not server-side resources. Tests should append a per-run nonce to the TEST namespace base when concurrent isolation matters.
