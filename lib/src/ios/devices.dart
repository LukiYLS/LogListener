// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:process/process.dart';
import 'package:vm_service/vm_service.dart' as vm_service;

import '../application_package.dart';
import '../base/common.dart';
import '../base/file_system.dart';
import '../base/io.dart';
import '../base/logger.dart';
import '../base/os.dart';
import '../base/platform.dart';
import '../base/utils.dart';
import '../build_info.dart';
import '../convert.dart';
import '../device.dart';
import '../globals.dart' as globals;
import '../macos/xcode.dart';
import '../mdns_discovery.dart';
import '../project.dart';
import '../protocol_discovery.dart';
import '../vmservice.dart';
import 'fallback_discovery.dart';
import 'ios_deploy.dart';
import 'ios_workflow.dart';
import 'iproxy.dart';
import 'mac.dart';

class IOSDevices extends PollingDeviceDiscovery {
  IOSDevices({
    @required Platform platform,
    @required XCDevice xcdevice,
    @required IOSWorkflow iosWorkflow,
    @required Logger logger,
  }) : _platform = platform,
       _xcdevice = xcdevice,
       _iosWorkflow = iosWorkflow,
       _logger = logger,
       super('iOS devices');

  final Platform _platform;
  final XCDevice _xcdevice;
  final IOSWorkflow _iosWorkflow;
  final Logger _logger;

  @override
  bool get supportsPlatform => _platform.isMacOS;

  @override
  bool get canListAnything => _iosWorkflow.canListDevices;

  StreamSubscription<Map<XCDeviceEvent, String>> _observedDeviceEventsSubscription;

  @override
  Future<void> startPolling() async {
    if (!_platform.isMacOS) {
      throw UnsupportedError(
        'Control of iOS devices or simulators only supported on macOS.'
      );
    }
    if (!_xcdevice.isInstalled) {
      return;
    }

    deviceNotifier ??= ItemListNotifier<Device>();

    // Start by populating all currently attached devices.
    deviceNotifier.updateWithNewList(await pollingGetDevices());

    // cancel any outstanding subscriptions.
    await _observedDeviceEventsSubscription?.cancel();
    _observedDeviceEventsSubscription = _xcdevice.observedDeviceEvents()?.listen(
      _onDeviceEvent,
      onError: (dynamic error, StackTrace stack) {
        _logger.printTrace('Process exception running xcdevice observe:\n$error\n$stack');
      }, onDone: () {
        // If xcdevice is killed or otherwise dies, polling will be stopped.
        // No retry is attempted and the polling client will have to restart polling
        // (restart the IDE). Avoid hammering on a process that is
        // continuously failing.
        _logger.printTrace('xcdevice observe stopped');
      },
      cancelOnError: true,
    );
  }

  Future<void> _onDeviceEvent(Map<XCDeviceEvent, String> event) async {
    final XCDeviceEvent eventType = event.containsKey(XCDeviceEvent.attach) ? XCDeviceEvent.attach : XCDeviceEvent.detach;
    final String deviceIdentifier = event[eventType];
    final Device knownDevice = deviceNotifier.items
      .firstWhere((Device device) => device.id == deviceIdentifier, orElse: () => null);

    // Ignore already discovered devices (maybe populated at the beginning).
    if (eventType == XCDeviceEvent.attach && knownDevice == null) {
      // There's no way to get details for an individual attached device,
      // so repopulate them all.
      final List<Device> devices = await pollingGetDevices();
      deviceNotifier.updateWithNewList(devices);
    } else if (eventType == XCDeviceEvent.detach && knownDevice != null) {
      deviceNotifier.removeItem(knownDevice);
    }
  }

  @override
  Future<void> stopPolling() async {
    await _observedDeviceEventsSubscription?.cancel();
  }

  @override
  Future<List<Device>> pollingGetDevices({ Duration timeout }) async {
    if (!_platform.isMacOS) {
      throw UnsupportedError(
        'Control of iOS devices or simulators only supported on macOS.'
      );
    }

    return await _xcdevice.getAvailableIOSDevices(timeout: timeout);
  }

