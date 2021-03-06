// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:ReplayServerTools/src/build_info.dart';
import 'package:ReplayServerTools/src/device.dart';
import 'package:ReplayServerTools/src/project.dart';

/// A list of fake devices to test JSON serialization
/// (`Device.toJson()` and `--machine` flag for `devices` command)
List<FakeDeviceJsonData> fakeDevices = <FakeDeviceJsonData>[
  FakeDeviceJsonData(
    FakeDevice('ephemeral', 'ephemeral', true, true, PlatformType.android),
    <String, Object>{
      'name': 'ephemeral',
      'id': 'ephemeral',
      'isSupported': true,
      'targetPlatform': 'android-arm',
      'emulator': true,
      'sdk': 'Test SDK (1.2.3)',
      'capabilities': <String, Object>{
        'hotReload': true,
        'hotRestart': true,
        'screenshot': false,
        'fastStart': false,
        'flutterExit': true,
        'hardwareRendering': true,
        'startPaused': true
      }
    }
  ),
  FakeDeviceJsonData(
    FakeDevice('webby', 'webby')
      ..targetPlatform = Future<TargetPlatform>.value(TargetPlatform.web_javascript)
      ..sdkNameAndVersion = Future<String>.value('Web SDK (1.2.4)'),
    <String,Object>{
      'name': 'webby',
      'id': 'webby',
      'isSupported': true,
      'targetPlatform': 'web-javascript',
      'emulator': true,
      'sdk': 'Web SDK (1.2.4)',
      'capabilities': <String, Object>{
        'hotReload': true,
        'hotRestart': true,
        'screenshot': false,
        'fastStart': false,
        'flutterExit': true,
        'hardwareRendering': true,
        'startPaused': true
      }
    }
  ),
];

/// Fake device to test `devices` command.
class FakeDevice extends Device {
  FakeDevice(this.name, String id, [bool ephemeral = true, this._isSupported = true, PlatformType type = PlatformType.web]) : super(
      id,
      platformType: type,
      category: Category.mobile,
      ephemeral: ephemeral,
  );

  final bool _isSupported;

  @override
  final String name;

  @override
  Future<TargetPlatform> targetPlatform = Future<TargetPlatform>.value(TargetPlatform.android_arm);

  @override
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  bool isSupportedForProject(FlutterProject flutterProject) => _isSupported;

  @override
  bool isSupported() => _isSupported;

  @override
  Future<bool> isLocalEmulator = Future<bool>.value(true);

  @override
  Future<String> sdkNameAndVersion = Future<String>.value('Test SDK (1.2.3)');
}

/// Combines fake device with its canonical JSON representation.
class FakeDeviceJsonData {
  FakeDeviceJsonData(this.dev, this.json);

  final FakeDevice dev;
  final Map<String, Object> json;
}
