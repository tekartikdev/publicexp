# Windows stdin exit hang

Branch `windows_stdin_exit_hang`: a reproduction for a Dart SDK issue. On
Windows, a compiled program that listened to its stdin (a pipe) and cancelled
the subscription sometimes never exits while the pipe stays open, after
`main` returned.

- `windows_stdin_exit_hang_exp/repro.dart`: the reproduction, `dart:io`
  only. Run `dart windows_stdin_exit_hang_exp/repro.dart [runs per variant]`.
- `windows_stdin_exit_hang_exp/issue.md`: the issue text.
- `.github/workflows/windows_stdin_exit_hang.yml`: runs it on Windows
  (stable and dev) and Linux.
