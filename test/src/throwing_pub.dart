// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:ReplayServerTools/src/base/io.dart';
import 'package:ReplayServerTools/src/dart/pub.dart';
import 'package:meta/meta.dart';

class ThrowingPub implements Pub {
  @override
  Future<void> batch(List<String> arguments, {
    PubContext context,
    String directory,
    MessageFilter filter,
    String failureMessage = 'pub failed',
    bool retry,
    bool showTraceForErrors,
  }) {
    throw UnsupportedError('Attempted to invoke pub during test.');
  }

  @override
  Future<void> get({
    PubContext context,
    String directory,
    bool skipIfAbsent = false,
    bool upgrade = false,
    bool offline = false,
    bool checkLastModified = true,
    bool skipPubspecYamlCheck = false,
    bool generateSyntheticPackage = false,
    String flutterRootOverride,
  }) {
    throw UnsupportedError('Attempted to invoke pub during test.');
  }

  @override
  Future<void> interactively(List<String> arguments, {String directory, @required Stdio stdio,}) {
    throw UnsupportedError('Attempted to invoke pub during test.');
  }
}