  @override
  Future<List<String>> getDiagnostics() async {
    if (!_platform.isMacOS) {
      return const <String>[
        'Control of iOS devices or simulators only supported on macOS.'
      ];
    }

    return await _xcdevice.getDiagnostics();
  }
}

enum IOSDeviceInterface {
  none,
  usb,
  network,
}

class IOSDevice extends Device {
  IOSDevice(String id, {
    @required FileSystem fileSystem,
    @required this.name,
    @required this.cpuArchitecture,
    @required this.interfaceType,
    @required String sdkVersion,
    @required Platform platform,
    @required IOSDeploy iosDeploy,
    @required IMobileDevice iMobileDevice,
    @required IProxy iProxy,
    @required Logger logger,
    @required VmServiceConnector vmServiceConnectUri,
  })
    : _sdkVersion = sdkVersion,
      _iosDeploy = iosDeploy,
      _iMobileDevice = iMobileDevice,
      _iproxy = iProxy,
      _fileSystem = fileSystem,
      _logger = logger,
      _platform = platform,
      _vmServiceConnectUri = vmServiceConnectUri,
        super(
          id,
          category: Category.mobile,
          platformType: PlatformType.ios,
          ephemeral: true,
      ) {
    if (!platform.isMacOS) {
      assert(false, 'Control of iOS devices or simulators only supported on Mac OS.');
      return;
    }
  }

  final String _sdkVersion;
  final IOSDeploy _iosDeploy;
  final FileSystem _fileSystem;
  final Logger _logger;
  final Platform _platform;
  final IMobileDevice _iMobileDevice;
  final IProxy _iproxy;
  final VmServiceConnector _vmServiceConnectUri;

  /// May be 0 if version cannot be parsed.
  int get majorSdkVersion {
    final String majorVersionString = _sdkVersion?.split('.')?.first?.trim();
    return majorVersionString != null ? int.tryParse(majorVersionString) ?? 0 : 0;
  }

  @override
  bool get supportsHotReload => interfaceType == IOSDeviceInterface.usb;

  @override
  bool get supportsHotRestart => interfaceType == IOSDeviceInterface.usb;

  @override
  bool get supportsFlutterExit => interfaceType == IOSDeviceInterface.usb;

  @override
  final String name;

  @override
  bool supportsRuntimeMode(BuildMode buildMode) => buildMode != BuildMode.jitRelease;

  final DarwinArch cpuArchitecture;

  final IOSDeviceInterface interfaceType;

  Map<IOSApp, DeviceLogReader> _logReaders;

  DevicePortForwarder _portForwarder;

  @override
  Future<bool> get isLocalEmulator async => false;

  @override
  Future<String> get emulatorId async => null;

  @override
  bool get supportsStartPaused => false;

  @override
  Future<bool> isAppInstalled(
    IOSApp app, {
    String userIdentifier,
  }) async {
    bool result;
    try {
      result = await _iosDeploy.isAppInstalled(
        bundleId: app.id,
        deviceId: id,
      );
    } on ProcessException catch (e) {
      _logger.printError(e.message);
      return false;
    }
    return result;
  }

  @override
  Future<bool> isLatestBuildInstalled(IOSApp app) async => false;

  @override
  Future<bool> installApp(
    IOSApp app, {
    String userIdentifier,
  }) async {
    final Directory bundle = _fileSystem.directory(app.deviceBundlePath);
    if (!bundle.existsSync()) {
      _logger.printError('Could not find application bundle at ${bundle.path}; have you run "flutter build ios"?');
      return false;
    }

    int installationResult;
    try {
      installationResult = await _iosDeploy.installApp(
        deviceId: id,
        bundlePath: bundle.path,
        launchArguments: <String>[],
        interfaceType: interfaceType,
      );
    } on ProcessException catch (e) {
      _logger.printError(e.message);
      return false;
    }
    if (installationResult != 0) {
      _logger.printError('Could not install ${bundle.path} on $id.');
      _logger.printError('Try launching Xcode and selecting "Product > Run" to fix the problem:');
      _logger.printError('  open ios/Runner.xcworkspace');
      _logger.printError('');
      return false;
    }
    return true;
  }

