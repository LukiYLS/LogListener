// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:ReplayServerTools/src/base/file_system.dart';
import 'package:ReplayServerTools/src/doctor.dart';
import 'package:ReplayServerTools/src/intellij/intellij.dart';
import 'package:ReplayServerTools/src/globals.dart' as globals;

import '../../src/common.dart';
import '../../src/context.dart';

void main() {
  FileSystem fs;

  void writeFileCreatingDirectories(String path, List<int> bytes) {
    final File file = globals.fs.file(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  setUp(() {
    fs = MemoryFileSystem();
  });

  group('IntelliJ', () {
    group('plugins', () {
      testUsingContext('found', () async {
        final IntelliJPlugins plugins = IntelliJPlugins(_kPluginsPath);

        final Archive dartJarArchive =
            buildSingleFileArchive('META-INF/plugin.xml', r'''
<idea-plugin version="2">
  <name>Dart</name>
  <version>162.2485</version>
</idea-plugin>
''');
        writeFileCreatingDirectories(
            globals.fs.path.join(_kPluginsPath, 'Dart', 'lib', 'Dart.jar'),
            ZipEncoder().encode(dartJarArchive));

        final Archive flutterJarArchive =
            buildSingleFileArchive('META-INF/plugin.xml', r'''
<idea-plugin version="2">
  <name>Flutter</name>
  <version>0.1.3</version>
</idea-plugin>
''');
        writeFileCreatingDirectories(
            globals.fs.path.join(_kPluginsPath, 'flutter-intellij.jar'),
            ZipEncoder().encode(flutterJarArchive));

        final List<ValidationMessage> messages = <ValidationMessage>[];
        plugins.validatePackage(messages, <String>['Dart'], 'Dart');
        plugins.validatePackage(messages,
            <String>['flutter-intellij', 'flutter-intellij.jar'], 'Flutter',
            minVersion: IntelliJPlugins.kMinFlutterPluginVersion);

        ValidationMessage message = messages
            .firstWhere((ValidationMessage m) => m.message.startsWith('Dart '));
        expect(message.message, 'Dart plugin version 162.2485');

        message = messages.firstWhere(
            (ValidationMessage m) => m.message.startsWith('Flutter '));
        expect(message.message, contains('Flutter plugin version 0.1.3'));
        expect(message.message, contains('recommended minimum version'));
      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
      });

      testUsingContext('not found', () async {
        final IntelliJPlugins plugins = IntelliJPlugins(_kPluginsPath);

        final List<ValidationMessage> messages = <ValidationMessage>[];
        plugins.validatePackage(messages, <String>['Dart'], 'Dart');
        plugins.validatePackage(messages,
            <String>['flutter-intellij', 'flutter-intellij.jar'], 'Flutter',
            minVersion: IntelliJPlugins.kMinFlutterPluginVersion);

        ValidationMessage message = messages
            .firstWhere((ValidationMessage m) => m.message.startsWith('Dart '));
        expect(message.message, contains('Dart plugin not installed'));

        message = messages.firstWhere(
            (ValidationMessage m) => m.message.startsWith('Flutter '));
        expect(message.message, contains('Flutter plugin not installed'));
      }, overrides: <Type, Generator>{
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
      });
    });
  });
}

const String _kPluginsPath = '/data/intellij/plugins';

Archive buildSingleFileArchive(String path, String content) {
  final Archive archive = Archive();

  final List<int> bytes = utf8.encode(content);
  archive.addFile(ArchiveFile(path, bytes.length, bytes));

  return archive;
}
