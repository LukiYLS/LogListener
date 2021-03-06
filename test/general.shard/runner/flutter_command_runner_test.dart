// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:ReplayServerTools/src/base/context.dart';
import 'package:ReplayServerTools/src/base/file_system.dart';
import 'package:ReplayServerTools/src/base/io.dart';
import 'package:ReplayServerTools/src/base/platform.dart';
import 'package:ReplayServerTools/src/base/terminal.dart';
import 'package:ReplayServerTools/src/cache.dart';
import 'package:ReplayServerTools/src/globals.dart' as globals;
import 'package:ReplayServerTools/src/runner/flutter_command.dart';
import 'package:ReplayServerTools/src/runner/flutter_command_runner.dart';
import 'package:ReplayServerTools/src/version.dart';
import 'package:mockito/mockito.dart';
import 'package:process/process.dart';

import '../../src/common.dart';
import '../../src/context.dart';
import 'utils.dart';

const String _kFlutterRoot = '/flutter/flutter';
const String _kEngineRoot = '/flutter/engine';
const String _kArbitraryEngineRoot = '/arbitrary/engine';
const String _kProjectRoot = '/project';
const String _kDotPackages = '.packages';

void main() {
  group('FlutterCommandRunner', () {
    MemoryFileSystem fs;
    Platform platform;
    FlutterCommandRunner runner;
    ProcessManager processManager;

    setUpAll(() {
      Cache.disableLocking();
      Cache.flutterRoot = FlutterCommandRunner.defaultFlutterRoot;
    });

    setUp(() {
      fs = MemoryFileSystem();
      fs.directory(_kFlutterRoot).createSync(recursive: true);
      fs.directory(_kProjectRoot).createSync(recursive: true);
      fs.currentDirectory = _kProjectRoot;

      platform = FakePlatform(
        environment: <String, String>{
          'FLUTTER_ROOT': _kFlutterRoot,
        },
        version: '1 2 3 4 5',
      );

      runner = createTestCommandRunner(DummyFlutterCommand()) as FlutterCommandRunner;
      processManager = MockProcessManager();
    });

    group('run', () {
      testUsingContext('checks that Flutter installation is up-to-date', () async {
        final MockFlutterVersion version = globals.flutterVersion as MockFlutterVersion;
        bool versionChecked = false;
        when(version.checkFlutterVersionFreshness()).thenAnswer((_) async {
          versionChecked = true;
        });

        await runner.run(<String>['dummy']);

        expect(versionChecked, isTrue);
      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
        Platform: () => platform,
      }, initializeFlutterRoot: false);

      testUsingContext('does not check that Flutter installation is up-to-date with --machine flag', () async {
        final MockFlutterVersion version = globals.flutterVersion as MockFlutterVersion;
        bool versionChecked = false;
        when(version.checkFlutterVersionFreshness()).thenAnswer((_) async {
          versionChecked = true;
        });

        await runner.run(<String>['dummy', '--machine', '--version']);

        expect(versionChecked, isFalse);
      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
        Platform: () => platform,
      }, initializeFlutterRoot: false);

      testUsingContext('Fetches tags when --version is used', () async {
        final MockFlutterVersion version = globals.flutterVersion as MockFlutterVersion;

        await runner.run(<String>['--version']);

        verify(version.fetchTagsAndUpdate()).called(1);
      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
        Platform: () => platform,
      }, initializeFlutterRoot: false);

      testUsingContext('throw tool exit if the version file cannot be written', () async {
        final MockFlutterVersion version = globals.flutterVersion as MockFlutterVersion;
        when(version.ensureVersionFile()).thenThrow(const FileSystemException());

        expect(() async => await runner.run(<String>['dummy']), throwsToolExit());

      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
        Platform: () => platform,
      }, initializeFlutterRoot: false);

      testUsingContext('works if --local-engine is specified and --local-engine-src-path is determined by sky_engine', () async {
        fs.directory('$_kArbitraryEngineRoot/src/out/ios_debug/gen/dart-pkg/sky_engine/lib/').createSync(recursive: true);
        fs.directory('$_kArbitraryEngineRoot/src/out/host_debug').createSync(recursive: true);
        fs.file(_kDotPackages).writeAsStringSync('sky_engine:file://$_kArbitraryEngineRoot/src/out/ios_debug/gen/dart-pkg/sky_engine/lib/');

        await runner.run(<String>['dummy', '--local-engine=ios_debug']);

        // Verify that this also works if the sky_engine path is a symlink to the engine root.
        fs.link('/symlink').createSync(_kArbitraryEngineRoot);
        fs.file(_kDotPackages).writeAsStringSync('sky_engine:file:///symlink/src/out/ios_debug/gen/dart-pkg/sky_engine/lib/');

        await runner.run(<String>['dummy', '--local-engine=ios_debug']);
      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
        Platform: () => platform,
      }, initializeFlutterRoot: false);

      testUsingContext('works if --local-engine is specified and --local-engine-src-path is specified', () async {
        // Intentionally do not create a package_config to verify that it is not required.
        fs.directory('$_kArbitraryEngineRoot/src/out/ios_debug').createSync(recursive: true);
        fs.directory('$_kArbitraryEngineRoot/src/out/host_debug').createSync(recursive: true);

        await runner.run(<String>['dummy', '--local-engine-src-path=$_kArbitraryEngineRoot/src', '--local-engine=ios_debug']);
      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
        Platform: () => platform,
      }, initializeFlutterRoot: false);

      testUsingContext('works if --local-engine is specified and --local-engine-src-path is determined by flutter root', () async {
        fs.file(_kDotPackages).writeAsStringSync('\n');
        fs.directory('$_kEngineRoot/src/out/ios_debug').createSync(recursive: true);
        fs.directory('$_kEngineRoot/src/out/host_debug').createSync(recursive: true);

        await runner.run(<String>['dummy', '--local-engine=ios_debug']);
      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
        Platform: () => platform,
      }, initializeFlutterRoot: false);
    });

    testUsingContext('Doesnt crash on invalid .packages file', () async {
      fs.file('pubspec.yaml').createSync();
      fs.file('.packages')
        ..createSync()
        ..writeAsStringSync('Not a valid package');

      await runner.run(<String>['dummy']);

    }, overrides: <Type, Generator>{
      FileSystem: () => fs,
      ProcessManager: () => FakeProcessManager.any(),
      Platform: () => platform,
    }, initializeFlutterRoot: false);

    group('version', () {
      testUsingContext('checks that Flutter toJson output reports the flutter framework version', () async {
        final ProcessResult result = ProcessResult(0, 0, 'random', '0');

        when(processManager.runSync(FlutterVersion.gitLog('-n 1 --pretty=format:%H'.split(' ')),
          workingDirectory: Cache.flutterRoot)).thenReturn(result);
        when(processManager.runSync('git rev-parse --abbrev-ref --symbolic @{u}'.split(' '),
          workingDirectory: Cache.flutterRoot)).thenReturn(result);
        when(processManager.runSync('git rev-parse --abbrev-ref HEAD'.split(' '),
          workingDirectory: Cache.flutterRoot)).thenReturn(result);
        when(processManager.runSync('git ls-remote --get-url master'.split(' '),
          workingDirectory: Cache.flutterRoot)).thenReturn(result);
        when(processManager.runSync(FlutterVersion.gitLog('-n 1 --pretty=format:%ar'.split(' ')),
          workingDirectory: Cache.flutterRoot)).thenReturn(result);
        when(processManager.runSync('git fetch https://github.com/flutter/flutter.git --tags'.split(' '),
          workingDirectory: Cache.flutterRoot)).thenReturn(result);
        when(processManager.runSync('git tag --points-at HEAD'.split(' '),
          workingDirectory: Cache.flutterRoot)).thenReturn(result);
        when(processManager.runSync('git describe --match *.*.* --first-parent --long --tags'.split(' '),
          workingDirectory: Cache.flutterRoot)).thenReturn(result);
        when(processManager.runSync(FlutterVersion.gitLog('-n 1 --pretty=format:%ad --date=iso'.split(' ')),
          workingDirectory: Cache.flutterRoot)).thenReturn(result);

        final FakeFlutterVersion version = FakeFlutterVersion();

        // Because the hash depends on the time, we just use the 0.0.0-unknown here.
        expect(version.toJson()['frameworkVersion'], '0.10.3');
      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => processManager,
        Platform: () => platform,
      }, initializeFlutterRoot: false);
    });

    group('getRepoPackages', () {
      String oldFlutterRoot;

      setUp(() {
        oldFlutterRoot = Cache.flutterRoot;
        Cache.flutterRoot = _kFlutterRoot;
        fs.directory(fs.path.join(_kFlutterRoot, 'examples'))
            .createSync(recursive: true);
        fs.directory(fs.path.join(_kFlutterRoot, 'packages'))
            .createSync(recursive: true);
        fs.directory(fs.path.join(_kFlutterRoot, 'dev', 'tools', 'aatool'))
            .createSync(recursive: true);

        fs.file(fs.path.join(_kFlutterRoot, 'dev', 'tools', 'pubspec.yaml'))
            .createSync();
        fs.file(fs.path.join(_kFlutterRoot, 'dev', 'tools', 'aatool', 'pubspec.yaml'))
            .createSync();
      });

      tearDown(() {
        Cache.flutterRoot = oldFlutterRoot;
      });

      testUsingContext('', () {
        final List<String> packagePaths = runner.getRepoPackages()
            .map((Directory d) => d.path).toList();
        expect(packagePaths, <String>[
          fs.directory(fs.path.join(_kFlutterRoot, 'dev', 'tools', 'aatool')).path,
          fs.directory(fs.path.join(_kFlutterRoot, 'dev', 'tools')).path,
        ]);
      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
        Platform: () => platform,
      }, initializeFlutterRoot: false);
    });

    group('wrapping', () {
      testUsingContext('checks that output wrapping is turned on when writing to a terminal', () async {
        final FakeFlutterCommand fakeCommand = FakeFlutterCommand();
        runner.addCommand(fakeCommand);
        await runner.run(<String>['fake']);
        expect(fakeCommand.preferences.wrapText, isTrue);
      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
        Stdio: () => FakeStdio(hasFakeTerminal: true),
      }, initializeFlutterRoot: false);

      testUsingContext('checks that output wrapping is turned off when not writing to a terminal', () async {
        final FakeFlutterCommand fakeCommand = FakeFlutterCommand();
        runner.addCommand(fakeCommand);
        await runner.run(<String>['fake']);
        expect(fakeCommand.preferences.wrapText, isFalse);
      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
        Stdio: () => FakeStdio(hasFakeTerminal: false),
      }, initializeFlutterRoot: false);

      testUsingContext('checks that output wrapping is turned off when set on the command line and writing to a terminal', () async {
        final FakeFlutterCommand fakeCommand = FakeFlutterCommand();
        runner.addCommand(fakeCommand);
        await runner.run(<String>['--no-wrap', 'fake']);
        expect(fakeCommand.preferences.wrapText, isFalse);
      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
        Stdio: () => FakeStdio(hasFakeTerminal: true),
      }, initializeFlutterRoot: false);

      testUsingContext('checks that output wrapping is turned on when set on the command line, but not writing to a terminal', () async {
        final FakeFlutterCommand fakeCommand = FakeFlutterCommand();
        runner.addCommand(fakeCommand);
        await runner.run(<String>['--wrap', 'fake']);
        expect(fakeCommand.preferences.wrapText, isTrue);
      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
        Stdio: () => FakeStdio(hasFakeTerminal: false),
      }, initializeFlutterRoot: false);
    });
  });
}
class MockProcessManager extends Mock implements ProcessManager {}

class FakeFlutterVersion extends FlutterVersion {
  @override
  String get frameworkVersion => '0.10.3';
}

class FakeFlutterCommand extends FlutterCommand {
  OutputPreferences preferences;

  @override
  Future<FlutterCommandResult> runCommand() {
    preferences = globals.outputPreferences;
    return Future<FlutterCommandResult>.value(const FlutterCommandResult(ExitStatus.success));
  }

  @override
  String get description => null;

  @override
  String get name => 'fake';
}

class FakeStdio extends Stdio {
  FakeStdio({this.hasFakeTerminal});

  final bool hasFakeTerminal;

  @override
  bool get hasTerminal => hasFakeTerminal;

  @override
  int get terminalColumns => hasFakeTerminal ? 80 : null;

  @override
  int get terminalLines => hasFakeTerminal ? 24 : null;
  @override
  bool get supportsAnsiEscapes => hasFakeTerminal;
}