  @override
  Future<bool> uninstallApp(
    IOSApp app, {
    String userIdentifier,
  }) async {
    int uninstallationResult;
    try {
      uninstallationResult = await _iosDeploy.uninstallApp(
        deviceId: id,
        bundleId: app.id,
      );
    } on ProcessException catch (e) {
      _logger.printError(e.message);
      return false;
    }
    if (uninstallationResult != 0) {
      _logger.printError('Could not uninstall ${app.id} on $id.');
      return false;
    }
    return true;
  }

  @override
  bool isSupported() => true;

  @override
  Future<LaunchResult> startApp(
    IOSApp package, {
    String mainPath,
    String route,
    DebuggingOptions debuggingOptions,
    Map<String, dynamic> platformArgs,
    bool prebuiltApplication = false,
    bool ipv6 = false,
    @visibleForTesting Duration fallbackPollingDelay,
    String userIdentifier,
  }) async {
    String packageId;

    if (!prebuiltApplication) {
      // TODO(chinmaygarde): Use mainPath, route.
      _logger.printTrace('Building ${package.name} for $id');

      // Step 1: Build the precompiled/DBC application if necessary.
      final XcodeBuildResult buildResult = await buildXcodeProject(
          app: package as BuildableIOSApp,
          buildInfo: debuggingOptions.buildInfo,
          targetOverride: mainPath,
          buildForDevice: true,
          activeArch: cpuArchitecture,
          deviceID: id,
      );
      if (!buildResult.success) {
        _logger.printError('Could not build the precompiled application for the device.');
        await diagnoseXcodeBuildFailure(buildResult, globals.flutterUsage, _logger);
        _logger.printError('');
        return LaunchResult.failed();
      }
      packageId = buildResult.xcodeBuildExecution?.buildSettings['PRODUCT_BUNDLE_IDENTIFIER'];
    } else {
      if (!await installApp(package)) {
        return LaunchResult.failed();
      }
    }

    packageId ??= package.id;

    // Step 2: Check that the application exists at the specified path.
    final Directory bundle = _fileSystem.directory(package.deviceBundlePath);
    if (!bundle.existsSync()) {
      _logger.printError('Could not find the built application bundle at ${bundle.path}.');
      return LaunchResult.failed();
    }

    // Step 2.5: Generate a potential open port using the provided argument,
    // or randomly with the package name as a seed. Intentionally choose
    // ports within the ephemeral port range.
    final int assumedObservatoryPort = debuggingOptions?.deviceVmServicePort
      ?? math.Random(packageId.hashCode).nextInt(16383) + 49152;

    // Step 3: Attempt to install the application on the device.
    final String dartVmFlags = computeDartVmFlags(debuggingOptions);
    final List<String> launchArguments = <String>[
      '--enable-dart-profiling',
      // These arguments are required to support the fallback connection strategy
      // described in fallback_discovery.dart.
      '--enable-service-port-fallback',
      '--disable-service-auth-codes',
      '--observatory-port=$assumedObservatoryPort',
      if (debuggingOptions.startPaused) '--start-paused',
      if (dartVmFlags.isNotEmpty) '--dart-flags="$dartVmFlags"',
      if (debuggingOptions.useTestFonts) '--use-test-fonts',
      // "--enable-checked-mode" and "--verify-entry-points" should always be
      // passed when we launch debug build via "ios-deploy". However, we don't
      // pass them if a certain environment variable is set to enable the
      // "system_debug_ios" integration test in the CI, which simulates a
      // home-screen launch.
      if (debuggingOptions.debuggingEnabled &&
          _platform.environment['ReplayServerTools_DEBUG_WITHOUT_CHECKED_MODE'] != 'true') ...<String>[
        '--enable-checked-mode',
        '--verify-entry-points',
      ],
      if (debuggingOptions.enableSoftwareRendering) '--enable-software-rendering',
      if (debuggingOptions.skiaDeterministicRendering) '--skia-deterministic-rendering',
      if (debuggingOptions.traceSkia) '--trace-skia',
      if (debuggingOptions.traceAllowlist != null) '--trace-allowlist="${debuggingOptions.traceAllowlist}"',
      if (debuggingOptions.endlessTraceBuffer) '--endless-trace-buffer',
      if (debuggingOptions.dumpSkpOnShaderCompilation) '--dump-skp-on-shader-compilation',
      if (debuggingOptions.verboseSystemLogs) '--verbose-logging',
      if (debuggingOptions.cacheSkSL) '--cache-sksl',
      if (debuggingOptions.purgePersistentCache) '--purge-persistent-cache',
      if (platformArgs['trace-startup'] as bool ?? false) '--trace-startup',
    ];

    final Status installStatus = _logger.startProgress(
        'Installing and launching...',
        timeout: timeoutConfiguration.slowOperation);
    try {
      ProtocolDiscovery observatoryDiscovery;
      if (debuggingOptions.debuggingEnabled) {
        _logger.printTrace('Debugging is enabled, connecting to observatory');
        observatoryDiscovery = ProtocolDiscovery.observatory(
          getLogReader(app: package),
          portForwarder: portForwarder,
          hostPort: debuggingOptions.hostVmServicePort,
          devicePort: debuggingOptions.deviceVmServicePort,
          ipv6: ipv6,
        );
      }
      final int installationResult = await _iosDeploy.runApp(
        deviceId: id,
        bundlePath: bundle.path,
        launchArguments: launchArguments,
        interfaceType: interfaceType,
      );
      if (installationResult != 0) {
        _logger.printError('Could not run ${bundle.path} on $id.');
        _logger.printError('Try launching Xcode and selecting "Product > Run" to fix the problem:');
        _logger.printError('  open ios/Runner.xcworkspace');
        _logger.printError('');
        return LaunchResult.failed();
      }

      if (!debuggingOptions.debuggingEnabled) {
        return LaunchResult.succeeded();
      }

      _logger.printTrace('Application launched on the device. Waiting for observatory port.');
      final FallbackDiscovery fallbackDiscovery = FallbackDiscovery(
        logger: _logger,
        mDnsObservatoryDiscovery: MDnsObservatoryDiscovery.instance,
        portForwarder: portForwarder,
        protocolDiscovery: observatoryDiscovery,
        flutterUsage: globals.flutterUsage,
        pollingDelay: fallbackPollingDelay,
        vmServiceConnectUri: _vmServiceConnectUri,
      );
      final Uri localUri = await fallbackDiscovery.discover(
        assumedDevicePort: assumedObservatoryPort,
        device: this,
        usesIpv6: ipv6,
        hostVmservicePort: debuggingOptions.hostVmServicePort,
        packageId: packageId,
        packageName: FlutterProject.current().manifest.appName,
      );
      if (localUri == null) {
        return LaunchResult.failed();
      }
      return LaunchResult.succeeded(observatoryUri: localUri);
    } on ProcessException catch (e) {
      _logger.printError(e.message);
      return LaunchResult.failed();
    } finally {
      installStatus.stop();
    }
  }

