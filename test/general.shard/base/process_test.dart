// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:ReplayServerTools/src/base/io.dart';
import 'package:ReplayServerTools/src/base/logger.dart';
import 'package:ReplayServerTools/src/base/platform.dart';
import 'package:ReplayServerTools/src/base/process.dart';
import 'package:ReplayServerTools/src/base/terminal.dart';
import 'package:mockito/mockito.dart';
import 'package:process/process.dart';
import 'package:fake_async/fake_async.dart';
import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/mocks.dart' show MockProcess,
                                   MockProcessManager,
                                   MockStdio,
                                   flakyProcessFactory;

void main() {
  group('process exceptions', () {
    ProcessManager mockProcessManager;
    ProcessUtils processUtils;

    setUp(() {
      mockProcessManager = PlainMockProcessManager();
      processUtils = ProcessUtils(
        processManager: mockProcessManager,
        logger: BufferLogger.test(),
      );
    });

    testWithoutContext('runAsync throwOnError: exceptions should be ProcessException objects', () async {
      when(mockProcessManager.run(<String>['false'])).thenAnswer(
          (Invocation invocation) => Future<ProcessResult>.value(ProcessResult(0, 1, '', '')));
      expect(() async => await processUtils.run(<String>['false'], throwOnError: true),
             throwsA(isA<ProcessException>()));
    });
  });

  group('shutdownHooks', () {
    testWithoutContext('runInExpectedOrder', () async {
      int i = 1;
      int serializeRecording1;
      int serializeRecording2;
      int postProcessRecording;
      int cleanup;

      final ShutdownHooks shutdownHooks = ShutdownHooks(logger: BufferLogger.test());

      shutdownHooks.addShutdownHook(() async {
        serializeRecording1 = i++;
      }, ShutdownStage.SERIALIZE_RECORDING);

      shutdownHooks.addShutdownHook(() async {
        cleanup = i++;
      }, ShutdownStage.CLEANUP);

      shutdownHooks.addShutdownHook(() async {
        postProcessRecording = i++;
      }, ShutdownStage.POST_PROCESS_RECORDING);

      shutdownHooks.addShutdownHook(() async {
        serializeRecording2 = i++;
      }, ShutdownStage.SERIALIZE_RECORDING);

      await shutdownHooks.runShutdownHooks();

      expect(serializeRecording1, lessThanOrEqualTo(2));
      expect(serializeRecording2, lessThanOrEqualTo(2));
      expect(postProcessRecording, 3);
      expect(cleanup, 4);
    });
  });

  group('output formatting', () {
    MockProcessManager mockProcessManager;
    ProcessUtils processUtils;
    BufferLogger mockLogger;

    setUp(() {
      mockProcessManager = MockProcessManager();
      mockLogger = BufferLogger(
        terminal: AnsiTerminal(
          stdio: MockStdio(),
          platform: FakePlatform(stdoutSupportsAnsi: false),
        ),
        outputPreferences: OutputPreferences(wrapText: true, wrapColumn: 40),
      );
      processUtils = ProcessUtils(
        processManager: mockProcessManager,
        logger: mockLogger,
      );
    });

    MockProcess Function(List<String>) processMetaFactory(List<String> stdout, {
      List<String> stderr = const <String>[],
    }) {
      final Stream<List<int>> stdoutStream = Stream<List<int>>.fromIterable(
        stdout.map<List<int>>((String s) => s.codeUnits,
      ));
      final Stream<List<int>> stderrStream = Stream<List<int>>.fromIterable(
        stderr.map<List<int>>((String s) => s.codeUnits,
      ));
      return (List<String> command) => MockProcess(stdout: stdoutStream, stderr: stderrStream);
    }

    testWithoutContext('Command output is not wrapped.', () async {
      final List<String> testString = <String>['0123456789' * 10];
      mockProcessManager.processFactory = processMetaFactory(testString, stderr: testString);
      await processUtils.stream(<String>['command']);
      expect(mockLogger.statusText, equals('${testString[0]}\n'));
      expect(mockLogger.errorText, equals('${testString[0]}\n'));
    });
  });

  group('run', () {
    const Duration delay = Duration(seconds: 2);
    MockProcessManager flakyProcessManager;
    ProcessManager mockProcessManager;
    ProcessUtils processUtils;
    ProcessUtils flakyProcessUtils;

    setUp(() {
      // MockProcessManager has an implementation of start() that returns the
      // result of processFactory.
      flakyProcessManager = MockProcessManager();
      mockProcessManager = MockProcessManager();
      processUtils = ProcessUtils(
        processManager: mockProcessManager,
        logger: BufferLogger.test(),
      );
      flakyProcessUtils = ProcessUtils(
        processManager: flakyProcessManager,
        logger: BufferLogger.test(),
      );
    });

    testWithoutContext(' succeeds on success', () async {
      when(mockProcessManager.run(<String>['whoohoo'])).thenAnswer((_) {
        return Future<ProcessResult>.value(ProcessResult(0, 0, '', ''));
      });
      expect((await processUtils.run(<String>['whoohoo'])).exitCode, 0);
    });

    testWithoutContext(' fails on failure', () async {
      when(mockProcessManager.run(<String>['boohoo'])).thenAnswer((_) {
        return Future<ProcessResult>.value(ProcessResult(0, 1, '', ''));
      });
      expect((await processUtils.run(<String>['boohoo'])).exitCode, 1);
    });

    testWithoutContext(' throws on failure with throwOnError', () async {
      when(mockProcessManager.run(<String>['kaboom'])).thenAnswer((_) {
        return Future<ProcessResult>.value(ProcessResult(0, 1, '', ''));
      });
      expect(() => processUtils.run(<String>['kaboom'], throwOnError: true),
             throwsA(isA<ProcessException>()));
    });

    testWithoutContext(' does not throw on allowed Failures', () async {
      when(mockProcessManager.run(<String>['kaboom'])).thenAnswer((_) {
        return Future<ProcessResult>.value(ProcessResult(0, 1, '', ''));
      });
      expect(
        (await processUtils.run(
          <String>['kaboom'],
          throwOnError: true,
          allowedFailures: (int c) => c == 1,
        )).exitCode,
        1,
      );
    });

    testWithoutContext(' throws on disallowed failure', () async {
      when(mockProcessManager.run(<String>['kaboom'])).thenAnswer((_) {
        return Future<ProcessResult>.value(ProcessResult(0, 2, '', ''));
      });
      expect(
        () => processUtils.run(
          <String>['kaboom'],
          throwOnError: true,
          allowedFailures: (int c) => c == 1,
        ),
        throwsA(isA<ProcessException>()),
      );
    });

    testWithoutContext(' flaky process fails without retry', () async {
      flakyProcessManager.processFactory = flakyProcessFactory(
        flakes: 1,
        delay: delay,
      );

      await FakeAsync().run((FakeAsync time) async {
        final Duration timeout = delay + const Duration(seconds: 1);
        final RunResult result = await flakyProcessUtils.run(
          <String>['dummy'],
          timeout: timeout,
        );
        time.elapse(timeout);
        expect(result.exitCode, -9);
      });
    }, skip: true); // TODO(jonahwilliams): clean up with https://github.com/flutter/flutter/issues/60675

    testWithoutContext(' flaky process succeeds with retry', () async {
      flakyProcessManager.processFactory = flakyProcessFactory(
        flakes: 1,
        delay: delay,
      );
      await FakeAsync().run((FakeAsync time) async {
        final Duration timeout = delay - const Duration(milliseconds: 500);
        final RunResult result = await flakyProcessUtils.run(
          <String>['dummy'],
          timeout: timeout,
          timeoutRetries: 1,
        );
        time.elapse(timeout);
        expect(result.exitCode, 0);
      });
    }, skip: true); // TODO(jonahwilliams): clean up with https://github.com/flutter/flutter/issues/60675

    testWithoutContext(' flaky process generates ProcessException on timeout', () async {
      final Completer<List<int>> flakyStderr = Completer<List<int>>();
      final Completer<List<int>> flakyStdout = Completer<List<int>>();
      flakyProcessManager.processFactory = flakyProcessFactory(
        flakes: 1,
        delay: delay,
        stderr: () => Stream<List<int>>.fromFuture(flakyStderr.future),
        stdout: () => Stream<List<int>>.fromFuture(flakyStdout.future),
      );
      when(flakyProcessManager.killPid(any)).thenAnswer((_) {
        // Don't let the stderr stream stop until the process is killed. This
        // ensures that runAsync() does not delay killing the process until
        // stdout and stderr are drained (which won't happen).
        flakyStderr.complete(<int>[]);
        flakyStdout.complete(<int>[]);
        return true;
      });
      await FakeAsync().run((FakeAsync time) async {
        final Duration timeout = delay - const Duration(milliseconds: 500);
        expect(() => flakyProcessUtils.run(
          <String>['dummy'],
          timeout: timeout,
          timeoutRetries: 0,
        ), throwsA(isA<ProcessException>()));
        time.elapse(timeout);
      });
    }, skip: true); // TODO(jonahwilliams): clean up with https://github.com/flutter/flutter/issues/60675
  });

  group('runSync', () {
    ProcessManager mockProcessManager;
    ProcessUtils processUtils;
    BufferLogger testLogger;

    setUp(() {
      mockProcessManager = MockProcessManager();
      testLogger = BufferLogger(
        terminal: AnsiTerminal(
          stdio: MockStdio(),
          platform: FakePlatform(stdinSupportsAnsi: false),
        ),
        outputPreferences: OutputPreferences(wrapText: true, wrapColumn: 40),
      );
      processUtils = ProcessUtils(
        processManager: mockProcessManager,
        logger: testLogger,
      );
    });

    testWithoutContext(' succeeds on success', () async {
      when(mockProcessManager.runSync(<String>['whoohoo'])).thenReturn(
        ProcessResult(0, 0, '', '')
      );
      expect(processUtils.runSync(<String>['whoohoo']).exitCode, 0);
    });

    testWithoutContext(' fails on failure', () async {
      when(mockProcessManager.runSync(<String>['boohoo'])).thenReturn(
        ProcessResult(0, 1, '', '')
      );
      expect(processUtils.runSync(<String>['boohoo']).exitCode, 1);
    });

    testWithoutContext('throws on failure with throwOnError', () async {
      const String stderr = 'Something went wrong.';
      when(mockProcessManager.runSync(<String>['kaboom'])).thenReturn(
        ProcessResult(0, 1, '', stderr),
      );
      try {
        processUtils.runSync(<String>['kaboom'], throwOnError: true);
        fail('ProcessException expected.');
      } on ProcessException catch (e) {
        expect(e, isA<ProcessException>());
        expect(e.message.contains(stderr), false);
      }
    });

    testWithoutContext('throws with stderr in exception on failure with verboseExceptions', () async {
      const String stderr = 'Something went wrong.';
      when(mockProcessManager.runSync(<String>['verybad'])).thenReturn(
        ProcessResult(0, 1, '', stderr),
      );
      expect(
        () => processUtils.runSync(
          <String>['verybad'],
          throwOnError: true,
          verboseExceptions: true,
        ),
        throwsProcessException(message: stderr),
      );
    });

    testWithoutContext(' does not throw on allowed Failures', () async {
      when(mockProcessManager.runSync(<String>['kaboom'])).thenReturn(
        ProcessResult(0, 1, '', '')
      );
      expect(
        processUtils.runSync(
          <String>['kaboom'],
          throwOnError: true,
          allowedFailures: (int c) => c == 1,
        ).exitCode,
        1);
    });

    testWithoutContext(' throws on disallowed failure', () async {
      when(mockProcessManager.runSync(<String>['kaboom'])).thenReturn(
        ProcessResult(0, 2, '', '')
      );
      expect(
        () => processUtils.runSync(
          <String>['kaboom'],
          throwOnError: true,
          allowedFailures: (int c) => c == 1,
        ),
        throwsA(isA<ProcessException>()));
    });

    testWithoutContext(' prints stdout and stderr to trace on success', () async {
      when(mockProcessManager.runSync(<String>['whoohoo'])).thenReturn(
        ProcessResult(0, 0, 'stdout', 'stderr')
      );
      expect(processUtils.runSync(<String>['whoohoo']).exitCode, 0);
      expect(testLogger.traceText, contains('stdout'));
      expect(testLogger.traceText, contains('stderr'));
    });

    testWithoutContext(' prints stdout to status and stderr to error on failure with throwOnError', () async {
      when(mockProcessManager.runSync(<String>['kaboom'])).thenReturn(
        ProcessResult(0, 1, 'stdout', 'stderr')
      );
      expect(() => processUtils.runSync(<String>['kaboom'], throwOnError: true),
             throwsA(isA<ProcessException>()));
      expect(testLogger.statusText, contains('stdout'));
      expect(testLogger.errorText, contains('stderr'));
    });

    testWithoutContext(' does not print stdout with hideStdout', () async {
      when(mockProcessManager.runSync(<String>['whoohoo'])).thenReturn(
        ProcessResult(0, 0, 'stdout', 'stderr')
      );
      expect(processUtils.runSync(<String>['whoohoo'], hideStdout: true).exitCode, 0);
      expect(testLogger.traceText.contains('stdout'), isFalse);
      expect(testLogger.traceText, contains('stderr'));
    });
  });

  group('exitsHappySync', () {
    MockProcessManager mockProcessManager;
    ProcessUtils processUtils;

    setUp(() {
      mockProcessManager = MockProcessManager();
      processUtils = ProcessUtils(
        processManager: mockProcessManager,
        logger: BufferLogger.test(),
      );
    });

    testWithoutContext(' succeeds on success', () async {
      when(mockProcessManager.runSync(<String>['whoohoo'])).thenReturn(
        ProcessResult(0, 0, '', '')
      );
      expect(processUtils.exitsHappySync(<String>['whoohoo']), isTrue);
    });

    testWithoutContext(' fails on failure', () async {
      when(mockProcessManager.runSync(<String>['boohoo'])).thenReturn(
        ProcessResult(0, 1, '', '')
      );
      expect(processUtils.exitsHappySync(<String>['boohoo']), isFalse);
    });

    testWithoutContext('catches Exception and returns false', () {
      when(mockProcessManager.runSync(<String>['boohoo'])).thenThrow(
        const ProcessException('Process failed', <String>[]),
      );
      expect(processUtils.exitsHappySync(<String>['boohoo']), isFalse);
    });

    testWithoutContext('does not throw Exception and returns false if binary cannot run', () {
      mockProcessManager.canRunSucceeds = false;
      expect(processUtils.exitsHappySync(<String>['nonesuch']), isFalse);
      verifyNever(
        mockProcessManager.runSync(any, environment: anyNamed('environment')),
      );
    });

    testWithoutContext('does not catch ArgumentError', () async {
      when(mockProcessManager.runSync(<String>['invalid'])).thenThrow(
        ArgumentError('Bad input'),
      );
      expect(
        () => processUtils.exitsHappySync(<String>['invalid']),
        throwsArgumentError,
      );
    });
  });

  group('exitsHappy', () {
    MockProcessManager mockProcessManager;
    ProcessUtils processUtils;

    setUp(() {
      mockProcessManager = MockProcessManager();
      processUtils = ProcessUtils(
        processManager: mockProcessManager,
        logger: BufferLogger.test(),
      );
    });

    testWithoutContext('succeeds on success', () async {
      when(mockProcessManager.run(<String>['whoohoo'])).thenAnswer((_) {
        return Future<ProcessResult>.value(ProcessResult(0, 0, '', ''));
      });
      expect(await processUtils.exitsHappy(<String>['whoohoo']), isTrue);
    });

    testWithoutContext('fails on failure', () async {
      when(mockProcessManager.run(<String>['boohoo'])).thenAnswer((_) {
        return Future<ProcessResult>.value(ProcessResult(0, 1, '', ''));
      });
      expect(await processUtils.exitsHappy(<String>['boohoo']), isFalse);
    });

    testWithoutContext('catches Exception and returns false', () async {
      when(mockProcessManager.run(<String>['boohoo'])).thenThrow(
        const ProcessException('Process failed', <String>[]),
      );
      expect(await processUtils.exitsHappy(<String>['boohoo']), isFalse);
    });

    testWithoutContext('does not throw Exception and returns false if binary cannot run', () async {
      mockProcessManager.canRunSucceeds = false;
      expect(await processUtils.exitsHappy(<String>['nonesuch']), isFalse);
      verifyNever(
        mockProcessManager.runSync(any, environment: anyNamed('environment')),
      );
    });

    testWithoutContext('does not catch ArgumentError', () async {
      when(mockProcessManager.run(<String>['invalid'])).thenThrow(
        ArgumentError('Bad input'),
      );
      expect(
        () async => await processUtils.exitsHappy(<String>['invalid']),
        throwsArgumentError,
      );
    });
  });

}

class PlainMockProcessManager extends Mock implements ProcessManager {}
