/// Times `pub get` and `pub upgrade` on this package, whose dependency graph
/// holds about 220 git packages from 77 public GitHub repositories.
///
/// Uses `dart:io` only, so that running it does not need this package to be
/// resolved first (resolving it is what is timed):
///
/// ```sh
/// dart tool/pub_timing.dart
/// dart tool/pub_timing.dart --runs 3 --fetches
/// dart tool/pub_timing.dart --pub "dart pub" --pub "dart /path/to/pub.dill"
/// ```
library;

import 'dart:io';

/// What a timed command starts from.
enum Scenario {
  /// `pub get` with `pubspec.lock` deleted.
  getNoLock('get-no-lock', 'get'),

  /// `pub upgrade` with a `pubspec.lock`.
  upgrade('upgrade', 'upgrade'),

  /// `pub get` with an up to date `pubspec.lock`.
  get('get', 'get');

  const Scenario(this.label, this.command);

  /// Name on the command line and in the report.
  final String label;

  /// The pub command run.
  final String command;
}

const _usage = '''
Usage: dart tool/pub_timing.dart [options]

  --pub <command>      pub command to time, repeatable (default: "dart pub"),
                       split on spaces, e.g. "dart /path/to/pub.dill".
  --runs <n>           rounds, each one times every pub command (default: 1).
  --scenario <names>   comma separated, among get-no-lock, upgrade, get
                       (default: all, in that order).
  --fetches            also count the git fetch and clone commands pub runs
                       (runs pub with --verbose).
''';

final _packageDir = File.fromUri(Platform.script).parent.parent.path;
final _lockFile = File('$_packageDir${Platform.pathSeparator}pubspec.lock');

Never _fail(String message) {
  stderr
    ..writeln(message)
    ..write(_usage);
  exit(64);
}

Future<void> main(List<String> arguments) async {
  final pubs = <String>[];
  var runs = 1;
  var scenarios = Scenario.values.toList();
  var countFetches = false;
  for (var i = 0; i < arguments.length; i++) {
    final option = arguments[i];
    String value() =>
        ++i < arguments.length ? arguments[i] : _fail('Missing $option value');
    switch (option) {
      case '--pub':
        pubs.add(value());
      case '--runs':
        runs = int.tryParse(value()) ?? _fail('Invalid --runs');
      case '--scenario':
        scenarios = [
          for (final name in value().split(','))
            Scenario.values.firstWhere(
              (scenario) => scenario.label == name,
              orElse: () => _fail('Unknown scenario $name'),
            ),
        ];
      case '--fetches':
        countFetches = true;
      case '-h' || '--help':
        stdout.write(_usage);
        return;
      default:
        _fail('Unknown option $option');
    }
  }
  if (pubs.isEmpty) pubs.add('dart pub');

  stdout
    ..writeln(
      (await Process.run('dart', ['--version'])).stdout.toString().trim(),
    )
    ..writeln(
      (await Process.run('git', ['--version'])).stdout.toString().trim(),
    );
  final concurrency = Platform.environment['PUB_GIT_CONCURRENCY'];
  if (concurrency != null) stdout.writeln('PUB_GIT_CONCURRENCY=$concurrency');
  stdout.writeln();

  final results = <(Scenario, String), List<Duration>>{};
  for (var run = 1; run <= runs; run++) {
    for (final scenario in scenarios) {
      for (final pub in pubs) {
        final result = await _time(pub, scenario, countFetches: countFetches);
        results.putIfAbsent((scenario, pub), () => []).add(result.elapsed);
        stdout.writeln(
          'run $run  ${scenario.label.padRight(11)}  ${_seconds(result.elapsed)}'
          '${result.fetches == null ? '' : '  fetches ${result.fetches}'}'
          '${result.clones == null ? '' : '  clones ${result.clones}'}'
          '  $pub',
        );
        if (result.exitCode != 0) {
          stderr.writeln('$pub ${scenario.command} failed: ${result.exitCode}');
          exit(1);
        }
      }
    }
  }

  stdout
    ..writeln()
    ..writeln('$runs run(s)       min   median');
  for (final MapEntry(key: (scenario, pub), value: durations)
      in results.entries) {
    final sorted = [...durations]..sort();
    final middle = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) ~/ 2;
    stdout.writeln(
      '  ${scenario.label.padRight(11)}  '
      '${_seconds(sorted.first)}  ${_seconds(median)}  $pub',
    );
  }
}

String _seconds(Duration duration) =>
    '${(duration.inMilliseconds / 1000).toStringAsFixed(1).padLeft(5)} s';

Future<({Duration elapsed, int exitCode, int? fetches, int? clones})> _time(
  String pub,
  Scenario scenario, {
  required bool countFetches,
}) async {
  final parts = pub.split(' ').where((part) => part.isNotEmpty).toList();
  Future<ProcessResult> runPub(String command, {bool verbose = false}) =>
      Process.run(parts.first, [
        ...parts.skip(1),
        command,
        if (verbose) '--verbose',
      ], workingDirectory: _packageDir);

  if (scenario == Scenario.getNoLock) {
    if (_lockFile.existsSync()) _lockFile.deleteSync();
  } else if (!_lockFile.existsSync()) {
    // The scenario starts from a lock file, get one first (not timed).
    await runPub('get');
  }

  final stopwatch = Stopwatch()..start();
  final result = await runPub(scenario.command, verbose: countFetches);
  stopwatch.stop();

  int? count(RegExp command) => countFetches
      ? command.allMatches('${result.stdout}\n${result.stderr}').length
      : null;
  if (result.exitCode != 0) stderr.write(result.stderr);
  return (
    elapsed: stopwatch.elapsed,
    exitCode: result.exitCode,
    fetches: count(RegExp(r'Spawning "git [^\n"]* fetch"')),
    clones: count(RegExp(r'Spawning "git (?:[^\n"]* )?clone ')),
  );
}