  @override
  Future<bool> stopApp(
    IOSApp app, {
    String userIdentifier,
  }) async {
    // Currently we don't have a way to stop an app running on iOS.
    return false;
  }

  @override
  Future<TargetPlatform> get targetPlatform async => TargetPlatform.ios;

  @override
  Future<String> get sdkNameAndVersion async => 'iOS $_sdkVersion';

  @override
  DeviceLogReader getLogReader({
    IOSApp app,
    bool includePastLogs = false,
  }) {
    assert(!includePastLogs, 'Past log reading not supported on iOS devices.');
    _logReaders ??= <IOSApp, DeviceLogReader>{};
    return _logReaders.putIfAbsent(app, () => IOSDeviceLogReader.create(
      device: this,
      app: app,
      iMobileDevice: _iMobileDevice,
    ));
  }

  @visibleForTesting
  void setLogReader(IOSApp app, DeviceLogReader logReader) {
    _logReaders ??= <IOSApp, DeviceLogReader>{};
    _logReaders[app] = logReader;
  }

  @override
  DevicePortForwarder get portForwarder => _portForwarder ??= IOSDevicePortForwarder(
    logger: _logger,
    iproxy: _iproxy,
    id: id,
    operatingSystemUtils: globals.os,
  );

  @visibleForTesting
  set portForwarder(DevicePortForwarder forwarder) {
    _portForwarder = forwarder;
  }

  @override
  void clearLogs() { }

  @override
  bool get supportsScreenshot => _iMobileDevice.isInstalled;

