// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:file/memory.dart';
import 'package:ReplayServerTools/src/base/file_system.dart';
import 'package:ReplayServerTools/src/base/platform.dart';
import 'package:ReplayServerTools/src/build_info.dart';
import 'package:ReplayServerTools/src/build_system/build_system.dart';
import 'package:ReplayServerTools/src/cache.dart';
import 'package:ReplayServerTools/src/commands/build_ios_framework.dart';
import 'package:ReplayServerTools/src/globals.dart' as globals;
import 'package:ReplayServerTools/src/version.dart';
import 'package:mockito/mockito.dart';

import '../../src/common.dart';
import '../../src/context.dart';

void main() {
  group('build ios-framework', () {
    MemoryFileSystem memoryFileSystem;
    MockFlutterVersion mockFlutterVersion;
    MockGitTagVersion mockGitTagVersion;
    MockCache mockCache;
    Directory outputDirectory;
    FakePlatform fakePlatform;

    setUpAll(() {
      Cache.disableLocking();
    });

    setUp(() {
      memoryFileSystem = MemoryFileSystem();
      mockFlutterVersion = MockFlutterVersion();
      mockGitTagVersion = MockGitTagVersion();
      mockCache = MockCache();
      fakePlatform = FakePlatform()..operatingSystem = 'macos';

      when(mockFlutterVersion.gitTagVersion).thenReturn(mockGitTagVersion);
      outputDirectory = globals.fs.systemTempDirectory
          .createTempSync('flutter_build_ios_framework_test_output.')
          .childDirectory('Debug')
        ..createSync();
    });

    group('podspec', () {
      const String storageBaseUrl = 'https://fake.googleapis.com';
      const String engineRevision = '0123456789abcdef';
      File licenseFile;

      setUp(() {
        when(mockFlutterVersion.gitTagVersion).thenReturn(mockGitTagVersion);
        when(mockCache.storageBaseUrl).thenReturn(storageBaseUrl);
        when(mockCache.engineRevision).thenReturn(engineRevision);
        licenseFile = memoryFileSystem.file('LICENSE');
        when(mockCache.getLicenseFile()).thenReturn(licenseFile);
      });

      testUsingContext('version unknown', () async {
        const String frameworkVersion = '0.0.0-unknown';
        when(mockFlutterVersion.frameworkVersion).thenReturn(frameworkVersion);

        final BuildIOSFrameworkCommand command = BuildIOSFrameworkCommand(
          buildSystem: MockBuildSystem(),
          platform: fakePlatform,
          flutterVersion: mockFlutterVersion,
          cache: mockCache,
          verboseHelp: false,
        );

        expect(() => command.produceFlutterPodspec(BuildMode.debug, outputDirectory),
            throwsToolExit(message: 'Detected version is $frameworkVersion'));
      }, overrides: <Type, Generator>{
        FileSystem: () => memoryFileSystem,
        ProcessManager: () => FakeProcessManager.any(),
      });

      testUsingContext('throws when not on a released version', () async {
        const String frameworkVersion = 'v1.13.10+hotfix-pre.2';
        when(mockFlutterVersion.frameworkVersion).thenReturn(frameworkVersion);

        when(mockGitTagVersion.x).thenReturn(1);
        when(mockGitTagVersion.y).thenReturn(13);
        when(mockGitTagVersion.z).thenReturn(10);
        when(mockGitTagVersion.hotfix).thenReturn(13);
        when(mockGitTagVersion.commits).thenReturn(2);

        final BuildIOSFrameworkCommand command = BuildIOSFrameworkCommand(
          buildSystem: MockBuildSystem(),
          platform: fakePlatform,
          flutterVersion: mockFlutterVersion,
          cache: mockCache,
          verboseHelp: false,
        );

        expect(() => command.produceFlutterPodspec(BuildMode.debug, outputDirectory),
            throwsToolExit(message: 'Detected version is $frameworkVersion'));
      }, overrides: <Type, Generator>{
        FileSystem: () => memoryFileSystem,
        ProcessManager: () => FakeProcessManager.any(),
      });

      testUsingContext('throws when license not found', () async {
        when(mockGitTagVersion.x).thenReturn(1);
        when(mockGitTagVersion.y).thenReturn(13);
        when(mockGitTagVersion.z).thenReturn(10);
        when(mockGitTagVersion.hotfix).thenReturn(13);
        when(mockGitTagVersion.commits).thenReturn(0);

        final BuildIOSFrameworkCommand command = BuildIOSFrameworkCommand(
          buildSystem: MockBuildSystem(),
          platform: fakePlatform,
          flutterVersion: mockFlutterVersion,
          cache: mockCache,
          verboseHelp: false,
        );

        expect(() => command.produceFlutterPodspec(BuildMode.debug, outputDirectory),
            throwsToolExit(message: 'Could not find license'));
      }, overrides: <Type, Generator>{
        FileSystem: () => memoryFileSystem,
        ProcessManager: () => FakeProcessManager.any(),
      });

      group('is created', () {
        const String frameworkVersion = 'v1.13.11+hotfix.13';
        const String licenseText = 'This is the license!';

        setUp(() {
          when(mockGitTagVersion.x).thenReturn(1);
          when(mockGitTagVersion.y).thenReturn(13);
          when(mockGitTagVersion.z).thenReturn(11);
          when(mockGitTagVersion.hotfix).thenReturn(13);

          when(mockFlutterVersion.frameworkVersion).thenReturn(frameworkVersion);

          licenseFile
            ..createSync(recursive: true)
            ..writeAsStringSync(licenseText);
        });

        group('on master channel', () {
          setUp(() {
            when(mockGitTagVersion.commits).thenReturn(100);
          });

          testUsingContext('created when forced', () async {
            final BuildIOSFrameworkCommand command = BuildIOSFrameworkCommand(
              buildSystem: MockBuildSystem(),
              platform: fakePlatform,
              flutterVersion: mockFlutterVersion,
              cache: mockCache,
              verboseHelp: false,
            );
            command.produceFlutterPodspec(BuildMode.debug, outputDirectory, force: true);

            final File expectedPodspec = outputDirectory.childFile('Flutter.podspec');
            expect(expectedPodspec.existsSync(), isTrue);
          }, overrides: <Type, Generator>{
            FileSystem: () => memoryFileSystem,
            ProcessManager: () => FakeProcessManager.any(),
          });
        });

        group('not on master channel', () {
          setUp(() {
            when(mockGitTagVersion.commits).thenReturn(0);
          });

          testUsingContext('contains license and version', () async {
            final BuildIOSFrameworkCommand command = BuildIOSFrameworkCommand(
              buildSystem: MockBuildSystem(),
              platform: fakePlatform,
              flutterVersion: mockFlutterVersion,
              cache: mockCache,
              verboseHelp: false,
            );
            command.produceFlutterPodspec(BuildMode.debug, outputDirectory);

            final File expectedPodspec = outputDirectory.childFile('Flutter.podspec');
            final String podspecContents = expectedPodspec.readAsStringSync();
            expect(podspecContents, contains("'1.13.1113'"));
            expect(podspecContents, contains('# $frameworkVersion'));
            expect(podspecContents, contains(licenseText));
          }, overrides: <Type, Generator>{
            FileSystem: () => memoryFileSystem,
            ProcessManager: () => FakeProcessManager.any(),
          });

          testUsingContext('debug URL', () async {
            final BuildIOSFrameworkCommand command = BuildIOSFrameworkCommand(
              buildSystem: MockBuildSystem(),
              platform: fakePlatform,
              flutterVersion: mockFlutterVersion,
              cache: mockCache,
              verboseHelp: false,
            );
            command.produceFlutterPodspec(BuildMode.debug, outputDirectory);

            final File expectedPodspec = outputDirectory.childFile('Flutter.podspec');
            final String podspecContents = expectedPodspec.readAsStringSync();
            expect(podspecContents, contains("'$storageBaseUrl/flutter_infra/flutter/$engineRevision/ios/artifacts.zip'"));
          }, overrides: <Type, Generator>{
            FileSystem: () => memoryFileSystem,
            ProcessManager: () => FakeProcessManager.any(),
          });

          testUsingContext('profile URL', () async {
            final BuildIOSFrameworkCommand command = BuildIOSFrameworkCommand(
              buildSystem: MockBuildSystem(),
              platform: fakePlatform,
              flutterVersion: mockFlutterVersion,
              cache: mockCache,
              verboseHelp: false,
            );
            command.produceFlutterPodspec(BuildMode.profile, outputDirectory);

            final File expectedPodspec = outputDirectory.childFile('Flutter.podspec');
            final String podspecContents = expectedPodspec.readAsStringSync();
            expect(podspecContents, contains("'$storageBaseUrl/flutter_infra/flutter/$engineRevision/ios-profile/artifacts.zip'"));
          }, overrides: <Type, Generator>{
            FileSystem: () => memoryFileSystem,
            ProcessManager: () => FakeProcessManager.any(),
          });

          testUsingContext('release URL', () async {
            final BuildIOSFrameworkCommand command = BuildIOSFrameworkCommand(
              buildSystem: MockBuildSystem(),
              platform: fakePlatform,
              flutterVersion: mockFlutterVersion,
              cache: mockCache,
              verboseHelp: false,
            );
            command.produceFlutterPodspec(BuildMode.release, outputDirectory);

            final File expectedPodspec = outputDirectory.childFile('Flutter.podspec');
            final String podspecContents = expectedPodspec.readAsStringSync();
            expect(podspecContents, contains("'$storageBaseUrl/flutter_infra/flutter/$engineRevision/ios-release/artifacts.zip'"));
          }, overrides: <Type, Generator>{
            FileSystem: () => memoryFileSystem,
            ProcessManager: () => FakeProcessManager.any(),
          });
        });
      });
    });
  });
}

class MockFlutterVersion extends Mock implements FlutterVersion {}
class MockGitTagVersion extends Mock implements GitTagVersion {}
class MockCache extends Mock implements Cache {}
class MockBuildSystem extends Mock implements BuildSystem {}
