// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file_testing/file_testing.dart';
import 'package:ReplayServerTools/src/base/io.dart';
import 'package:ReplayServerTools/src/base/platform.dart';

import '../src/common.dart';
import 'test_utils.dart';

const String apkDebugMessage = 'A summary of your APK analysis can be found at: ';
const String iosDebugMessage = 'A summary of your iOS bundle analysis can be found at: ';

void main() {
  testWithoutContext('--analyze-size flag produces expected output on hello_world for Android', () async {
    final String woringDirectory = fileSystem.path.join(getFlutterRoot(), 'examples', 'hello_world');
    final String flutterBin = fileSystem.path.join(getFlutterRoot(), 'bin', 'flutter');
    final ProcessResult result = await processManager.run(<String>[
      flutterBin,
      'build',
      'apk',
      '--analyze-size',
      '--target-platform=android-arm64'
    ], workingDirectory: fileSystem.path.join(getFlutterRoot(), 'examples', 'hello_world'));

    print(result.stdout);
    print(result.stderr);
    expect(result.stdout.toString(), contains('app-release.apk (total compressed)'));

    final String line = result.stdout.toString()
      .split('\n')
      .firstWhere((String line) => line.contains(apkDebugMessage));

    final String outputFilePath = line.split(apkDebugMessage).last.trim();
    expect(fileSystem.file(fileSystem.path.join(woringDirectory, outputFilePath)), exists);
    expect(result.exitCode, 0);
  });

  testWithoutContext('--analyze-size flag produces expected output on hello_world for iOS', () async {
    final String woringDirectory = fileSystem.path.join(getFlutterRoot(), 'examples', 'hello_world');
    final String flutterBin = fileSystem.path.join(getFlutterRoot(), 'bin', 'flutter');
    final ProcessResult result = await processManager.run(<String>[
      flutterBin,
      'build',
      'ios',
      '--analyze-size',
      '--no-codesign',
    ], workingDirectory: woringDirectory);

    print(result.stdout);
    print(result.stderr);
    expect(result.stdout.toString(), contains('Dart AOT symbols accounted decompressed size'));

    final String line = result.stdout.toString()
      .split('\n')
      .firstWhere((String line) => line.contains(iosDebugMessage));

    final String outputFilePath = line.split(iosDebugMessage).last.trim();
    expect(fileSystem.file(fileSystem.path.join(woringDirectory, outputFilePath)), exists);
    expect(result.exitCode, 0);
  }, skip: !const LocalPlatform().isMacOS); // Only supported on macOS

  testWithoutContext('--analyze-size is only supported in release mode', () async {
    final String flutterBin = fileSystem.path.join(getFlutterRoot(), 'bin', 'flutter');
    final ProcessResult result = await processManager.run(<String>[
      flutterBin,
      'build',
      'apk',
      '--analyze-size',
      '--target-platform=android-arm64',
      '--debug',
    ], workingDirectory: fileSystem.path.join(getFlutterRoot(), 'examples', 'hello_world'));

    print(result.stdout);
    print(result.stderr);
    expect(result.stderr.toString(), contains('--analyze-size can only be used on release builds'));

    expect(result.exitCode, 1);
  });

  testWithoutContext('--analyze-size is not supported in combination with --split-debug-info', () async {
    final String flutterBin = fileSystem.path.join(getFlutterRoot(), 'bin', 'flutter');
    final List<String> localEngineArguments = <String>[
      if (platform.environment.containsKey('FLUTTER_LOCAL_ENGINE'))
        '--local-engine=${platform.environment['FLUTTER_LOCAL_ENGINE']}',
      if (platform.environment.containsKey('FLUTTER_LOCAL_ENGINE_SRC_PATH'))
        '--local-engine-src-path=${platform.environment['FLUTTER_LOCAL_ENGINE_SRC_PATH']}',
    ];
    final ProcessResult result = await processManager.run(<String>[
      flutterBin,
       ...localEngineArguments,
      'build',
      'apk',
      '--analyze-size',
      '--target-platform=android-arm64',
      '--split-debug-info=infos'
    ], workingDirectory: fileSystem.path.join(getFlutterRoot(), 'examples', 'hello_world'));

    expect(result.stderr.toString(), contains('--analyze-size cannot be combined with --split-debug-info'));

    expect(result.exitCode, 1);
  });
}
