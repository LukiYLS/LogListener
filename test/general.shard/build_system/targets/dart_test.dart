// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:ReplayServerTools/src/artifacts.dart';
import 'package:ReplayServerTools/src/base/file_system.dart';
import 'package:ReplayServerTools/src/base/logger.dart';
import 'package:ReplayServerTools/src/base/platform.dart';
import 'package:ReplayServerTools/src/build_info.dart';
import 'package:ReplayServerTools/src/build_system/build_system.dart';
import 'package:ReplayServerTools/src/build_system/exceptions.dart';
import 'package:ReplayServerTools/src/build_system/targets/common.dart';
import 'package:ReplayServerTools/src/build_system/targets/ios.dart';
import 'package:ReplayServerTools/src/compile.dart';

import '../../../src/common.dart';
import '../../../src/context.dart';
import '../../../src/fake_process_manager.dart';

const String kBoundaryKey = '4d2d9609-c662-4571-afde-31410f96caa6';
const String kElfAot = '--snapshot_kind=app-aot-elf';
const String kAssemblyAot = '--snapshot_kind=app-aot-assembly';

final Platform macPlatform = FakePlatform(operatingSystem: 'macos', environment: <String, String>{});
void main() {
  FakeProcessManager processManager;
  Environment androidEnvironment;
  Environment iosEnvironment;
  Artifacts artifacts;
  FileSystem fileSystem;
  Logger logger;

  setUp(() {
    processManager = FakeProcessManager.list(<FakeCommand>[]);
    logger = BufferLogger.test();
    artifacts = Artifacts.test();
    fileSystem = MemoryFileSystem.test(style: FileSystemStyle.posix);
    androidEnvironment = Environment.test(
      fileSystem.currentDirectory,
      defines: <String, String>{
        kBuildMode: getNameForBuildMode(BuildMode.profile),
        kTargetPlatform: getNameForTargetPlatform(TargetPlatform.android_arm),
      },
      inputs: <String, String>{},
      artifacts: artifacts,
      processManager: processManager,
      fileSystem: fileSystem,
      logger: logger,
    );
    androidEnvironment.buildDir.createSync(recursive: true);
    iosEnvironment = Environment.test(
      fileSystem.currentDirectory,
      defines: <String, String>{
        kBuildMode: getNameForBuildMode(BuildMode.profile),
        kTargetPlatform: getNameForTargetPlatform(TargetPlatform.ios),
      },
      inputs: <String, String>{},
      artifacts: artifacts,
      processManager: processManager,
      fileSystem: fileSystem,
      logger: logger,
    );
    iosEnvironment.buildDir.createSync(recursive: true);
  });

  testWithoutContext('KernelSnapshot throws error if missing build mode', () async {
    androidEnvironment.defines.remove(kBuildMode);
    expect(
      const KernelSnapshot().build(androidEnvironment),
      throwsA(isA<MissingDefineException>()));
  });

  testWithoutContext('KernelSnapshot handles null result from kernel compilation', () async {
    fileSystem.file('.packages').writeAsStringSync('\n');
    final String build = androidEnvironment.buildDir.path;
    processManager.addCommands(<FakeCommand>[
      FakeCommand(command: <String>[
        artifacts.getArtifactPath(Artifact.engineDartBinary),
        '--disable-dart-dev',
        artifacts.getArtifactPath(Artifact.frontendServerSnapshotForEngineDartSdk),
        '--sdk-root',
        artifacts.getArtifactPath(
          Artifact.flutterPatchedSdkPath,
          platform: TargetPlatform.android_arm,
          mode: BuildMode.profile,
        ) + '/',
        '--target=flutter',
        '-Ddart.developer.causal_async_stacks=false',
        ...buildModeOptions(BuildMode.profile),
        '--aot',
        '--tfa',
        '--packages',
        '/.packages',
        '--output-dill',
        '$build/app.dill',
        '--depfile',
        '$build/kernel_snapshot.d',
        '/lib/main.dart',
      ], exitCode: 1),
    ]);

    await expectLater(() => const KernelSnapshot().build(androidEnvironment),
      throwsA(isA<Exception>()));
    expect(processManager.hasRemainingExpectations, false);
  });

  testWithoutContext('KernelSnapshot does not use track widget creation on profile builds', () async {
    fileSystem.file('.packages').writeAsStringSync('\n');
    final String build = androidEnvironment.buildDir.path;
    processManager.addCommands(<FakeCommand>[
      FakeCommand(command: <String>[
        artifacts.getArtifactPath(Artifact.engineDartBinary),
        '--disable-dart-dev',
        artifacts.getArtifactPath(Artifact.frontendServerSnapshotForEngineDartSdk),
        '--sdk-root',
        artifacts.getArtifactPath(
          Artifact.flutterPatchedSdkPath,
          platform: TargetPlatform.android_arm,
          mode: BuildMode.profile,
        ) + '/',
        '--target=flutter',
        '-Ddart.developer.causal_async_stacks=false',
        ...buildModeOptions(BuildMode.profile),
        '--aot',
        '--tfa',
        '--packages',
        '/.packages',
        '--output-dill',
        '$build/app.dill',
        '--depfile',
        '$build/kernel_snapshot.d',
        '/lib/main.dart',
      ], stdout: 'result $kBoundaryKey\n$kBoundaryKey\n$kBoundaryKey $build/app.dill 0\n'),
    ]);

    await const KernelSnapshot().build(androidEnvironment);

    expect(processManager.hasRemainingExpectations, false);
  });

  testWithoutContext('KernelSnapshot correctly handles an empty string in ExtraFrontEndOptions', () async {
    fileSystem.file('.packages').writeAsStringSync('\n');
    final String build = androidEnvironment.buildDir.path;
    processManager.addCommands(<FakeCommand>[
      FakeCommand(command: <String>[
        artifacts.getArtifactPath(Artifact.engineDartBinary),
        '--disable-dart-dev',
        artifacts.getArtifactPath(Artifact.frontendServerSnapshotForEngineDartSdk),
        '--sdk-root',
        artifacts.getArtifactPath(
          Artifact.flutterPatchedSdkPath,
          platform: TargetPlatform.android_arm,
          mode: BuildMode.profile,
        ) + '/',
        '--target=flutter',
        '-Ddart.developer.causal_async_stacks=false',
        ...buildModeOptions(BuildMode.profile),
        '--aot',
        '--tfa',
        '--packages',
        '/.packages',
        '--output-dill',
        '$build/app.dill',
        '--depfile',
        '$build/kernel_snapshot.d',
        '/lib/main.dart',
      ], stdout: 'result $kBoundaryKey\n$kBoundaryKey\n$kBoundaryKey $build/app.dill 0\n'),
    ]);

    await const KernelSnapshot()
      .build(androidEnvironment..defines[kExtraFrontEndOptions] = '');

    expect(processManager.hasRemainingExpectations, false);
  });

  testWithoutContext('KernelSnapshot correctly forwards ExtraFrontEndOptions', () async {
    fileSystem.file('.packages').writeAsStringSync('\n');
    final String build = androidEnvironment.buildDir.path;
    processManager.addCommands(<FakeCommand>[
      FakeCommand(command: <String>[
        artifacts.getArtifactPath(Artifact.engineDartBinary),
        '--disable-dart-dev',
        artifacts.getArtifactPath(Artifact.frontendServerSnapshotForEngineDartSdk),
        '--sdk-root',
        artifacts.getArtifactPath(
          Artifact.flutterPatchedSdkPath,
          platform: TargetPlatform.android_arm,
          mode: BuildMode.profile,
        ) + '/',
        '--target=flutter',
        '-Ddart.developer.causal_async_stacks=false',
        ...buildModeOptions(BuildMode.profile),
        '--aot',
        '--tfa',
        '--packages',
        '/.packages',
        '--output-dill',
        '$build/app.dill',
        '--depfile',
        '$build/kernel_snapshot.d',
        'foo',
        'bar',
        '/lib/main.dart',
      ], stdout: 'result $kBoundaryKey\n$kBoundaryKey\n$kBoundaryKey $build/app.dill 0\n'),
    ]);

    await const KernelSnapshot()
      .build(androidEnvironment..defines[kExtraFrontEndOptions] = 'foo,bar');

    expect(processManager.hasRemainingExpectations, false);
  });

  testWithoutContext('KernelSnapshot can disable track-widget-creation on debug builds', () async {
    fileSystem.file('.packages').writeAsStringSync('\n');
    final String build = androidEnvironment.buildDir.path;
    processManager.addCommands(<FakeCommand>[
      FakeCommand(command: <String>[
        artifacts.getArtifactPath(Artifact.engineDartBinary),
        '--disable-dart-dev',
        artifacts.getArtifactPath(Artifact.frontendServerSnapshotForEngineDartSdk),
        '--sdk-root',
        artifacts.getArtifactPath(
          Artifact.flutterPatchedSdkPath,
          platform: TargetPlatform.android_arm,
          mode: BuildMode.debug,
        ) + '/',
        '--target=flutter',
        '-Ddart.developer.causal_async_stacks=true',
        ...buildModeOptions(BuildMode.debug),
        '--no-link-platform',
        '--packages',
        '/.packages',
        '--output-dill',
        '$build/app.dill',
        '--depfile',
        '$build/kernel_snapshot.d',
        '/lib/main.dart',
      ], stdout: 'result $kBoundaryKey\n$kBoundaryKey\n$kBoundaryKey $build/app.dill 0\n'),
    ]);

    await const KernelSnapshot().build(androidEnvironment
      ..defines[kBuildMode] = getNameForBuildMode(BuildMode.debug)
      ..defines[kTrackWidgetCreation] = 'false');

    expect(processManager.hasRemainingExpectations, false);
  });

  testWithoutContext('KernelSnapshot forces platform linking on debug for darwin target platforms', () async {
    fileSystem.file('.packages').writeAsStringSync('\n');
    final String build = androidEnvironment.buildDir.path;
    processManager.addCommands(<FakeCommand>[
      FakeCommand(command: <String>[
        artifacts.getArtifactPath(Artifact.engineDartBinary),
        '--disable-dart-dev',
        artifacts.getArtifactPath(Artifact.frontendServerSnapshotForEngineDartSdk),
        '--sdk-root',
        artifacts.getArtifactPath(
          Artifact.flutterPatchedSdkPath,
          platform: TargetPlatform.darwin_x64,
          mode: BuildMode.debug,
        ) + '/',
        '--target=flutter',
        '-Ddart.developer.causal_async_stacks=true',
        ...buildModeOptions(BuildMode.debug),
        '--packages',
        '/.packages',
        '--output-dill',
        '$build/app.dill',
        '--depfile',
        '$build/kernel_snapshot.d',
        '/lib/main.dart',
      ], stdout: 'result $kBoundaryKey\n$kBoundaryKey\n$kBoundaryKey $build/app.dill 0\n'),
    ]);

    await const KernelSnapshot().build(androidEnvironment
      ..defines[kTargetPlatform]  = getNameForTargetPlatform(TargetPlatform.darwin_x64)
      ..defines[kBuildMode] = getNameForBuildMode(BuildMode.debug)
      ..defines[kTrackWidgetCreation] = 'false'
    );

    expect(processManager.hasRemainingExpectations, false);
  });

  testWithoutContext('KernelSnapshot does use track widget creation on debug builds', () async {
    fileSystem.file('.packages').writeAsStringSync('\n');
    final Environment testEnvironment = Environment.test(
      fileSystem.currentDirectory,
      defines: <String, String>{
        kBuildMode: getNameForBuildMode(BuildMode.debug),
        kTargetPlatform: getNameForTargetPlatform(TargetPlatform.android_arm),
      },
      processManager: processManager,
      artifacts: artifacts,
      fileSystem: fileSystem,
      logger: logger,
    );
    final String build = testEnvironment.buildDir.path;
    processManager.addCommands(<FakeCommand>[
      FakeCommand(command: <String>[
        artifacts.getArtifactPath(Artifact.engineDartBinary),
        '--disable-dart-dev',
        artifacts.getArtifactPath(Artifact.frontendServerSnapshotForEngineDartSdk),
        '--sdk-root',
        artifacts.getArtifactPath(
          Artifact.flutterPatchedSdkPath,
          platform: TargetPlatform.android_arm,
          mode: BuildMode.debug,
        ) + '/',
        '--target=flutter',
        '-Ddart.developer.causal_async_stacks=true',
        ...buildModeOptions(BuildMode.debug),
        '--track-widget-creation',
        '--no-link-platform',
        '--packages',
        '/.packages',
        '--output-dill',
        '$build/app.dill',
        '--depfile',
        '$build/kernel_snapshot.d',
        '/lib/main.dart',
      ], stdout: 'result $kBoundaryKey\n$kBoundaryKey\n$kBoundaryKey /build/653e11a8e6908714056a57cd6b4f602a/app.dill 0\n'),
    ]);

    await const KernelSnapshot().build(testEnvironment);

    expect(processManager.hasRemainingExpectations, false);
  });

  testUsingContext('AotElfProfile Produces correct output directory', () async {
    final String build = androidEnvironment.buildDir.path;
    processManager.addCommands(<FakeCommand>[
      FakeCommand(command: <String>[
        artifacts.getArtifactPath(
          Artifact.genSnapshot,
          platform: TargetPlatform.android_arm,
          mode: BuildMode.profile,
        ),
        '--deterministic',
        kElfAot,
        '--elf=$build/app.so',
        '--strip',
        '--no-sim-use-hardfp',
        '--no-use-integer-division',
        '--no-causal-async-stacks',
        '--lazy-async-stacks',
        '$build/app.dill',
      ])
    ]);
    androidEnvironment.buildDir.childFile('app.dill').createSync(recursive: true);

    await const AotElfProfile(TargetPlatform.android_arm).build(androidEnvironment);

    expect(processManager.hasRemainingExpectations, false);
  });

  testUsingContext('AotElfRelease configures gen_snapshot with code size directory', () async {
    androidEnvironment.defines[kCodeSizeDirectory] = 'code_size_1';
    final String build = androidEnvironment.buildDir.path;
    processManager.addCommands(<FakeCommand>[
      FakeCommand(command: <String>[
        artifacts.getArtifactPath(
          Artifact.genSnapshot,
          platform: TargetPlatform.android_arm,
          mode: BuildMode.profile,
        ),
        '--deterministic',
        '--write-v8-snapshot-profile-to=code_size_1/snapshot.android-arm.json',
        '--trace-precompiler-to=code_size_1/trace.android-arm.json',
        kElfAot,
        '--elf=$build/app.so',
        '--strip',
        '--no-sim-use-hardfp',
        '--no-use-integer-division',
        '--no-causal-async-stacks',
        '--lazy-async-stacks',
        '$build/app.dill',
      ])
    ]);
    androidEnvironment.buildDir.childFile('app.dill').createSync(recursive: true);

    await const AotElfRelease(TargetPlatform.android_arm).build(androidEnvironment);

    expect(processManager.hasRemainingExpectations, false);
  });

  testUsingContext('AotElfProfile throws error if missing build mode', () async {
    androidEnvironment.defines.remove(kBuildMode);

    expect(const AotElfProfile(TargetPlatform.android_arm).build(androidEnvironment),
      throwsA(isA<MissingDefineException>()));
  });

  testUsingContext('AotElfProfile throws error if missing target platform', () async {
    androidEnvironment.defines.remove(kTargetPlatform);

    expect(const AotElfProfile(TargetPlatform.android_arm).build(androidEnvironment),
      throwsA(isA<MissingDefineException>()));
  });

  testUsingContext('AotAssemblyProfile throws error if missing build mode', () async {
    iosEnvironment.defines.remove(kBuildMode);

    expect(const AotAssemblyProfile().build(iosEnvironment),
      throwsA(isA<MissingDefineException>()));
  }, overrides: <Type, Generator>{
    Platform: () => macPlatform,
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
  });


  testUsingContext('AotAssemblyProfile throws error if missing target platform', () async {
    iosEnvironment.defines.remove(kTargetPlatform);

    expect(const AotAssemblyProfile().build(iosEnvironment),
      throwsA(isA<MissingDefineException>()));
  }, overrides: <Type, Generator>{
    Platform: () => macPlatform,
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
  });

  testUsingContext('AotAssemblyProfile throws error if built for non-iOS platform', () async {
    expect(const AotAssemblyProfile().build(androidEnvironment),
      throwsA(isA<Exception>()));
  }, overrides: <Type, Generator>{
    Platform: () => macPlatform,
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
  });

  testUsingContext('AotAssemblyProfile generates multiple arches and lipos together', () async {
    final String build = iosEnvironment.buildDir.path;
    processManager.addCommands(<FakeCommand>[
      FakeCommand(command: <String>[
        // This path is not known by the cache due to the iOS gen_snapshot split.
        'Artifact.genSnapshot.TargetPlatform.ios.profile_armv7',
        '--deterministic',
        kAssemblyAot,
        '--assembly=$build/armv7/snapshot_assembly.S',
        '--strip',
        '--no-sim-use-hardfp',
        '--no-use-integer-division',
        '--no-causal-async-stacks',
        '--lazy-async-stacks',
        '$build/app.dill',
      ]),
      FakeCommand(command: <String>[
        // This path is not known by the cache due to the iOS gen_snapshot split.
        'Artifact.genSnapshot.TargetPlatform.ios.profile_arm64',
        '--deterministic',
        kAssemblyAot,
        '--assembly=$build/arm64/snapshot_assembly.S',
        '--strip',
        '--no-causal-async-stacks',
        '--lazy-async-stacks',
        '$build/app.dill',
      ]),
      const FakeCommand(
        command: <String>[
          'sysctl',
          'hw.optional.arm64',
        ],
        exitCode: 1,
      ),
      const FakeCommand(command: <String>[
        'xcrun',
        '--sdk',
        'iphoneos',
        '--show-sdk-path',
      ]),
      const FakeCommand(command: <String>[
        'xcrun',
        '--sdk',
        'iphoneos',
        '--show-sdk-path',
      ]),
      FakeCommand(command: <String>[
        'xcrun',
        'cc',
        '-arch',
        'armv7',
        '-isysroot',
        '',
        '-c',
        '$build/armv7/snapshot_assembly.S',
        '-o',
        '$build/armv7/snapshot_assembly.o',
      ]),
      FakeCommand(command: <String>[
        'xcrun',
        'cc',
        '-arch',
        'arm64',
        '-isysroot',
        '',
        '-c',
        '$build/arm64/snapshot_assembly.S',
        '-o',
        '$build/arm64/snapshot_assembly.o',
      ]),
      FakeCommand(command: <String>[
        'xcrun',
        'clang',
        '-arch',
        'armv7',
        '-miphoneos-version-min=8.0',
        '-dynamiclib',
        '-Xlinker',
        '-rpath',
        '-Xlinker',
        '@executable_path/Frameworks',
        '-Xlinker',
        '-rpath',
        '-Xlinker',
        '@loader_path/Frameworks',
        '-install_name',
        '@rpath/App.framework/App',
        '-isysroot',
        '',
        '-o',
        '$build/armv7/App.framework/App',
        '$build/armv7/snapshot_assembly.o',
      ]),
      FakeCommand(command: <String>[
        'xcrun',
        'clang',
        '-arch',
        'arm64',
        '-miphoneos-version-min=8.0',
        '-dynamiclib',
        '-Xlinker',
        '-rpath',
        '-Xlinker',
        '@executable_path/Frameworks',
        '-Xlinker',
        '-rpath',
        '-Xlinker',
        '@loader_path/Frameworks',
        '-install_name',
        '@rpath/App.framework/App',
        '-isysroot',
        '',
        '-o',
        '$build/arm64/App.framework/App',
        '$build/arm64/snapshot_assembly.o',
      ]),
      FakeCommand(command: <String>[
        'lipo',
        '$build/armv7/App.framework/App',
        '$build/arm64/App.framework/App',
        '-create',
        '-output',
        '$build/App.framework/App',
      ]),
    ]);
    iosEnvironment.defines[kIosArchs] ='armv7 arm64';

    await const AotAssemblyProfile().build(iosEnvironment);

    expect(processManager.hasRemainingExpectations, false);
  }, overrides: <Type, Generator>{
    Platform: () => macPlatform,
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
  });

  testUsingContext('AotAssemblyProfile with bitcode sends correct argument to snapshotter (one arch)', () async {
    iosEnvironment.defines[kIosArchs] = 'arm64';
    iosEnvironment.defines[kBitcodeFlag] = 'true';
    final String build = iosEnvironment.buildDir.path;
    processManager.addCommands(<FakeCommand>[
      FakeCommand(command: <String>[
        // This path is not known by the cache due to the iOS gen_snapshot split.
        'Artifact.genSnapshot.TargetPlatform.ios.profile_arm64',
        '--deterministic',
        kAssemblyAot,
        '--assembly=$build/arm64/snapshot_assembly.S',
        '--strip',
        '--no-causal-async-stacks',
        '--lazy-async-stacks',
        '$build/app.dill',
      ]),
      const FakeCommand(
        command: <String>[
          'sysctl',
          'hw.optional.arm64',
        ],
        exitCode: 1,
      ),
      const FakeCommand(command: <String>[
        'xcrun',
        '--sdk',
        'iphoneos',
        '--show-sdk-path',
      ]),
      FakeCommand(command: <String>[
        'xcrun',
        'cc',
        '-arch',
        'arm64',
        '-isysroot',
        '',
        // Contains bitcode flag.
        '-fembed-bitcode',
        '-c',
        '$build/arm64/snapshot_assembly.S',
        '-o',
        '$build/arm64/snapshot_assembly.o',
      ]),
      FakeCommand(command: <String>[
        'xcrun',
        'clang',
        '-arch',
        'arm64',
        '-miphoneos-version-min=8.0',
        '-dynamiclib',
        '-Xlinker',
        '-rpath',
        '-Xlinker',
        '@executable_path/Frameworks',
        '-Xlinker',
        '-rpath',
        '-Xlinker',
        '@loader_path/Frameworks',
        '-install_name',
        '@rpath/App.framework/App',
        // Contains bitcode flag.
        '-fembed-bitcode',
        '-isysroot',
        '',
        '-o',
        '$build/arm64/App.framework/App',
        '$build/arm64/snapshot_assembly.o',
      ]),
      FakeCommand(command: <String>[
        'lipo',
        '$build/arm64/App.framework/App',
        '-create',
        '-output',
        '$build/App.framework/App',
      ]),
    ]);

    await const AotAssemblyProfile().build(iosEnvironment);

    expect(processManager.hasRemainingExpectations, false);
  }, overrides: <Type, Generator>{
    Platform: () => macPlatform,
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
  });

  testUsingContext('AotAssemblyRelease configures gen_snapshot with code size directory', () async {
    iosEnvironment.defines[kCodeSizeDirectory] = 'code_size_1';
    iosEnvironment.defines[kIosArchs] = 'arm64';
    iosEnvironment.defines[kBitcodeFlag] = 'true';
    final String build = iosEnvironment.buildDir.path;
    processManager.addCommands(<FakeCommand>[
      FakeCommand(command: <String>[
        // This path is not known by the cache due to the iOS gen_snapshot split.
        'Artifact.genSnapshot.TargetPlatform.ios.profile_arm64',
        '--deterministic',
        '--write-v8-snapshot-profile-to=code_size_1/snapshot.arm64.json',
        '--trace-precompiler-to=code_size_1/trace.arm64.json',
        kAssemblyAot,
        '--assembly=$build/arm64/snapshot_assembly.S',
        '--strip',
        '--no-causal-async-stacks',
        '--lazy-async-stacks',
        '$build/app.dill',
      ]),
      const FakeCommand(
        command: <String>[
          'sysctl',
          'hw.optional.arm64',
        ],
        exitCode: 1,
      ),
      const FakeCommand(command: <String>[
        'xcrun',
        '--sdk',
        'iphoneos',
        '--show-sdk-path',
      ]),
      FakeCommand(command: <String>[
        'xcrun',
        'cc',
        '-arch',
        'arm64',
        '-isysroot',
        '',
        // Contains bitcode flag.
        '-fembed-bitcode',
        '-c',
        '$build/arm64/snapshot_assembly.S',
        '-o',
        '$build/arm64/snapshot_assembly.o',
      ]),
      FakeCommand(command: <String>[
        'xcrun',
        'clang',
        '-arch',
        'arm64',
        '-miphoneos-version-min=8.0',
        '-dynamiclib',
        '-Xlinker',
        '-rpath',
        '-Xlinker',
        '@executable_path/Frameworks',
        '-Xlinker',
        '-rpath',
        '-Xlinker',
        '@loader_path/Frameworks',
        '-install_name',
        '@rpath/App.framework/App',
        // Contains bitcode flag.
        '-fembed-bitcode',
        '-isysroot',
        '',
        '-o',
        '$build/arm64/App.framework/App',
        '$build/arm64/snapshot_assembly.o',
      ]),
      FakeCommand(command: <String>[
        'lipo',
        '$build/arm64/App.framework/App',
        '-create',
        '-output',
        '$build/App.framework/App',
      ]),
    ]);

    await const AotAssemblyProfile().build(iosEnvironment);

    expect(processManager.hasRemainingExpectations, false);
  }, overrides: <Type, Generator>{
    Platform: () => macPlatform,
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
  });

  testUsingContext('kExtraGenSnapshotOptions passes values to gen_snapshot', () async {
    androidEnvironment.defines[kExtraGenSnapshotOptions] = 'foo,bar,baz=2';
    androidEnvironment.defines[kBuildMode] = getNameForBuildMode(BuildMode.profile);
    final String build = androidEnvironment.buildDir.path;

    processManager.addCommands(<FakeCommand>[
      FakeCommand(command: <String>[
        artifacts.getArtifactPath(
          Artifact.genSnapshot,
          platform: TargetPlatform.android_arm,
          mode: BuildMode.profile,
        ),
        '--deterministic',
        'foo',
        'bar',
        'baz=2',
        kElfAot,
        '--elf=$build/app.so',
        '--strip',
        '--no-sim-use-hardfp',
        '--no-use-integer-division',
        '--no-causal-async-stacks',
        '--lazy-async-stacks',
        '$build/app.dill',
      ]),
    ]);

    await const AotElfRelease(TargetPlatform.android_arm).build(androidEnvironment);

    expect(processManager.hasRemainingExpectations, false);
  });
}
