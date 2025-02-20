import 'package:hybrid_logical_clocks/src/timestamp.dart';
import 'dart:math';

/// Configuration for Hybrid Logical Clock
///
/// Allows customization of:
/// - Maximum allowed clock drift between logical and physical time
/// - Number of characters used in the hexadecimal counter representation
/// - Number of characters used to represent the timestamp string
/// - Function to get the current physical time
/// - Function to convert LogicalTime to string representation
/// - Function to parse string representation back to LogicalTime
///
/// The [maxCount] is automatically calculated based on the number of characters
/// in the counter representation.
class HLCConfig {
  /// Maximum allowed drift between logical and physical time in milliseconds
  /// Defaults to 1 hour (3,600,000 milliseconds)
  final int maxClockDriftMilliseconds;

  /// Number of characters used to represent the counter in hexadecimal
  /// Defaults to 4 characters, allowing values from 0000 to FFFF
  final int numberOfCharactersInCounterHexRepresentation;

  /// Number of characters used to represent the timestamp string
  /// Defaults to 27 characters for UTC ISO8601
  /// (e.g., "2025-02-20T00:45:58.249062Z")
  final int numberOfCharactersInTimeRepresentation;

  /// Function to get the current physical time
  /// Defaults to UTC DateTime.now().toUtc()
  final LogicalTime Function() getPhysicalTime;

  /// Function to convert LogicalTime to string representation
  /// Defaults to DateTime.toIso8601String()
  final String Function(LogicalTime) packTime;

  /// Function to parse string representation back to LogicalTime
  /// Defaults to DateTime.parse()
  final LogicalTime Function(String) unpackTime;

  /// Maximum allowed counter value, calculated from
  /// [numberOfCharactersInCounterHexRepresentation]
  /// For the default of 4 characters, this is 2^16 - 1 (65535)
  final int maxCount;

  HLCConfig({
    this.maxClockDriftMilliseconds = 3600000, // 1 hour
    this.numberOfCharactersInCounterHexRepresentation = 4,
    this.numberOfCharactersInTimeRepresentation = 27,
    LogicalTime Function()? getPhysicalTime,
    String Function(LogicalTime)? packTime,
    LogicalTime Function(String)? unpackTime,
  })  : getPhysicalTime = getPhysicalTime ?? (() => DateTime.now().toUtc()),
        packTime = packTime ?? ((time) => time.toIso8601String()),
        unpackTime = unpackTime ?? ((str) => DateTime.parse(str)),
        maxCount =
            pow(2, 4 * numberOfCharactersInCounterHexRepresentation).toInt() -
                1;
}

class CounterOverflowException implements Exception {
  String message;
  CounterOverflowException(this.message);
}

class ClientException implements Exception {
  String message;
  ClientException(this.message);
}

class TimestampFormatException implements Exception {
  String message;
  TimestampFormatException(this.message);
}

class ClockDriftException implements Exception {
  String message;
  ClockDriftException(this.message);
}

/// Implementation of Hybrid Logical Clocks (HLC)
///
/// HLC provides a mechanism for generating timestamps that respect both the
/// happens-before relationship and are closely tied to physical time.
///
/// Before using HLC, you must initialize it with [initialize]:
/// ```
/// HLC.initialize(clientNode: ClientNode("node123"));
/// ```
///
/// Then you can use it to:
/// - Generate timestamps for local events
/// - Generate timestamps for sending messages
/// - Process received timestamps
///
/// The implementation follows a singleton pattern, ensuring consistent
/// clock state across your application.
class HLC {
  HLC._({
    required this.clientNode,
    LogicalTime Function()? timeFunction,
    HLCConfig? customConfig,
    Timestamp? previousTimestamp,
  })  : _getPhysicalTime = timeFunction ?? (() => DateTime.now().toUtc()),
        config = customConfig ?? HLCConfig() {

    if (previousTimestamp != null) {
      if (previousTimestamp?.clientNode != clientNode){
        throw ClientException("Previous issuing client differs from current");
      }
    }
    _setTimestamp(previousTimestamp ??
        Timestamp(
          DateTime.fromMillisecondsSinceEpoch(0),
          clientNode,
          0,
        ));
  }

