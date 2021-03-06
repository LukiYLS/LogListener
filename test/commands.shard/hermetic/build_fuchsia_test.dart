// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:file_testing/file_testing.dart';
import 'package:ReplayServerTools/src/base/file_system.dart';
import 'package:ReplayServerTools/src/base/platform.dart';
import 'package:ReplayServerTools/src/build_info.dart';
import 'package:ReplayServerTools/src/cache.dart';
import 'package:ReplayServerTools/src/commands/build.dart';
import 'package:ReplayServerTools/src/features.dart';
import 'package:ReplayServerTools/src/fuchsia/fuchsia_kernel_compiler.dart';
import 'package:ReplayServerTools/src/fuchsia/fuchsia_pm.dart';
import 'package:ReplayServerTools/src/fuchsia/fuchsia_sdk.dart';
import 'package:ReplayServerTools/src/project.dart';
import 'package:meta/meta.dart';
import 'package:mockito/mockito.dart';
import 'package:process/process.dart';

import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/mocks.dart';
import '../../src/testbed.dart';

// Defined globally for mocks to use.
FileSystem fileSystem;

void main() {
  Cache.disableLocking();

  final Platform linuxPlatform = FakePlatform(
    operatingSystem: 'linux',
    environment: const <String, String>{
      'FLUTTER_ROOT': '/',
    },
  );
  final Platform windowsPlatform = FakePlatform(
    operatingSystem: 'windows',
    environment: const <String, String>{
      'FLUTTER_ROOT': '/'
    },
  );
  MockFuchsiaSdk fuchsiaSdk;

  setUp(() {
    fuchsiaSdk = MockFuchsiaSdk();
    fileSystem = MemoryFileSystem.test();
  });

  group('Fuchsia build fails gracefully when', () {
    testUsingContext('The feature is disabled', () async {
      final BuildCommand command = BuildCommand();
      fileSystem.directory('fuchsia').createSync(recursive: true);
      fileSystem.file('.packages').createSync();
      fileSystem.file('pubspec.yaml').createSync();
      fileSystem.file('lib/main.dart').createSync(recursive: true);

      expect(
        createTestCommandRunner(command).run(const <String>['build', 'fuchsia']),
        throwsToolExit(message: '"build fuchsia" is currently disabled'),
      );
    }, overrides: <Type, Generator>{
      Platform: () => linuxPlatform,
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
      FeatureFlags: () => TestFeatureFlags(isFuchsiaEnabled: false),
    });
    testUsingContext('there is no Fuchsia project', () async {
      final BuildCommand command = BuildCommand();

      expect(
        createTestCommandRunner(command).run(const <String>['build', 'fuchsia']),
        throwsToolExit(),
      );
    }, overrides: <Type, Generator>{
      Platform: () => linuxPlatform,
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
      FeatureFlags: () => TestFeatureFlags(isFuchsiaEnabled: true),
    });

    testUsingContext('there is no cmx file', () async {
      final BuildCommand command = BuildCommand();
      fileSystem.directory('fuchsia').createSync(recursive: true);
      fileSystem.file('.packages').createSync();
      fileSystem.file('pubspec.yaml').createSync();

      expect(
        createTestCommandRunner(command).run(const <String>['build', 'fuchsia']),
        throwsToolExit(),
      );
    }, overrides: <Type, Generator>{
      Platform: () => linuxPlatform,
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
      FeatureFlags: () => TestFeatureFlags(isFuchsiaEnabled: true),
    });

    testUsingContext('on Windows platform', () async {
      final BuildCommand command = BuildCommand();
      const String appName = 'app_name';
      fileSystem
        .file(fileSystem.path.join('fuchsia', 'meta', '$appName.cmx'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      fileSystem.file('.packages').createSync();
      final File pubspecFile = fileSystem.file('pubspec.yaml')..createSync();
      pubspecFile.writeAsStringSync('name: $appName');

      expect(
        createTestCommandRunner(command).run(const <String>['build', 'fuchsia']),
        throwsToolExit(),
      );
    }, overrides: <Type, Generator>{
      Platform: () => windowsPlatform,
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
      FeatureFlags: () => TestFeatureFlags(isFuchsiaEnabled: true),
    });

    testUsingContext('there is no Fuchsia kernel compiler', () async {
      final BuildCommand command = BuildCommand();
      const String appName = 'app_name';
      fileSystem
        .file(fileSystem.path.join('fuchsia', 'meta', '$appName.cmx'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      fileSystem.file('.packages').createSync();
      fileSystem.file(fileSystem.path.join('lib', 'main.dart')).createSync(recursive: true);
      final File pubspecFile = fileSystem.file('pubspec.yaml')..createSync();
      pubspecFile.writeAsStringSync('name: $appName');

      expect(
        createTestCommandRunner(command).run(const <String>['build', 'fuchsia']),
        throwsToolExit(),
      );
    }, overrides: <Type, Generator>{
      Platform: () => linuxPlatform,
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
      FeatureFlags: () => TestFeatureFlags(isFuchsiaEnabled: true),
    });
  });

  testUsingContext('Fuchsia build parts fit together right', () async {
    final BuildCommand command = BuildCommand();
    applyMocksToCommand(command);
    const String appName = 'app_name';
    fileSystem
        .file(fileSystem.path.join('fuchsia', 'meta', '$appName.cmx'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
    fileSystem.file('.packages').createSync();
    fileSystem.file(fileSystem.path.join('lib', 'main.dart')).createSync(recursive: true);
    final File pubspecFile = fileSystem.file('pubspec.yaml')..createSync();
    pubspecFile.writeAsStringSync('name: $appName');

    await createTestCommandRunner(command)
      .run(const <String>['build', 'fuchsia']);
    final String farPath = fileSystem.path.join(
      getFuchsiaBuildDirectory(), 'pkg', 'app_name-0.far',
    );

    expect(fileSystem.file(farPath), exists);
  }, overrides: <Type, Generator>{
    Platform: () => linuxPlatform,
    FileSystem: () => fileSystem,
    ProcessManager: () => FakeProcessManager.any(),
    FuchsiaSdk: () => fuchsiaSdk,
    FeatureFlags: () => TestFeatureFlags(isFuchsiaEnabled: true),
  });
}

class MockFuchsiaPM extends Mock implements FuchsiaPM {
  String _appName;

  @override
  Future<bool> init(String buildPath, String appName) async {
    if (!fileSystem.directory(buildPath).existsSync()) {
      return false;
    }
    fileSystem
        .file(fileSystem.path.join(buildPath, 'meta', 'package'))
        .createSync(recursive: true);
    _appName = appName;
    return true;
  }

  @override
  Future<bool> genkey(String buildPath, String outKeyPath) async {
    if (!fileSystem.file(fileSystem.path.join(buildPath, 'meta', 'package')).existsSync()) {
      return false;
    }
    fileSystem.file(outKeyPath).createSync(recursive: true);
    return true;
  }

  @override
  Future<bool> build(String buildPath, String keyPath, String manifestPath) async {
    if (!fileSystem.file(fileSystem.path.join(buildPath, 'meta', 'package')).existsSync() ||
        !fileSystem.file(keyPath).existsSync() ||
        !fileSystem.file(manifestPath).existsSync()) {
      return false;
    }
    fileSystem.file(fileSystem.path.join(buildPath, 'meta.far')).createSync(recursive: true);
    return true;
  }

  @override
  Future<bool> archive(String buildPath, String keyPath, String manifestPath) async {
    if (!fileSystem.file(fileSystem.path.join(buildPath, 'meta', 'package')).existsSync() ||
        !fileSystem.file(keyPath).existsSync() ||
        !fileSystem.file(manifestPath).existsSync()) {
      return false;
    }
    if (_appName == null) {
      return false;
    }
    fileSystem
        .file(fileSystem.path.join(buildPath, '$_appName-0.far'))
        .createSync(recursive: true);
    return true;
  }
}

class MockFuchsiaKernelCompiler extends Mock implements FuchsiaKernelCompiler {
  @override
  Future<void> build({
    @required FuchsiaProject fuchsiaProject,
    @required String target, // E.g., lib/main.dart
    BuildInfo buildInfo = BuildInfo.debug,
  }) async {
    final String outDir = getFuchsiaBuildDirectory();
    final String appName = fuchsiaProject.project.manifest.appName;
    final String manifestPath = fileSystem.path.join(outDir, '$appName.dilpmanifest');
    fileSystem.file(manifestPath).createSync(recursive: true);
  }
}

class MockFuchsiaSdk extends Mock implements FuchsiaSdk {
  @override
  final FuchsiaPM fuchsiaPM = MockFuchsiaPM();

  @override
  final FuchsiaKernelCompiler fuchsiaKernelCompiler =
      MockFuchsiaKernelCompiler();
}
