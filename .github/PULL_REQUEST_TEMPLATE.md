## What changed

<!-- Describe the user-visible behavior and its limitations. Keep one concern per pull request. -->

## Related issue

<!-- Link the issue first; open one before larger changes. -->

## Checks

- [ ] `TEST_ARCH=arm64 /bin/zsh scripts/test-public.sh` passes
- [ ] `/bin/zsh build-app.sh --arch arm64 --no-open` succeeds
- [ ] `TEST_ARCH=x86_64` and `--arch x86_64` paths checked when the change is architecture-sensitive
- [ ] Both Intel and Apple silicon CI jobs pass on this pull request
- [ ] Any private macOS API use, filesystem access, network behavior, permission or system-service change is called out above
- [ ] No arbitrary command execution added to preset import
- [ ] No generated build products, credentials, private session data, local logs or real user data included
- [ ] Third-party copyright and license notices preserved; new runtime dependencies discussed first

## Notes for the reviewer

<!-- Anything about hardware-specific behavior, Touch Bar mode, or why an alternative was not used. -->

By submitting this pull request I understand that out-of-scope changes may be closed with a short explanation and a reference to CONTRIBUTING.md, and that my original contribution is offered under the repository's MIT License.