  static HLC? _instance;

  final ClientNode clientNode;
  final LogicalTime Function() _getPhysicalTime;
  final HLCConfig config;
  late Timestamp _timestamp;

  factory HLC() {
    if (_instance == null) {
      throw StateError('HLC not initialized. Call HLC.initialize() first.');
    }
    return _instance!;
  }

  /// Initializes the HLC singleton with required configuration
  ///
  /// Must be called before using any HLC functionality.
  ///
  /// Example:
  /// ```
  /// HLC.initialize(clientNode: ClientNode("node123"));
  /// ```
  ///
  /// Optional [previousTimestamp] allows resuming from a previously
  /// issued timestamp.
  /// The [previousTimestamp] must be from the same client node and must follow
  /// the configured format.
  ///
  /// Throws:
  /// - [StateError] if HLC is already initialized
  /// - [ArgumentError] if previousTimestamp is from a different client node
  /// - [CounterOverflowException] if previousTimestamp counter exceeds maxCount
  /// - [ClockDriftException] if previousTimestamp exceeds max clock drift
  static void initialize({
    required ClientNode clientNode,
    DateTime Function()? timeFunction,
    HLCConfig? customConfig,
    Timestamp? previousTimestamp,
  }) {
    if (_instance != null) {
      throw StateError('HLC already initialized.');
    }

    _instance = HLC._(
      clientNode: clientNode,
      timeFunction: timeFunction,
      customConfig: customConfig,
      previousTimestamp: previousTimestamp
    );
  }

  /// Resets the HLC singleton instance
  ///
  /// WARNING:
  /// No reason to use in real life systems, but good for testing
  static void reset() {
    _instance = null;
  }

  /// Issues a timestamp for a local event
  ///
  /// Example:
  /// ```
  /// final timestamp = HLC().issueLocalEvent();
  /// ```
  Timestamp issueLocalEvent() {
    return _localEventOrSend();
  }

  /// Issues a timestamp for a local event and returns it in packed string format
  ///
  /// Example:
  /// ```
  /// final packedTimestamp = HLC().issueLocalEventPacked();
  /// // Format: "2025-02-20T00:45:58.249062Z-0000-node123"
  /// ```
  String issueLocalEventPacked() {
    return pack(_localEventOrSend());
  }

  /// Generates a timestamp for sending to another node
  ///
  /// Example:
  /// ```
  /// final sendTimestamp = HLC().send();
  /// ```
  Timestamp send() {
    return _localEventOrSend();
  }

  /// Generates a timestamp for sending and returns it in packed string format
  ///
  /// Example:
  /// ```
  /// final packedSendTimestamp = HLC().sendPacked();
  /// // Format: "2025-02-20T00:45:58.249062Z-0000-node123"
  /// ```
  String sendPacked() {
    return pack(_localEventOrSend());
  }

  /// Processes a received packed timestamp and returns a new timestamp
  ///
  /// Example:
  /// ```
  /// final newTimestamp = HLC().receivePacked("2025-02-20T00:45:58.249062Z-0000-node999");
  /// ```
  Timestamp receivePacked(String packedTimestamp) {
    return receive(unpack(packedTimestamp));
  }

  /// Processes a received packed timestamp and returns a new packed timestamp
  ///
  /// Example:
  /// ```
  /// final newPackedTimestamp = HLC().receivePackedAndRepack(
  ///   "2025-02-20T00:45:58.249062Z-0000-node999"
  /// );
  /// ```
  String receivePackedAndRepack(String packedTimestamp) {
    return pack(receive(unpack(packedTimestamp)));
  }

