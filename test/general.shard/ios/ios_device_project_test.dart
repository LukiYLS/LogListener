// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:ReplayServerTools/src/artifacts.dart';
import 'package:ReplayServerTools/src/base/file_system.dart';
import 'package:ReplayServerTools/src/base/logger.dart';
import 'package:ReplayServerTools/src/base/platform.dart';
import 'package:ReplayServerTools/src/build_info.dart';
import 'package:ReplayServerTools/src/ios/devices.dart';
import 'package:ReplayServerTools/src/ios/iproxy.dart';
import 'package:ReplayServerTools/src/project.dart';
import 'package:mockito/mockito.dart';
import 'package:vm_service/vm_service.dart';

import '../../src/common.dart';
import '../../src/context.dart';

// FlutterProject still depends on context.
void main() {
  FileSystem fileSystem;

  // This setup is required to inject the context.
  setUp(() {
    fileSystem = MemoryFileSystem.test();
  });

  testUsingContext('IOSDevice.isSupportedForProject is true on module project', () async {
    fileSystem.file('pubspec.yaml')
      ..createSync()
      ..writeAsStringSync(r'''
name: example
flutter:
  module: {}
  ''');
    fileSystem.file('.packages').writeAsStringSync('\n');
    final FlutterProject flutterProject =
      FlutterProject.fromDirectory(fileSystem.currentDirectory);
    final IOSDevice device = setUpIOSDevice(fileSystem);

    expect(device.isSupportedForProject(flutterProject), true);
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => FakeProcessManager.any(),
  });

  testUsingContext('IOSDevice.isSupportedForProject is true with editable host app', () async {
    final FileSystem fileSystem = MemoryFileSystem.test();
    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('.packages').writeAsStringSync('\n');
    fileSystem.directory('ios').createSync();
    final FlutterProject flutterProject =
      FlutterProject.fromDirectory(fileSystem.currentDirectory);
    final IOSDevice device = setUpIOSDevice(fileSystem);

    expect(device.isSupportedForProject(flutterProject), true);
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => FakeProcessManager.any(),
  });


  testUsingContext('IOSDevice.isSupportedForProject is false with no host app and no module', () async {
    final FileSystem fileSystem = MemoryFileSystem.test();
    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('.packages').writeAsStringSync('\n');
    final FlutterProject flutterProject =
      FlutterProject.fromDirectory(fileSystem.currentDirectory);
    final IOSDevice device = setUpIOSDevice(fileSystem);

    expect(device.isSupportedForProject(flutterProject), false);
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => FakeProcessManager.any(),
  });
}

IOSDevice setUpIOSDevice(FileSystem fileSystem) {
  final MockArtifacts artifacts = MockArtifacts();
  when(artifacts.getArtifactPath(Artifact.iosDeploy, platform: anyNamed('platform')))
    .thenReturn('ios-deploy');
  return IOSDevice(
    'test',
    fileSystem: fileSystem,
    logger: BufferLogger.test(),
    iosDeploy: null, // not used in this test
    iMobileDevice: null, // not used in this test
    platform: FakePlatform(operatingSystem: 'macos'),
    name: 'iPhone 1',
    sdkVersion: '13.3',
    cpuArchitecture: DarwinArch.arm64,
    iProxy: IProxy.test(logger: BufferLogger.test(), processManager: FakeProcessManager.any()),
    interfaceType: IOSDeviceInterface.usb,
    vmServiceConnectUri: (String string, {Log log}) async => MockVmService(),
  );
}

class MockArtifacts extends Mock implements Artifacts {}
class MockVmService extends Mock implements VmService {}
