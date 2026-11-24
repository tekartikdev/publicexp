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