  /// Processes a received timestamp and returns a new timestamp
  ///
  /// This is the core timestamp merge logic that maintains the happens-before
  /// relationship while keeping logical time close to physical time.
  Timestamp receive(Timestamp incoming) {
    final now = _getPhysicalTime();
    final newLogicalTime = [now, incoming.logicalTime, _timestamp.logicalTime]
        .reduceToMaxWithCompareTo();

    late final int newCounter;
    if (newLogicalTime == _timestamp.logicalTime &&
        newLogicalTime == incoming.logicalTime) {
      newCounter = max(_timestamp.counter, incoming.counter) + 1;
    } else if (newLogicalTime == _timestamp.logicalTime) {
      newCounter = _timestamp.counter + 1;
    } else if (newLogicalTime == incoming.logicalTime) {
      newCounter = incoming.counter + 1;
    } else {
      newCounter = 0;
    }

    final newTimestamp = _timestamp.copyWith(
      logicalTime: newLogicalTime,
      counter: newCounter,
    );

    return _setTimestamp(newTimestamp, physicalDriftReferenceTime: now);
  }

  /// Converts a timestamp to its string representation
  ///
  /// Format: "{TIME_STRING}-{HEX_COUNTER}-{NODE_ID}"
  /// Example: "2025-02-20T00:45:58.249062Z-0000-node123"
  String pack(Timestamp timestamp) {
    if (timestamp.counter > config.maxCount) {
      throw CounterOverflowException(
          "Counter exceeded the limit of ${config.maxCount}");
    }

    final timeString = config.packTime(timestamp.logicalTime);
    final countString = timestamp.counter
        .toRadixString(16)
        .padLeft(config.numberOfCharactersInCounterHexRepresentation, '0');
    final nodeString = timestamp.clientNode.pack();

    return "$timeString-$countString-$nodeString";
  }

  /// Converts a packed string representation back to a timestamp
  ///
  /// Expects format: "{TIME_STRING}-{HEX_COUNTER}-{NODE_ID}"
  /// Throws [TimestampFormatException] if the format is invalid
  Timestamp unpack(String packed) {
    final logicalTime = config.unpackTime(
        packed.substring(0, config.numberOfCharactersInTimeRepresentation));
    final counter = int.parse(
        packed.substring(
            config.numberOfCharactersInTimeRepresentation + 1,
            config.numberOfCharactersInTimeRepresentation +
                1 +
                config.numberOfCharactersInCounterHexRepresentation),
        radix: 16);
    final clientNode = ClientNode.fromPacked(packed.substring(
        config.numberOfCharactersInTimeRepresentation +
            1 +
            config.numberOfCharactersInCounterHexRepresentation +
            1));

    if (counter > config.maxCount) {
      throw CounterOverflowException(
          "Counter exceeded the limit of ${config.maxCount}");
    }

    return Timestamp(logicalTime, clientNode, counter);
  }

  Timestamp _localEventOrSend() {
    final now = _getPhysicalTime();

    late final Timestamp newTimestamp;

    if (_timestamp.logicalTime.compareTo(now) > 0) {
      newTimestamp = _timestamp.copyWith(counter: _timestamp.counter + 1);
      return _setTimestamp(newTimestamp, physicalDriftReferenceTime: now);
    }
    newTimestamp = _timestamp.copyWith(logicalTime: now, counter: 0);
    return _setTimestamp(newTimestamp, physicalDriftReferenceTime: now);
  }

  Timestamp _setTimestamp(Timestamp newTimestamp,
      {LogicalTime? physicalDriftReferenceTime}) {
    if (newTimestamp.counter > config.maxCount) {
      throw CounterOverflowException(
          "Counter exceeded the limit of ${config.maxCount}");
    }
    if (physicalDriftReferenceTime != null) {
      if (newTimestamp.logicalTime
              .difference(physicalDriftReferenceTime)
              .inMilliseconds
              .abs() >
          config.maxClockDriftMilliseconds) {
        throw ClockDriftException("Logical time drifted from physical time by "
            "more than ${config.maxClockDriftMilliseconds} ms");
      }
    }
    return _timestamp = newTimestamp;
  }
}

extension _ReduceToMaxWithCompareTo<T extends Comparable<T>> on List<T> {
  T reduceToMaxWithCompareTo() {
    return reduce((t1, t2) => t1.compareTo(t2) > 0 ? t1 : t2);
  }
}
