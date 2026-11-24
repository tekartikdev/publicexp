<!-- Draft of a dart-lang/sdk issue, not filed. Fill "Results on Windows" first. -->

# [vm, io] Windows: a program that cancelled its stdin subscription sometimes never exits while its stdin (a pipe) stays open

**Dart SDK version:** 3.14.1 (stable) on "windows_x64" (GitHub Actions `windows-latest`). Never seen on Linux.

## What happens

A compiled program (`dart compile exe`) whose stdin is a pipe that its parent keeps open:

1. listens to `stdin`,
2. runs a process (its stdin a pipe never closed, the way a tool running a command does),
3. prints `ready`, then gets one line on its stdin,
4. cancels the stdin subscription 500ms later, prints `done`, and returns from `main`.

Sometimes the process never exits: `done` is printed, then nothing happens until the parent kills it.

Seen in the CI of `package:process_run`. One test there does exactly this through `sharedStdIn`. It hung in 2 of 4 Windows runs on Dart 3.14.1, and the log showed `done` as the last line printed:

- https://github.com/tekartik/process_run.dart/actions/runs/45413802661: `terminate: no exit within 0:00:15.000000, printed [ready, done]`
- https://github.com/tekartik/process_run.dart/actions/runs/45405897853 (attempt 1)

The same test passed in 7 earlier Windows runs (Dart 3.13.7, 3.14.0, 3.14.1) and never hung on Linux in 60 runs. The run that came after one more change passed: the parent now closes the pipe once `done` is printed.

## Reproduction

Only `dart:io`. Save it as `repro.dart` and run `dart repro.dart [runs per variant, 20 by default]`. It compiles itself, then runs the executable once per run, with its stdin kept open, for 4 variants:

- `plain`: listen to stdin, then cancel
- `line`: a line is written once `ready` is printed
- `process`: runs a process first
- `process+line`: both

For each variant it prints the outcome counts:

- `exited`: the process exited
- `no exit`: `done` was printed but the process did not exit within 10 s (the issue)
- `no ready` or `no done`: the run hung at an earlier step

```dart
// Reproduction for a Dart SDK issue: on Windows a compiled program that
// listened to its stdin (a pipe) and cancelled the subscription sometimes
// never exits while the pipe stays open, after main returned.
//
// No dependency, only dart:io (an SDK issue: no process_run here).
//
//   dart repro.dart [runs per variant, 20 by default]
//
// Compiles this file (`dart compile exe`), then runs the executable `runs`
// times per variant, its stdin a pipe kept open, and counts the runs that
// printed `done` but did not exit within 10 seconds.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Time given to each step of a run.
const _timeout = Duration(seconds: 10);

/// The variants of the program: `line` (a line is written to its stdin once
/// it printed `ready`), `process` (it runs a process first, its stdin a pipe
/// left open, as a tool running a command does).
const _variants = [
  <String>[],
  ['line'],
  ['process'],
  ['process', 'line'],
];

Future<void> main(List<String> arguments) async {
  switch (arguments.firstOrNull) {
    case 'child':
      await _child(arguments.skip(1).toSet());
    case 'version':
      stdout.writeln('1.0.0');
    default:
      var runs = arguments.isEmpty ? 20 : int.parse(arguments.first);
      await _parent(runs);
  }
}

/// The program tested: listens to its stdin, prints `ready`, cancels the
/// subscription 500ms later, prints `done` and returns.
Future<void> _child(Set<String> options) async {
  var subscription = stdin.listen((_) {});
  if (options.contains('process')) {
    var process = await Process.start(Platform.resolvedExecutable, ['version']);
    // Its stdin is never closed.
    await Future.wait([
      process.stdout.drain<void>(),
      process.stderr.drain<void>(),
      process.exitCode,
    ]);
  }
  stdout.writeln('ready');
  // Time for the line written on `ready` to arrive.
  await Future<void>.delayed(const Duration(milliseconds: 500));
  await subscription.cancel();
  stdout.writeln('done');
}

/// Compiles this file, runs each variant [runs] times.
Future<void> _parent(int runs) async {
  stdout.writeln(Platform.version);
  var dir = await Directory.systemTemp.createTemp('windows_stdin_exit_hang');
  var exe = [
    dir.path,
    'repro${Platform.isWindows ? '.exe' : ''}',
  ].join(Platform.pathSeparator);
  var compile = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    Platform.script.toFilePath(),
    '-o',
    exe,
  ]);
  if (compile.exitCode != 0) {
    stderr.writeln('${compile.stdout}${compile.stderr}');
    exit(1);
  }
  for (var variant in _variants) {
    var outcomes = <String, int>{};
    for (var i = 0; i < runs; i++) {
      var outcome = await _run(exe, variant);
      outcomes[outcome] = (outcomes[outcome] ?? 0) + 1;
    }
    var name = variant.isEmpty ? 'plain' : variant.join('+');
    stdout.writeln('$name: $outcomes');
  }
  try {
    await dir.delete(recursive: true);
  } on FileSystemException catch (_) {
    // A killed program may still hold its executable for a while.
  }
}

/// Runs the program once, its stdin open until it exits (or is killed).
///
/// Returns `exited`, or where it hangs: `no ready`, `no done`, `no exit`
/// (`done` printed, main returned: the issue).
Future<String> _run(String exe, List<String> variant) async {
  var process = await Process.start(exe, ['child', ...variant]);
  var ready = Completer<void>();
  var done = Completer<void>();
  var outcome = 'no ready';
  var stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        if (line == 'ready' && !ready.isCompleted) {
          ready.complete();
        } else if (line == 'done' && !done.isCompleted) {
          done.complete();
        }
      })
      .asFuture<void>();
  var stderrDone = process.stderr.drain<void>();
  try {
    await ready.future.timeout(_timeout);
    outcome = 'no done';
    if (variant.contains('line')) {
      process.stdin.writeln('typed');
    }
    await done.future.timeout(_timeout);
    outcome = 'no exit';
    await process.exitCode.timeout(_timeout);
    outcome = 'exited';
  } on TimeoutException catch (_) {
    process.kill();
  }
  try {
    await process.stdin.close();
  } on Object catch (_) {
    // Broken pipe: the program ended.
  }
  await process.exitCode;
  await stdoutDone;
  await stderrDone;
  return outcome;
}
```

## Results on Windows

<!-- To fill: the output of `dart repro.dart 50` on Windows. -->

On Linux (3.14.0), `dart repro.dart 10` reports `{exited: 10}` for every variant.

## Expected

The program exits once `main` returns: after the cancel, nothing in it listens to stdin anymore.

## Possible cause (not verified)

`runtime/bin/eventhandler_win.cc` reads a stdin pipe with a blocking `ReadFile` on a thread of its own ("dart:io ReadFile"). On close, `Handle::CloseLocked` calls `CancelIoEx`, then `StdHandle::DoCloseLocked` replaces fd 0 with NUL (`_dup2`). If that read is not cancelled, the close of the handle, and then the event handler shutdown at exit, could wait for input that never comes while the pipe stays open.
