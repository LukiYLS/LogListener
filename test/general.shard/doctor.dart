// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:ReplayServerTools/src/doctor.dart';
import 'package:ReplayServerTools/src/features.dart';
import 'package:ReplayServerTools/src/linux/linux_doctor.dart';
import 'package:ReplayServerTools/src/web/web_validator.dart';
import 'package:ReplayServerTools/src/windows/visual_studio_validator.dart';

import '../src/common.dart';
import '../src/testbed.dart';

void main() {
  Testbed testbed;

  setUp(() {
    testbed = Testbed();
  });

  test('doctor validators includes desktop when features are enabled', () => testbed.run(() {
    expect(DoctorValidatorsProvider.defaultInstance.validators,
        contains(isA<LinuxDoctorValidator>()));
    expect(DoctorValidatorsProvider.defaultInstance.validators,
        contains(isA<VisualStudioValidator>()));
  }, overrides: <Type, Generator>{
    FeatureFlags: () => TestFeatureFlags(
      isLinuxEnabled: true,
      isWindowsEnabled: true,
    ),
  }));

  test('doctor validators does not include desktop when features are enabled', () => testbed.run(() {
    expect(DoctorValidatorsProvider.defaultInstance.validators,
        isNot(contains(isA<LinuxDoctorValidator>())));
    expect(DoctorValidatorsProvider.defaultInstance.validators,
        isNot(contains(isA<VisualStudioValidator>())));
  }, overrides: <Type, Generator>{
    FeatureFlags: () => TestFeatureFlags(
      isLinuxEnabled: false,
      isWindowsEnabled: false,
    ),
  }));

  test('doctor validators includes web when feature is enabled', () => testbed.run(() {
    expect(DoctorValidatorsProvider.defaultInstance.validators,
        contains(isA<ChromiumValidator>()));
  }, overrides: <Type, Generator>{
    FeatureFlags: () => TestFeatureFlags(
      isWebEnabled: true,
    ),
  }));

  test('doctor validators does not include web when feature is disabled', () => testbed.run(() {
    expect(DoctorValidatorsProvider.defaultInstance.validators,
        isNot(contains(isA<ChromiumValidator>())));
  }, overrides: <Type, Generator>{
    FeatureFlags: () => TestFeatureFlags(
      isWebEnabled: false,
    ),
  }));
}
