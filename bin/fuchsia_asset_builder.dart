// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:args/args.dart';
import 'package:ReplayServerTools/src/asset.dart' hide defaultManifestPath;
import 'package:ReplayServerTools/src/base/context.dart';
import 'package:ReplayServerTools/src/base/file_system.dart' as libfs;
import 'package:ReplayServerTools/src/base/io.dart';
import 'package:ReplayServerTools/src/cache.dart';
import 'package:ReplayServerTools/src/context_runner.dart';
import 'package:ReplayServerTools/src/devfs.dart';
import 'package:ReplayServerTools/src/bundle.dart';
import 'package:ReplayServerTools/src/globals.dart' as globals;
import 'package:ReplayServerTools/src/reporting/reporting.dart';

const String _kOptionPackages = 'packages';
const String _kOptionAsset = 'asset-dir';
const String _kOptionManifest = 'manifest';
const String _kOptionAssetManifestOut = 'asset-manifest-out';
const String _kOptionComponentName = 'component-name';
const List<String> _kRequiredOptions = <String>[
  _kOptionPackages,
  _kOptionAsset,
  _kOptionAssetManifestOut,
  _kOptionComponentName,
];

Future<void> main(List<String> args) {
  return runInContext<void>(() => run(args), overrides: <Type, Generator>{
    Usage: () => DisabledUsage(),
  });
}

Future<void> writeFile(libfs.File outputFile, DevFSContent content) async {
  outputFile.createSync(recursive: true);
  final List<int> data = await content.contentsAsBytes();
  outputFile.writeAsBytesSync(data);
}

Future<void> run(List<String> args) async {
  final ArgParser parser = ArgParser()
    ..addOption(_kOptionPackages, help: 'The .packages file')
    ..addOption(_kOptionAsset,
        help: 'The directory where to put temporary files')
    ..addOption(_kOptionManifest, help: 'The manifest file')
    ..addOption(_kOptionAssetManifestOut)
    ..addOption(_kOptionComponentName);
  final ArgResults argResults = parser.parse(args);
  if (_kRequiredOptions
      .any((String option) => !argResults.options.contains(option))) {
    globals.printError('Missing option! All options must be specified.');
    exit(1);
  }
  Cache.flutterRoot = globals.platform.environment['FLUTTER_ROOT'];

  final String assetDir = argResults[_kOptionAsset] as String;
  final AssetBundle assets = await buildAssets(
    manifestPath: argResults[_kOptionManifest] as String ?? defaultManifestPath,
    assetDirPath: assetDir,
    packagesPath: argResults[_kOptionPackages] as String,
    includeDefaultFonts: false,
  );

  if (assets == null) {
    print('Unable to find assets.');
    exit(1);
  }

  final List<Future<void>> calls = <Future<void>>[];
  assets.entries.forEach((String fileName, DevFSContent content) {
    final libfs.File outputFile = globals.fs.file(globals.fs.path.join(assetDir, fileName));
    calls.add(writeFile(outputFile, content));
  });
  await Future.wait<void>(calls);

  final String outputMan = argResults[_kOptionAssetManifestOut] as String;
  await writeFuchsiaManifest(assets, argResults[_kOptionAsset] as String, outputMan, argResults[_kOptionComponentName] as String);
}

Future<void> writeFuchsiaManifest(AssetBundle assets, String outputBase, String fileDest, String componentName) async {

  final libfs.File destFile = globals.fs.file(fileDest);
  await destFile.create(recursive: true);
  final libfs.IOSink outFile = destFile.openWrite();

  for (final String path in assets.entries.keys) {
    outFile.write('data/$componentName/$path=$outputBase/$path\n');
  }
  await outFile.flush();
  await outFile.close();
}