  @override
  Future<void> takeScreenshot(File outputFile) async {
    await _iMobileDevice.takeScreenshot(outputFile, id, interfaceType);
  }

  @override
  bool isSupportedForProject(FlutterProject flutterProject) {
    return flutterProject.ios.existsSync();
  }

  @override
  Future<void> dispose() async {
    _logReaders?.forEach((IOSApp application, DeviceLogReader logReader) {
      logReader.dispose();
    });
    await _portForwarder?.dispose();
  }
}

/// Decodes a vis-encoded syslog string to a UTF-8 representation.
///
/// Apple's syslog logs are encoded in 7-bit form. Input bytes are encoded as follows:
/// 1. 0x00 to 0x19: non-printing range. Some ignored, some encoded as <...>.
/// 2. 0x20 to 0x7f: as-is, with the exception of 0x5c (backslash).
/// 3. 0x5c (backslash): octal representation \134.
/// 4. 0x80 to 0x9f: \M^x (using control-character notation for range 0x00 to 0x40).
/// 5. 0xa0: octal representation \240.
/// 6. 0xa1 to 0xf7: \M-x (where x is the input byte stripped of its high-order bit).
/// 7. 0xf8 to 0xff: unused in 4-byte UTF-8.
///
/// See: [vis(3) manpage](https://www.freebsd.org/cgi/man.cgi?query=vis&sektion=3)
String decodeSyslog(String line) {
  // UTF-8 values for \, M, -, ^.
  const int kBackslash = 0x5c;
  const int kM = 0x4d;
  const int kDash = 0x2d;
  const int kCaret = 0x5e;

  // Mask for the UTF-8 digit range.
  const int kNum = 0x30;

  // Returns true when `byte` is within the UTF-8 7-bit digit range (0x30 to 0x39).
  bool isDigit(int byte) => (byte & 0xf0) == kNum;

  // Converts a three-digit ASCII (UTF-8) representation of an octal number `xyz` to an integer.
  int decodeOctal(int x, int y, int z) => (x & 0x3) << 6 | (y & 0x7) << 3 | z & 0x7;

  try {
    final List<int> bytes = utf8.encode(line);
    final List<int> out = <int>[];
    for (int i = 0; i < bytes.length;) {
      if (bytes[i] != kBackslash || i > bytes.length - 4) {
        // Unmapped byte: copy as-is.
        out.add(bytes[i++]);
      } else {
        // Mapped byte: decode next 4 bytes.
        if (bytes[i + 1] == kM && bytes[i + 2] == kCaret) {
          // \M^x form: bytes in range 0x80 to 0x9f.
          out.add((bytes[i + 3] & 0x7f) + 0x40);
        } else if (bytes[i + 1] == kM && bytes[i + 2] == kDash) {
          // \M-x form: bytes in range 0xa0 to 0xf7.
          out.add(bytes[i + 3] | 0x80);
        } else if (bytes.getRange(i + 1, i + 3).every(isDigit)) {
          // \ddd form: octal representation (only used for \134 and \240).
          out.add(decodeOctal(bytes[i + 1], bytes[i + 2], bytes[i + 3]));
        } else {
          // Unknown form: copy as-is.
          out.addAll(bytes.getRange(0, 4));
        }
        i += 4;
      }
    }
    return utf8.decode(out);
  } on Exception {
    // Unable to decode line: return as-is.
    return line;
  }
}

@visibleForTesting
class IOSDeviceLogReader extends DeviceLogReader {
  IOSDeviceLogReader._(
    this._iMobileDevice,
    this._majorSdkVersion,
    this._deviceId,
    this.name,
    String appName,
  ) {
    _linesController = StreamController<String>.broadcast(
      onListen: _listenToSysLog,
      onCancel: dispose,
    );

    // Match for lines for the runner in syslog.
    //
    // iOS 9 format:  Runner[297] <Notice>:
    // iOS 10 format: Runner(Flutter)[297] <Notice>:
    _runnerLineRegex = RegExp(appName + r'(\(Flutter\))?\[[\d]+\] <[A-Za-z]+>: ');
    // Similar to above, but allows ~arbitrary components instead of "Runner"
    // and "Flutter". The regex tries to strike a balance between not producing
    // false positives and not producing false negatives.
    _anyLineRegex = RegExp(r'\w+(\([^)]*\))?\[\d+\] <[A-Za-z]+>: ');
    _loggingSubscriptions = <StreamSubscription<void>>[];
  }

