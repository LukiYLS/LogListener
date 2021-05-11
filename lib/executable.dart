// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';


import 'runner.dart' as runner;

import 'src/commands/attach.dart';
import 'src/commands/devices.dart';
import 'src/runner/flutter_command.dart';


/// Main entry point for commands.
///
/// This function is intended to be used from the `flutter` command line tool.
Future<void> main(List<String> args) async {
  // args = ['listen', '--device-id=00008030-0012041E1A31802E'];
  // args = ['listen', '--device-id=d887f483', '--regex=.*Replay recorder listen on.*'];
  // args = ['devices'];
  final bool veryVerbose = args.contains('-vv');
  final bool verbose = args.contains('-v') || args.contains('--verbose') || veryVerbose;

  final bool doctor = (args.isNotEmpty && args.first == 'doctor') ||
      (args.length == 2 && verbose && args.last == 'doctor');
  final bool help = args.contains('-h') || args.contains('--help') ||
      (args.isNotEmpty && args.first == 'help') || (args.length == 1 && verbose);
  final bool muteCommandLogging = (help || doctor) && !veryVerbose;
  final bool verboseHelp = help && verbose;
  // final bool daemon = args.contains('daemon');
  // final bool runMachine = (args.contains('--machine') && args.contains('run')) ||
  //                         (args.contains('--machine') && args.contains('attach'));
  
  await runner.run(args, () => <FlutterCommand>[
    AttachCommand(verboseHelp: verboseHelp, output: stdout),
    DevicesCommand()
  ], verbose: verbose,
     muteCommandLogging: muteCommandLogging,
     verboseHelp: verboseHelp);
}


// /// An abstraction for instantiation of the correct logger type.
// ///
// /// Our logger class hierarchy and runtime requirements are overly complicated.
// class LoggerFactory {
//   LoggerFactory({
//     @required Terminal terminal,
//     @required Stdio stdio,
//     @required OutputPreferences outputPreferences,
//     @required TimeoutConfiguration timeoutConfiguration,
//     StopwatchFactory stopwatchFactory = const StopwatchFactory(),
//   }) : _terminal = terminal,
//        _stdio = stdio,
//        _timeoutConfiguration = timeoutConfiguration,
//        _stopwatchFactory = stopwatchFactory,
//        _outputPreferences = outputPreferences;

//   final Terminal _terminal;
//   final Stdio _stdio;
//   final TimeoutConfiguration _timeoutConfiguration;
//   final StopwatchFactory _stopwatchFactory;
//   final OutputPreferences _outputPreferences;

//   /// Create the appropriate logger for the current platform and configuration.
//   Logger createLogger({
//     @required bool verbose,
//     @required bool machine,
//     @required bool daemon,
//     @required bool windows,
//   }) {
//     Logger logger;
//     if (windows) {
//       logger = WindowsStdoutLogger(
//         terminal: _terminal,
//         stdio: _stdio,
//         outputPreferences: _outputPreferences,
//         timeoutConfiguration: _timeoutConfiguration,
//         stopwatchFactory: _stopwatchFactory,
//       );
//     } else {
//       logger = StdoutLogger(
//         terminal: _terminal,
//         stdio: _stdio,
//         outputPreferences: _outputPreferences,
//         timeoutConfiguration: _timeoutConfiguration,
//         stopwatchFactory: _stopwatchFactory
//       );
//     }
//     if (verbose) {
//       logger = VerboseLogger(logger, stopwatchFactory: _stopwatchFactory);
//     }
//     if (daemon) {
//       return NotifyingLogger(verbose: verbose, parent: logger);
//     }
//     if (machine) {
//       return AppRunLogger(parent: logger);
//     }
//     return logger;
//   }
// }
