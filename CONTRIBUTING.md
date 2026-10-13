# Contributing

1. Fork, then branch from `main`.
2. Make the change. Keep `Sources/NotchCore` free of AppKit; it is the part covered by checks.
3. Run `./scripts/test.sh` (exit code 0 means every check passed) and `./scripts/build.sh`.
4. For UI changes, attach a screenshot; `--fixture <scene>` and `--snapshot <dir>` render the app without live agents.
5. Open a pull request with what changed and how you checked it.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org): `feat(list): …`, `fix(hooks): …`.

## Releasing

1. Add a section for the version to `CHANGELOG.md`.
2. Tag and push: `git tag v0.2.0 && git push origin v0.2.0`.
3. The Release workflow runs the checks, builds the DMG and zip, publishes the GitHub release with notes from the changelog, and updates the Homebrew cask in `Forichok/homebrew-tap` (needs the `TAP_TOKEN` secret).
