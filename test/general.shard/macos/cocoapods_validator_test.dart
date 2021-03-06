// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:ReplayServerTools/src/base/user_messages.dart';
import 'package:ReplayServerTools/src/doctor.dart';
import 'package:ReplayServerTools/src/macos/cocoapods.dart';
import 'package:ReplayServerTools/src/macos/cocoapods_validator.dart';
import 'package:mockito/mockito.dart';

import '../../src/common.dart';

void main() {
  group('CocoaPods validation', () {
    MockCocoaPods cocoaPods;

    setUp(() {
      cocoaPods = MockCocoaPods();
      when(cocoaPods.evaluateCocoaPodsInstallation)
          .thenAnswer((_) async => CocoaPodsStatus.recommended);
      when(cocoaPods.isCocoaPodsInitialized).thenAnswer((_) async => true);
      when(cocoaPods.cocoaPodsVersionText).thenAnswer((_) async => '1.8.0');
    });

    testWithoutContext('Emits installed status when CocoaPods is installed', () async {
      final CocoaPodsValidator workflow = CocoaPodsValidator(cocoaPods, UserMessages());
      final ValidationResult result = await workflow.validate();
      expect(result.type, ValidationType.installed);
    });

    testWithoutContext('Emits missing status when CocoaPods is not installed', () async {
      when(cocoaPods.evaluateCocoaPodsInstallation)
          .thenAnswer((_) async => CocoaPodsStatus.notInstalled);
      final CocoaPodsValidator workflow = CocoaPodsValidator(cocoaPods, UserMessages());
      final ValidationResult result = await workflow.validate();
      expect(result.type, ValidationType.missing);
    });

    testWithoutContext('Emits partial status when CocoaPods is installed with unknown version', () async {
      when(cocoaPods.evaluateCocoaPodsInstallation)
          .thenAnswer((_) async => CocoaPodsStatus.unknownVersion);
      final CocoaPodsValidator workflow = CocoaPodsValidator(cocoaPods, UserMessages());
      final ValidationResult result = await workflow.validate();
      expect(result.type, ValidationType.partial);
    });

    testWithoutContext('Emits partial status when CocoaPods is not initialized', () async {
      when(cocoaPods.isCocoaPodsInitialized).thenAnswer((_) async => false);
      final CocoaPodsValidator workflow = CocoaPodsValidator(cocoaPods, UserMessages());
      final ValidationResult result = await workflow.validate();
      expect(result.type, ValidationType.partial);
    });

    testWithoutContext('Emits partial status when CocoaPods version is too low', () async {
      when(cocoaPods.evaluateCocoaPodsInstallation)
          .thenAnswer((_) async => CocoaPodsStatus.belowRecommendedVersion);
      const String currentVersion = '1.4.0';
      when(cocoaPods.cocoaPodsVersionText)
          .thenAnswer((_) async => currentVersion);
      const String recommendedVersion = '1.8.0';
      when(cocoaPods.cocoaPodsRecommendedVersion)
          .thenAnswer((_) => recommendedVersion);
      final CocoaPodsValidator workflow = CocoaPodsValidator(cocoaPods, UserMessages());
      final ValidationResult result = await workflow.validate();
      expect(result.type, ValidationType.partial);
      expect(result.messages.length, 1);
      final ValidationMessage message = result.messages.first;
      expect(message.type, ValidationMessageType.hint);
      expect(message.message, contains('CocoaPods $currentVersion out of date'));
      expect(message.message, contains('($recommendedVersion is recommended)'));
    });
  });
}

class MockCocoaPods extends Mock implements CocoaPods {}
