// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:ReplayServerTools/src/base/logger.dart';
import 'package:ReplayServerTools/src/base/platform.dart';
import 'package:ReplayServerTools/src/cache.dart';
import 'package:ReplayServerTools/src/commands/precache.dart';
import 'package:ReplayServerTools/src/runner/flutter_command.dart';
import 'package:mockito/mockito.dart';

import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/mocks.dart';
import '../../src/testbed.dart';

void main() {
  MockCache cache;
  Set<DevelopmentArtifact> artifacts;

  setUp(() {
    cache = MockCache();
    // Release lock between test cases.
    Cache.releaseLock();

    when(cache.isUpToDate()).thenReturn(false);
    when(cache.updateAll(any)).thenAnswer((Invocation invocation) {
      artifacts = invocation.positionalArguments.first as Set<DevelopmentArtifact>;
      return Future<void>.value(null);
    });
  });

  testUsingContext('precache should acquire lock', () async {
    final Platform platform = FakePlatform(environment: <String, String>{});
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      platform: platform,
      featureFlags: TestFeatureFlags(),
    );
    applyMocksToCommand(command);
    await createTestCommandRunner(command).run(const <String>['precache']);

    expect(Cache.isLocked(), isTrue);
    // Do not throw StateError, lock is acquired.
    expect(() => Cache.checkLockAcquired(platform), returnsNormally);
  });

  testUsingContext('precache should not re-entrantly acquire lock', () async {
    final Platform platform = FakePlatform(
      operatingSystem: 'windows',
      environment: <String, String>{
        'FLUTTER_ROOT': 'flutter',
        'FLUTTER_ALREADY_LOCKED': 'true',
      },
    );
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(),
      platform: platform,
    );
    applyMocksToCommand(command);
    await createTestCommandRunner(command).run(const <String>['precache']);

    expect(Cache.isLocked(), isFalse);
    // Do not throw StateError, acquired reentrantly with FLUTTER_ALREADY_LOCKED.
    expect(() => Cache.checkLockAcquired(platform), returnsNormally);
  });

  testUsingContext('precache downloads web artifacts on dev branch when feature is enabled.', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(isWebEnabled: true),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);
    await createTestCommandRunner(command).run(const <String>['precache', '--web', '--no-android', '--no-ios']);

    expect(artifacts, unorderedEquals(<DevelopmentArtifact>{
      DevelopmentArtifact.universal,
      DevelopmentArtifact.web,
    }));
  });

  testUsingContext('precache does not download web artifacts on dev branch when feature is enabled.', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(isWebEnabled: false),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);
    await createTestCommandRunner(command).run(const <String>['precache', '--web', '--no-android', '--no-ios']);

    expect(artifacts, unorderedEquals(<DevelopmentArtifact>{
      DevelopmentArtifact.universal,
    }));
  });

  testUsingContext('precache downloads macOS artifacts on dev branch when macOS is enabled.', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(isMacOSEnabled: true),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);
    await createTestCommandRunner(command).run(const <String>['precache', '--macos', '--no-android', '--no-ios']);

    expect(artifacts, unorderedEquals(<DevelopmentArtifact>{
      DevelopmentArtifact.universal,
      DevelopmentArtifact.macOS,
    }));
  });

  testUsingContext('precache does not download macOS artifacts on dev branch when feature is enabled.', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(isMacOSEnabled: false),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);
    await createTestCommandRunner(command).run(const <String>['precache', '--macos', '--no-android', '--no-ios']);

    expect(artifacts, unorderedEquals(<DevelopmentArtifact>{
      DevelopmentArtifact.universal,
    }));
  });

  testUsingContext('precache downloads Windows artifacts on dev branch when feature is enabled.', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(isWindowsEnabled: true),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);
    await createTestCommandRunner(command).run(const <String>['precache', '--windows', '--no-android', '--no-ios']);

    expect(artifacts, unorderedEquals(<DevelopmentArtifact>{
      DevelopmentArtifact.universal,
      DevelopmentArtifact.windows,
    }));
  });

  testUsingContext('precache does not download Windows artifacts on dev branch when feature is enabled.', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(isWindowsEnabled: false),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);
    await createTestCommandRunner(command).run(const <String>['precache', '--windows', '--no-android', '--no-ios']);

    expect(artifacts, unorderedEquals(<DevelopmentArtifact>{
      DevelopmentArtifact.universal,
    }));
  });

  testUsingContext('precache downloads Linux artifacts on dev branch when feature is enabled.', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(isLinuxEnabled: true),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);
    await createTestCommandRunner(command).run(const <String>['precache', '--linux', '--no-android', '--no-ios']);

    expect(artifacts, unorderedEquals(<DevelopmentArtifact>{
      DevelopmentArtifact.universal,
      DevelopmentArtifact.linux,
    }));
  });

  testUsingContext('precache does not download Linux artifacts on dev branch when feature is enabled.', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(isLinuxEnabled: false),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);
    await createTestCommandRunner(command).run(const <String>['precache', '--linux', '--no-android', '--no-ios']);

    expect(artifacts, unorderedEquals(<DevelopmentArtifact>{
      DevelopmentArtifact.universal,
    }));
  });

  testUsingContext('precache exits if requesting mismatched artifacts.', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(isWebEnabled: false),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);

    expect(createTestCommandRunner(command).run(const <String>['precache',
      '--no-android',
      '--android_gen_snapshot',
    ]), throwsToolExit(message: '--android_gen_snapshot requires --android'));
  });

  testUsingContext('precache adds artifact flags to requested artifacts', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(
        isWebEnabled: true,
        isLinuxEnabled: true,
        isMacOSEnabled: true,
        isWindowsEnabled: true,
        isFuchsiaEnabled: true,
      ),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);
    await createTestCommandRunner(command).run(
      const <String>[
        'precache',
        '--ios',
        '--android',
        '--web',
        '--macos',
        '--linux',
        '--windows',
        '--fuchsia',
        '--flutter_runner',
      ],
    );
    expect(artifacts, unorderedEquals(<DevelopmentArtifact>{
      DevelopmentArtifact.universal,
      DevelopmentArtifact.iOS,
      DevelopmentArtifact.androidGenSnapshot,
      DevelopmentArtifact.androidMaven,
      DevelopmentArtifact.androidInternalBuild,
      DevelopmentArtifact.web,
      DevelopmentArtifact.macOS,
      DevelopmentArtifact.linux,
      DevelopmentArtifact.windows,
      DevelopmentArtifact.fuchsia,
      DevelopmentArtifact.flutterRunner,
    }));
  });

  testUsingContext('precache expands android artifacts when the android flag is used', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);
    await createTestCommandRunner(command).run(
      const <String>[
        'precache',
        '--no-ios',
        '--android',
      ],
    );
    expect(artifacts, unorderedEquals(<DevelopmentArtifact>{
      DevelopmentArtifact.universal,
      DevelopmentArtifact.androidGenSnapshot,
      DevelopmentArtifact.androidMaven,
      DevelopmentArtifact.androidInternalBuild,
    }));
  });

  testUsingContext('precache adds artifact flags to requested android artifacts', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);
    await createTestCommandRunner(command).run(
      const <String>[
        'precache',
        '--no-ios',
        '--android_gen_snapshot',
        '--android_maven',
        '--android_internal_build',
      ],
    );
    expect(artifacts, unorderedEquals(<DevelopmentArtifact>{
      DevelopmentArtifact.universal,
      DevelopmentArtifact.androidGenSnapshot,
      DevelopmentArtifact.androidMaven,
      DevelopmentArtifact.androidInternalBuild,
    }));
  });

  testUsingContext('precache downloads iOS and Android artifacts by default', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);

    await createTestCommandRunner(command).run(
      const <String>[
        'precache',
      ],
    );

    expect(artifacts, unorderedEquals(<DevelopmentArtifact>{
      DevelopmentArtifact.universal,
      DevelopmentArtifact.iOS,
      DevelopmentArtifact.androidGenSnapshot,
      DevelopmentArtifact.androidMaven,
      DevelopmentArtifact.androidInternalBuild,
    }));
  });

  testUsingContext('precache --all-platforms gets all artifacts', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(
        isWebEnabled: true,
        isLinuxEnabled: true,
        isMacOSEnabled: true,
        isWindowsEnabled: true,
        isFuchsiaEnabled: true,
      ),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);

    await createTestCommandRunner(command).run(
      const <String>[
        'precache',
        '--all-platforms',
      ],
    );

    expect(artifacts, unorderedEquals(<DevelopmentArtifact>{
      DevelopmentArtifact.universal,
      DevelopmentArtifact.iOS,
      DevelopmentArtifact.androidGenSnapshot,
      DevelopmentArtifact.androidMaven,
      DevelopmentArtifact.androidInternalBuild,
      DevelopmentArtifact.web,
      DevelopmentArtifact.macOS,
      DevelopmentArtifact.linux,
      DevelopmentArtifact.windows,
      DevelopmentArtifact.fuchsia,
      DevelopmentArtifact.flutterRunner,
    }));
  });

  testUsingContext('precache with default artifacts does not override platform filtering', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);

    await createTestCommandRunner(command).run(
      const <String>[
        'precache',
      ],
    );

    verify(cache.platformOverrideArtifacts = <String>{});
  });

  testUsingContext('precache with explicit artifact options overrides platform filtering', () async {
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
        featureFlags: TestFeatureFlags(
        isMacOSEnabled: true,
      ),
      platform: FakePlatform(
        operatingSystem: 'windows',
        environment: <String, String>{
          'FLUTTER_ROOT': 'flutter',
          'FLUTTER_ALREADY_LOCKED': 'true',
        },
      ),
    );
    applyMocksToCommand(command);

    await createTestCommandRunner(command).run(
      const <String>[
        'precache',
        '--no-ios',
        '--no-android',
        '--macos',
      ],
    );

    expect(artifacts, unorderedEquals(<DevelopmentArtifact>{
      DevelopmentArtifact.universal,
      DevelopmentArtifact.macOS,
    }));
    verify(cache.platformOverrideArtifacts = <String>{'macos'});
  });

  testUsingContext('precache deletes artifact stampfiles when --force is provided', () async {
    when(cache.isUpToDate()).thenReturn(true);
    final PrecacheCommand command = PrecacheCommand(
      cache: cache,
      logger: BufferLogger.test(),
      featureFlags: TestFeatureFlags(
        isMacOSEnabled: true,
      ),
      platform: FakePlatform(environment: <String, String>{}),
    );
    applyMocksToCommand(command);
    await createTestCommandRunner(command).run(const <String>['precache', '--force']);

    verify(cache.clearStampFiles()).called(1);
  });
}

class MockCache extends Mock implements Cache {}
