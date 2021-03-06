// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:ReplayServerTools/src/artifacts.dart';
import 'package:ReplayServerTools/src/base/file_system.dart';
import 'package:ReplayServerTools/src/base/logger.dart';
import 'package:ReplayServerTools/src/dart/generate_synthetic_packages.dart';
import 'package:ReplayServerTools/src/build_system/build_system.dart';
import 'package:ReplayServerTools/src/build_system/targets/localizations.dart';
import 'package:mockito/mockito.dart';

import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/fake_process_manager.dart';

void main() {
  testWithoutContext('calls buildSystem.build with blank l10n.yaml file', () {
    // Project directory setup for gen_l10n logic
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();

    // Add generate:true to pubspec.yaml.
    final File pubspecFile = fileSystem.file('pubspec.yaml')..createSync();
    final String content = pubspecFile.readAsStringSync().replaceFirst(
      '\nflutter:\n',
      '\nflutter:\n  generate: true\n',
    );
    pubspecFile.writeAsStringSync(content);

    // Create an l10n.yaml file
    fileSystem.file('l10n.yaml').createSync();

    final FakeProcessManager mockProcessManager = FakeProcessManager.any();
    final BufferLogger mockBufferLogger = BufferLogger.test();
    final Artifacts mockArtifacts = Artifacts.test();
    final Environment environment = Environment.test(
      fileSystem.currentDirectory,
      fileSystem: fileSystem,
      logger: mockBufferLogger,
      artifacts: mockArtifacts,
      processManager: mockProcessManager,
    );
    final BuildSystem buildSystem = MockBuildSystem();

    expect(
      () => generateLocalizationsSyntheticPackage(
        environment: environment,
        buildSystem: buildSystem,
      ),
      throwsToolExit(message: 'Generating synthetic localizations package has failed.'),
    );
    // [BuildSystem] should have called build with [GenerateLocalizationsTarget].
    verify(buildSystem.build(
      const GenerateLocalizationsTarget(),
      environment,
    )).called(1);
  });

  testWithoutContext('calls buildSystem.build with l10n.yaml synthetic-package: true', () {
    // Project directory setup for gen_l10n logic
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();

    // Add generate:true to pubspec.yaml.
    final File pubspecFile = fileSystem.file('pubspec.yaml')..createSync();
    final String content = pubspecFile.readAsStringSync().replaceFirst(
      '\nflutter:\n',
      '\nflutter:\n  generate: true\n',
    );
    pubspecFile.writeAsStringSync(content);

    // Create an l10n.yaml file
    fileSystem.file('l10n.yaml').writeAsStringSync('synthetic-package: true');

    final FakeProcessManager mockProcessManager = FakeProcessManager.any();
    final BufferLogger mockBufferLogger = BufferLogger.test();
    final Artifacts mockArtifacts = Artifacts.test();
    final Environment environment = Environment.test(
      fileSystem.currentDirectory,
      fileSystem: fileSystem,
      logger: mockBufferLogger,
      artifacts: mockArtifacts,
      processManager: mockProcessManager,
    );
    final BuildSystem buildSystem = MockBuildSystem();

    expect(
      () => generateLocalizationsSyntheticPackage(
        environment: environment,
        buildSystem: buildSystem,
      ),
      throwsToolExit(message: 'Generating synthetic localizations package has failed.'),
    );
    // [BuildSystem] should have called build with [GenerateLocalizationsTarget].
    verify(buildSystem.build(
      const GenerateLocalizationsTarget(),
      environment,
    )).called(1);
  });

  testWithoutContext('calls buildSystem.build with l10n.yaml synthetic-package: null', () {
    // Project directory setup for gen_l10n logic
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();

    // Add generate:true to pubspec.yaml.
    final File pubspecFile = fileSystem.file('pubspec.yaml')..createSync();
    final String content = pubspecFile.readAsStringSync().replaceFirst(
      '\nflutter:\n',
      '\nflutter:\n  generate: true\n',
    );
    pubspecFile.writeAsStringSync(content);

    // Create an l10n.yaml file
    fileSystem.file('l10n.yaml').writeAsStringSync('synthetic-package: null');

    final FakeProcessManager mockProcessManager = FakeProcessManager.any();
    final BufferLogger mockBufferLogger = BufferLogger.test();
    final Artifacts mockArtifacts = Artifacts.test();
    final Environment environment = Environment.test(
      fileSystem.currentDirectory,
      fileSystem: fileSystem,
      logger: mockBufferLogger,
      artifacts: mockArtifacts,
      processManager: mockProcessManager,
    );
    final BuildSystem buildSystem = MockBuildSystem();

    expect(
      () => generateLocalizationsSyntheticPackage(
        environment: environment,
        buildSystem: buildSystem,
      ),
      throwsToolExit(message: 'Generating synthetic localizations package has failed.'),
    );
    // [BuildSystem] should have called build with [GenerateLocalizationsTarget].
    verify(buildSystem.build(
      const GenerateLocalizationsTarget(),
      environment,
    )).called(1);
  });

  testWithoutContext('does not call buildSystem.build when l10n.yaml is not present', () async {
    // Project directory setup for gen_l10n logic
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();

    // Add generate:true to pubspec.yaml.
    final File pubspecFile = fileSystem.file('pubspec.yaml')..createSync();
    final String content = pubspecFile.readAsStringSync().replaceFirst(
      '\nflutter:\n',
      '\nflutter:\n  generate: true\n',
    );
    pubspecFile.writeAsStringSync(content);

    final FakeProcessManager mockProcessManager = FakeProcessManager.any();
    final BufferLogger mockBufferLogger = BufferLogger.test();
    final Artifacts mockArtifacts = Artifacts.test();
    final Environment environment = Environment.test(
      fileSystem.currentDirectory,
      fileSystem: fileSystem,
      logger: mockBufferLogger,
      artifacts: mockArtifacts,
      processManager: mockProcessManager,
    );
    final BuildSystem buildSystem = MockBuildSystem();

    await generateLocalizationsSyntheticPackage(
      environment: environment,
      buildSystem: buildSystem,
    );
    // [BuildSystem] should not be called with [GenerateLocalizationsTarget].
    verifyNever(buildSystem.build(
      const GenerateLocalizationsTarget(),
      environment,
    ));
  });

  testWithoutContext('does not call buildSystem.build with incorrect l10n.yaml format', () {
    // Project directory setup for gen_l10n logic
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();

    // Add generate:true to pubspec.yaml.
    final File pubspecFile = fileSystem.file('pubspec.yaml')..createSync();
    final String content = pubspecFile.readAsStringSync().replaceFirst(
      '\nflutter:\n',
      '\nflutter:\n  generate: true\n',
    );
    pubspecFile.writeAsStringSync(content);

    // Create an l10n.yaml file
    fileSystem.file('l10n.yaml').writeAsStringSync('helloWorld');

    final FakeProcessManager mockProcessManager = FakeProcessManager.any();
    final BufferLogger mockBufferLogger = BufferLogger.test();
    final Artifacts mockArtifacts = Artifacts.test();
    final Environment environment = Environment.test(
      fileSystem.currentDirectory,
      fileSystem: fileSystem,
      logger: mockBufferLogger,
      artifacts: mockArtifacts,
      processManager: mockProcessManager,
    );
    final BuildSystem buildSystem = MockBuildSystem();

    expect(
      () => generateLocalizationsSyntheticPackage(
        environment: environment,
        buildSystem: buildSystem,
      ),
      throwsToolExit(message: 'to contain a map, instead was helloWorld'),
    );
    // [BuildSystem] should not be called with [GenerateLocalizationsTarget].
    verifyNever(buildSystem.build(
      const GenerateLocalizationsTarget(),
      environment,
    ));
  });

  testWithoutContext('does not call buildSystem.build with non-bool "synthetic-package" value', () {
    // Project directory setup for gen_l10n logic
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();

    // Add generate:true to pubspec.yaml.
    final File pubspecFile = fileSystem.file('pubspec.yaml')..createSync();
    final String content = pubspecFile.readAsStringSync().replaceFirst(
      '\nflutter:\n',
      '\nflutter:\n  generate: true\n',
    );
    pubspecFile.writeAsStringSync(content);

    // Create an l10n.yaml file
    fileSystem.file('l10n.yaml').writeAsStringSync('synthetic-package: nonBoolValue');

    final FakeProcessManager mockProcessManager = FakeProcessManager.any();
    final BufferLogger mockBufferLogger = BufferLogger.test();
    final Artifacts mockArtifacts = Artifacts.test();
    final Environment environment = Environment.test(
      fileSystem.currentDirectory,
      fileSystem: fileSystem,
      logger: mockBufferLogger,
      artifacts: mockArtifacts,
      processManager: mockProcessManager,
    );
    final BuildSystem buildSystem = MockBuildSystem();

    expect(
      () => generateLocalizationsSyntheticPackage(
        environment: environment,
        buildSystem: buildSystem,
      ),
      throwsToolExit(message: 'to have a bool value, instead was "nonBoolValue"'),
    );
    // [BuildSystem] should not be called with [GenerateLocalizationsTarget].
    verifyNever(buildSystem.build(
      const GenerateLocalizationsTarget(),
      environment,
    ));
  });
}

class MockBuildSystem extends Mock implements BuildSystem {}