  /// Create a new [IOSDeviceLogReader].
  factory IOSDeviceLogReader.create({
    @required IOSDevice device,
    @required IOSApp app,
    @required IMobileDevice iMobileDevice,
  }) {
    final String appName = app == null ? '' : app.name.replaceAll('.app', '');
    return IOSDeviceLogReader._(
      iMobileDevice,
      device.majorSdkVersion,
      device.id,
      device.name,
      appName,
    );
  }

  /// Create an [IOSDeviceLogReader] for testing.
  factory IOSDeviceLogReader.test({
    @required IMobileDevice iMobileDevice,
    bool useSyslog = true,
  }) {
    return IOSDeviceLogReader._(
      iMobileDevice, useSyslog ? 12 : 13, '1234', 'test', 'Runner');
  }

  @override
  final String name;
  final int _majorSdkVersion;
  final String _deviceId;
  final IMobileDevice _iMobileDevice;

  // Matches a syslog line from the runner.
  RegExp _runnerLineRegex;
  // Matches a syslog line from any app.
  RegExp _anyLineRegex;

  StreamController<String> _linesController;
  List<StreamSubscription<void>> _loggingSubscriptions;

  @override
  Stream<String> get logLines => _linesController.stream;

  @override
  vm_service.VmService get connectedVMService => _connectedVMService;
  vm_service.VmService _connectedVMService;

  @override
  set connectedVMService(vm_service.VmService connectedVmService) {
    _listenToUnifiedLoggingEvents(connectedVmService);
    _connectedVMService = connectedVmService;
  }

  static const int _minimumUniversalLoggingSdkVersion = 13;

  Future<void> _listenToUnifiedLoggingEvents(vm_service.VmService connectedVmService) async {
    if (_majorSdkVersion < _minimumUniversalLoggingSdkVersion) {
      return;
    }
    try {
      // The VM service will not publish logging events unless the debug stream is being listened to.
      // Listen to this stream as a side effect.
      unawaited(connectedVmService.streamListen('Debug'));

      await Future.wait(<Future<void>>[
        connectedVmService.streamListen(vm_service.EventStreams.kStdout),
        connectedVmService.streamListen(vm_service.EventStreams.kStderr),
      ]);
    } on vm_service.RPCError {
      // Do nothing, since the tool is already subscribed.
    }

    void logMessage(vm_service.Event event) {
      final String message = processVmServiceMessage(event);
      if (message.isNotEmpty) {
        _linesController.add(message);
      }
    }

    _loggingSubscriptions.addAll(<StreamSubscription<void>>[
      connectedVmService.onStdoutEvent.listen(logMessage),
      connectedVmService.onStderrEvent.listen(logMessage),
    ]);
  }

  void _listenToSysLog() {
    // syslog is not written on iOS 13+.
    if (_majorSdkVersion >= _minimumUniversalLoggingSdkVersion) {
      return;
    }
    _iMobileDevice.startLogger(_deviceId).then<void>((Process process) {
      process.stdout.transform<String>(utf8.decoder).transform<String>(const LineSplitter()).listen(_newSyslogLineHandler());
      process.stderr.transform<String>(utf8.decoder).transform<String>(const LineSplitter()).listen(_newSyslogLineHandler());
      process.exitCode.whenComplete(() {
        if (_linesController.hasListener) {
          _linesController.close();
        }
      });
      assert(_idevicesyslogProcess == null);
      _idevicesyslogProcess = process;
    });
  }

  @visibleForTesting
  set idevicesyslogProcess(Process process) => _idevicesyslogProcess = process;
  Process _idevicesyslogProcess;

