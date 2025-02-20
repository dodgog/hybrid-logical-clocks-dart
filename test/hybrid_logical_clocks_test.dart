import 'dart:math';

import 'package:hybrid_logical_clocks/hybrid_logical_clocks.dart';
import 'package:test/test.dart';

void main() {
  group('ClientNode Tests', () {
    test('ClientNode comparison works correctly', () {
      final node1 = ClientNode('node1');
      final node2 = ClientNode('node2');
      final node1Duplicate = ClientNode('node1');

      expect(node1.compareTo(node2), lessThan(0));
      expect(node2.compareTo(node1), greaterThan(0));
      expect(node1.compareTo(node1Duplicate), equals(0));
    });

    test('ClientNode packing and unpacking works', () {
      final original = ClientNode('test-node-123');
      final packed = original.pack();
      final unpacked = ClientNode.fromPacked(packed);

      expect(unpacked.clientNodeId, equals(original.clientNodeId));
    });
  });

  group('Timestamp Tests', () {
    test('Timestamp comparison works correctly', () {
      final now = DateTime.now().toUtc();
      final later = now.add(Duration(seconds: 1));

      final timestamp1 = Timestamp(now, ClientNode('node1'), 0);
      final timestamp2 = Timestamp(later, ClientNode('node1'), 0);
      final timestamp3 = Timestamp(now, ClientNode('node1'), 1);
      final timestamp4 = Timestamp(now, ClientNode('node2'), 0);

      expect(timestamp1.compareTo(timestamp2), lessThan(0)); // Different times
      expect(timestamp1.compareTo(timestamp3),
          lessThan(0)); // Same time, different counter
      expect(timestamp1.compareTo(timestamp4),
          lessThan(0)); // Same time, same counter, different nodes
    });

    test('Timestamp copyWith works correctly', () {
      final original =
          Timestamp(DateTime.now().toUtc(), ClientNode('node1'), 0);

      final modified =
          original.copyWith(counter: 1, clientNode: ClientNode('node2'));

      expect(modified.logicalTime, equals(original.logicalTime));
      expect(modified.counter, equals(1));
      expect(modified.clientNode.clientNodeId, equals('node2'));
    });
  });

  group('HLC Basic Operations', () {
    final fixedTime = DateTime.utc(2024);

    setUp(() {
      HLC.reset();
    });

    tearDown(() {
      HLC.reset();
    });

    test('Local event generation works', () {
      HLC.initialize(
        clientNode: ClientNode('test-node'),
        timeFunction: () => fixedTime,
      );
      final timestamp = HLC().issueLocalEvent();
      expect(timestamp.logicalTime, equals(fixedTime));
      expect(timestamp.counter, equals(0));
      expect(timestamp.clientNode.clientNodeId, equals('test-node'));
    });

    test('Send operation works', () {
      HLC.initialize(
        clientNode: ClientNode('test-node'),
        timeFunction: () => fixedTime,
      );
      final timestamp = HLC().send();
      expect(timestamp.logicalTime, equals(fixedTime));
      expect(timestamp.counter, equals(0));
    });

    test('Local/Send event with physical time > logical time sets counter to 0',
        () {
      final pastTime = fixedTime.subtract(Duration(seconds: 1));
      HLC.initialize(
        clientNode: ClientNode('test-node'),
        timeFunction: () => fixedTime,
        previousTimestamp: Timestamp(pastTime, ClientNode('test-node'), 5),
      );

      final result = HLC().send();
      expect(result.logicalTime, equals(fixedTime));
      expect(result.counter, equals(0));
    });

    test(
        'Local/Send event with logical time > physical time increments counter',
        () {
      final futureTime = fixedTime.add(Duration(seconds: 1));
      HLC.initialize(
        clientNode: ClientNode('test-node'),
        timeFunction: () => fixedTime,
        previousTimestamp: Timestamp(futureTime, ClientNode('test-node'), 5),
      );

      final result = HLC().send();
      expect(result.logicalTime, equals(futureTime));
      expect(result.counter, equals(6));
    });

    test(
        'Receive with same logical times (ahead of physical) local counter '
        'greater => sets to local counter + 1', () {
      final futureTime = fixedTime.add(Duration(seconds: 1));
      HLC.initialize(
        clientNode: ClientNode('test-node'),
        timeFunction: () => fixedTime,
        previousTimestamp: Timestamp(futureTime, ClientNode('test-node'), 5),
      );

      final incoming = Timestamp(futureTime, ClientNode('other-node'), 3);
      final result = HLC().receive(incoming);
      expect(result.logicalTime, equals(futureTime));
      expect(result.counter, equals(6)); // max(5,3) + 1
    });

    test(
        'Receive with same logical times (ahead of physical) incoming '
        'counter greater => sets to incoming counter + 1', () {
      final futureTime = fixedTime.add(Duration(seconds: 1));
      HLC.initialize(
        clientNode: ClientNode('test-node'),
        timeFunction: () => fixedTime,
        previousTimestamp: Timestamp(futureTime, ClientNode('test-node'), 3),
      );

      final incoming = Timestamp(futureTime, ClientNode('other-node'), 5);
      final result = HLC().receive(incoming);
      expect(result.logicalTime, equals(futureTime));
      expect(result.counter, equals(6)); // max(3,5) + 1
    });

    test(
        'Receive with local logical time greater than physical and incoming '
        '=> increment local', () {
      final futureTime = fixedTime.add(Duration(seconds: 2));
      final incomingTime = fixedTime.add(Duration(seconds: 1));
      HLC.initialize(
        clientNode: ClientNode('test-node'),
        timeFunction: () => fixedTime,
        previousTimestamp: Timestamp(futureTime, ClientNode('test-node'), 5),
      );

      final incoming = Timestamp(incomingTime, ClientNode('other-node'), 3);
      final result = HLC().receive(incoming);
      expect(result.logicalTime, equals(futureTime));
      expect(result.counter, equals(6));
    });

    test(
        'Receive with incoming logical time greater than physical and local '
        '=> increment incoming', () {
      final incomingTime = fixedTime.add(Duration(seconds: 2));
      final localTime = fixedTime.add(Duration(seconds: 1));
      HLC.initialize(
        clientNode: ClientNode('test-node'),
        timeFunction: () => fixedTime,
        previousTimestamp: Timestamp(localTime, ClientNode('test-node'), 5),
      );

      final incoming = Timestamp(incomingTime, ClientNode('other-node'), 3);
      final result = HLC().receive(incoming);
      expect(result.logicalTime, equals(incomingTime));
      expect(result.counter, equals(4));
    });

    test(
        'Receive with physical time greater than both logical times => reset '
        'counter', () {
      final pastLocalTime = fixedTime.subtract(Duration(seconds: 2));
      final pastIncomingTime = fixedTime.subtract(Duration(seconds: 1));
      HLC.initialize(
        clientNode: ClientNode('test-node'),
        timeFunction: () => fixedTime,
        previousTimestamp: Timestamp(pastLocalTime, ClientNode('test-node'), 5),
      );

      final incoming = Timestamp(pastIncomingTime, ClientNode('other-node'), 3);
      final result = HLC().receive(incoming);
      expect(result.logicalTime, equals(fixedTime));
      expect(result.counter, equals(0));
    });
  });

  group('HLC Edge Cases and Error Conditions', () {
    setUp(() {
      HLC.reset();
      HLC.initialize(
        clientNode: ClientNode('test-node'),
        timeFunction: () => DateTime.utc(2024),
        customConfig:
            HLCConfig(numberOfCharactersInCounterHexRepresentation: 1),
      );
    });

    tearDown(() {
      HLC.reset();
    });

    test('Counter overflow throws exception', () {
      final maxCounter = Timestamp(DateTime.utc(2024), ClientNode('test-node'),
          15 // Maximum value for 1 hex character is 15 (0xF)
          );

      HLC().pack(maxCounter);

      final overflowCounter = maxCounter.copyWith(counter: 16);
      expect(() => HLC().pack(overflowCounter),
          throwsA(isA<CounterOverflowException>()));
    });

    test('Clock drift detection works', () {
      final farFuture = DateTime.utc(2024).add(Duration(hours: 2));
      final driftedTimestamp = Timestamp(farFuture, ClientNode('test-node'), 0);

      expect(() => HLC().receive(driftedTimestamp),
          throwsA(isA<ClockDriftException>()));
    });
  });

  group('Real-world Usage Scenarios', () {
    setUp(() {
      HLC.reset();
    });

    tearDown(() {
      HLC.reset();
    });

    test('Simulated distributed event ordering', () {
      HLC.initialize(clientNode: ClientNode('node1'));

      final event1 = HLC().issueLocalEventPacked();

      // Simulate receiving an event from another node
      final receivedEvent = HLC().receivePackedAndRepack(
          "${DateTime.now().toUtc().toIso8601String()}-0001-node2");

      final event2 = HLC().issueLocalEventPacked();

      expect(event1.compareTo(receivedEvent), lessThan(0));
      expect(receivedEvent.compareTo(event2), lessThan(0));
    });
  });
}
