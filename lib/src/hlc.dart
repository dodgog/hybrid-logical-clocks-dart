import 'package:hybrid_logical_clocks/src/timestamp.dart';

class HLCConfig {
  final int maxClockDriftMilliseconds;
  final int numberOfCharactersInCounterHexRepresentation;
  final int maxCount;

  const HLCConfig({
    this.maxClockDriftMilliseconds = 3600000, // 1 hour
    this.numberOfCharactersInCounterHexRepresentation = 4,
  }) : maxCount = 2 ^ (4 * numberOfCharactersInCounterHexRepresentation) - 1;
}

class CounterOverflowException implements Exception {
  String message;
  CounterOverflowException(this.message);
}

class TimestampFormatException implements Exception {
  String message;
  TimestampFormatException(this.message);
}

class ClockDriftException implements Exception {
  String message;
  ClockDriftException(this.message);
}

class HLC {
  HLC._({
    required this.clientNode,
    LogicalTime Function()? timeFunction,
    HLCConfig? customConfig,
  })  : _getPhysicalTime = timeFunction ?? DateTime.now,
        _timestamp = Timestamp(
          DateTime.fromMillisecondsSinceEpoch(0),
          clientNode,
          0,
        ),
        config = customConfig ?? HLCConfig();

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

  static void initialize({
    required ClientNode clientNode,
    DateTime Function()? timeFunction,
  }) {
    if (_instance != null) {
      throw StateError('HLC already initialized.');
    }
    _instance = HLC._(
      clientNode: clientNode,
      timeFunction: timeFunction,
    );
  }

  Timestamp issueLocalEvent() {
    return _localEventOrSend();
  }

  String issueLocalEventPacked() {
    return pack(_localEventOrSend());
  }

  Timestamp send() {
    return _localEventOrSend();
  }

  String sendPacked() {
    return pack(_localEventOrSend());
  }

  Timestamp receivePacked(String packedTimestamp){
    return receive(unpack(packedTimestamp));
  }

  Timestamp receivePackedAndRepack(String packedTimestamp){
    return receive(unpack(packedTimestamp));
  }

  Timestamp receive(Timestamp incoming) {
    final now = _getPhysicalTime();
    final newLogicalTime = [now, incoming.logicalTime, _timestamp.logicalTime]
        .reduceToMaxWithCompareTo();

    late final int newCounter;
    if (newLogicalTime == _timestamp.logicalTime &&
        newLogicalTime == incoming.logicalTime) {
      newCounter = ((_timestamp.counter > incoming.counter)
              ? _timestamp.counter
              : incoming.counter) +
          1;
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

    return _setTimestamp(newTimestamp, now);
  }

  String pack(Timestamp timestamp) {
    final timeString = timestamp.logicalTime.toIso8601String();
    final countString = timestamp.counter.toRadixString(16);
    final nodeString = timestamp.clientNode.pack();

    return "$timeString-$countString-$nodeString";
  }

  Timestamp unpack(String packed) {
    final parts = packed.split('-');
    if (parts.length != 3) {
      throw TimestampFormatException(
          'Invalid timestamp format of string $packed');
    }

    final logicalTime = DateTime.parse(parts[0]);
    final counter = int.parse(parts[1], radix: 16);
    final clientNode = ClientNode.fromPacked(parts[2]);

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
      return _setTimestamp(newTimestamp, now);
    }
    newTimestamp = _timestamp.copyWith(logicalTime: now, counter: 0);
    return _setTimestamp(newTimestamp, now);
  }

  Timestamp _setTimestamp(
      Timestamp newTimestamp, LogicalTime physicalDriftReferenceTime) {
    if (newTimestamp.counter > config.maxCount) {
      throw CounterOverflowException(
          "Counter exceeded the limit of ${config.maxCount}");
    }
    if (newTimestamp.logicalTime.compareTo(physicalDriftReferenceTime) > 0) {
      throw ClockDriftException("Logical time drifted from physical time by "
          "more than ${config.maxClockDriftMilliseconds} ms");
    }
    return _timestamp = newTimestamp;
  }
}

extension _ReduceToMaxWithCompareTo<T extends Comparable<T>> on List<T> {
  T reduceToMaxWithCompareTo() {
    return reduce((t1, t2) => t1.compareTo(t2) > 0 ? t1 : t2);
  }
}
