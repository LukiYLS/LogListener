// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:ReplayServerTools/src/base/user_messages.dart';
import 'package:ReplayServerTools/src/doctor.dart';
import 'package:ReplayServerTools/src/macos/xcode.dart';
import 'package:ReplayServerTools/src/macos/xcode_validator.dart';
import 'package:mockito/mockito.dart';
import 'package:process/process.dart';

import '../../src/common.dart';
import '../../src/context.dart';

class MockProcessManager extends Mock implements ProcessManager {}
class MockXcode extends Mock implements Xcode {}

void main() {
  group('Xcode validation', () {
    MockXcode xcode;

    setUp(() {
      xcode = MockXcode();
    });

    testWithoutContext('Emits missing status when Xcode is not installed', () async {
      when(xcode.isInstalled).thenReturn(false);
      when(xcode.xcodeSelectPath).thenReturn(null);
      final XcodeValidator validator = XcodeValidator(xcode: xcode, userMessages: UserMessages());
      final ValidationResult result = await validator.validate();
      expect(result.type, ValidationType.missing);
    });

    testWithoutContext('Emits missing status when Xcode installation is incomplete', () async {
      when(xcode.isInstalled).thenReturn(false);
      when(xcode.xcodeSelectPath).thenReturn('/Library/Developer/CommandLineTools');
      final XcodeValidator validator = XcodeValidator(xcode: xcode, userMessages: UserMessages());
      final ValidationResult result = await validator.validate();
      expect(result.type, ValidationType.missing);
    });

    testWithoutContext('Emits partial status when Xcode version too low', () async {
      when(xcode.isInstalled).thenReturn(true);
      when(xcode.versionText)
          .thenReturn('Xcode 7.0.1\nBuild version 7C1002\n');
      when(xcode.isInstalledAndMeetsVersionCheck).thenReturn(false);
      when(xcode.eulaSigned).thenReturn(true);
      when(xcode.isSimctlInstalled).thenReturn(true);
      final XcodeValidator validator = XcodeValidator(xcode: xcode, userMessages: UserMessages());
      final ValidationResult result = await validator.validate();
      expect(result.type, ValidationType.partial);
    });

    testWithoutContext('Emits partial status when Xcode EULA not signed', () async {
      when(xcode.isInstalled).thenReturn(true);
      when(xcode.versionText)
          .thenReturn('Xcode 8.2.1\nBuild version 8C1002\n');
      when(xcode.isInstalledAndMeetsVersionCheck).thenReturn(true);
      when(xcode.eulaSigned).thenReturn(false);
      when(xcode.isSimctlInstalled).thenReturn(true);
      final XcodeValidator validator = XcodeValidator(xcode: xcode, userMessages: UserMessages());
      final ValidationResult result = await validator.validate();
      expect(result.type, ValidationType.partial);
    });

    testWithoutContext('Emits partial status when simctl is not installed', () async {
      when(xcode.isInstalled).thenReturn(true);
      when(xcode.versionText)
          .thenReturn('Xcode 8.2.1\nBuild version 8C1002\n');
      when(xcode.isInstalledAndMeetsVersionCheck).thenReturn(true);
      when(xcode.eulaSigned).thenReturn(true);
      when(xcode.isSimctlInstalled).thenReturn(false);
      final XcodeValidator validator = XcodeValidator(xcode: xcode, userMessages: UserMessages());
      final ValidationResult result = await validator.validate();
      expect(result.type, ValidationType.partial);
    });


    testWithoutContext('Succeeds when all checks pass', () async {
      when(xcode.isInstalled).thenReturn(true);
      when(xcode.versionText)
          .thenReturn('Xcode 8.2.1\nBuild version 8C1002\n');
      when(xcode.isInstalledAndMeetsVersionCheck).thenReturn(true);
      when(xcode.eulaSigned).thenReturn(true);
      when(xcode.isSimctlInstalled).thenReturn(true);
      final XcodeValidator validator = XcodeValidator(xcode: xcode, userMessages: UserMessages());
      final ValidationResult result = await validator.validate();
      expect(result.type, ValidationType.installed);
    });
  });
}