  // Returns a stateful line handler to properly capture multiline output.
  //
  // For multiline log messages, any line after the first is logged without
  // any specific prefix. To properly capture those, we enter "printing" mode
  // after matching a log line from the runner. When in printing mode, we print
  // all lines until we find the start of another log message (from any app).
  void Function(String line) _newSyslogLineHandler() {
    bool printing = false;

    return (String line) {
      if (printing) {
        if (!_anyLineRegex.hasMatch(line)) {
          _linesController.add(decodeSyslog(line));
          return;
        }

        printing = false;
      }

      final Match match = _runnerLineRegex.firstMatch(line);

      if (match != null) {
        final String logLine = line.substring(match.end);
        // Only display the log line after the initial device and executable information.
        _linesController.add(decodeSyslog(logLine));

        printing = true;
      }
    };
  }

  @override
  void dispose() {
    for (final StreamSubscription<void> loggingSubscription in _loggingSubscriptions) {
      loggingSubscription.cancel();
    }
    _idevicesyslogProcess?.kill();
  }
}

/// A [DevicePortForwarder] specialized for iOS usage with iproxy.
class IOSDevicePortForwarder extends DevicePortForwarder {

  /// Create a new [IOSDevicePortForwarder].
  IOSDevicePortForwarder({
    @required Logger logger,
    @required String id,
    @required IProxy iproxy,
    @required OperatingSystemUtils operatingSystemUtils,
  }) : _logger = logger,
       _id = id,
       _iproxy = iproxy,
       _operatingSystemUtils = operatingSystemUtils;

  /// Create a [IOSDevicePortForwarder] for testing.
  ///
  /// This specifies the path to iproxy as 'iproxy` and the dyLdLibEntry as
  /// 'DYLD_LIBRARY_PATH: /path/to/libs'.
  ///
  /// The device id may be provided, but otherwise defaults to '1234'.
  factory IOSDevicePortForwarder.test({
    @required ProcessManager processManager,
    @required Logger logger,
    String id,
    OperatingSystemUtils operatingSystemUtils,
  }) {
    return IOSDevicePortForwarder(
      logger: logger,
      iproxy: IProxy.test(
        logger: logger,
        processManager: processManager,
      ),
      id: id ?? '1234',
      operatingSystemUtils: operatingSystemUtils,
    );
  }

  final Logger _logger;
  final String _id;
  final IProxy _iproxy;
  final OperatingSystemUtils _operatingSystemUtils;

  @override
  List<ForwardedPort> forwardedPorts = <ForwardedPort>[];

  @visibleForTesting
  void addForwardedPorts(List<ForwardedPort> ports) {
    ports.forEach(forwardedPorts.add);
  }

  static const Duration _kiProxyPortForwardTimeout = Duration(seconds: 1);

  @override
  Future<int> forward(int devicePort, { int hostPort }) async {
    final bool autoselect = hostPort == null || hostPort == 0;
    if (autoselect) {
      final int freePort = await _operatingSystemUtils?.findFreePort();
      // Dynamic port range 49152 - 65535.
      hostPort = freePort == null || freePort == 0 ? 49152 : freePort;
    }

    Process process;

    bool connected = false;
    while (!connected) {
      _logger.printTrace('Attempting to forward device port $devicePort to host port $hostPort');
      process = await _iproxy.forward(devicePort, hostPort, _id);
      // TODO(ianh): This is a flakey race condition, https://github.com/libimobiledevice/libimobiledevice/issues/674
      connected = !await process.stdout.isEmpty.timeout(_kiProxyPortForwardTimeout, onTimeout: () => false);
      if (!connected) {
        process.kill();
        if (autoselect) {
          hostPort += 1;
          if (hostPort > 65535) {
            throw Exception('Could not find open port on host.');
          }
        } else {
          throw Exception('Port $hostPort is not available.');
        }
      }
    }
    assert(connected);
    assert(process != null);

    final ForwardedPort forwardedPort = ForwardedPort.withContext(
      hostPort, devicePort, process,
    );
    _logger.printTrace('Forwarded port $forwardedPort');
    forwardedPorts.add(forwardedPort);
    return hostPort;
  }

  @override
  Future<void> unforward(ForwardedPort forwardedPort) async {
    if (!forwardedPorts.remove(forwardedPort)) {
      // Not in list. Nothing to remove.
      return;
    }

    _logger.printTrace('Unforwarding port $forwardedPort');
    forwardedPort.dispose();
  }

  @override
  Future<void> dispose() async {
    for (final ForwardedPort forwardedPort in forwardedPorts) {
      forwardedPort.dispose();
    }
  }
}
