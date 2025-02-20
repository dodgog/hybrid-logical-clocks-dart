import 'package:hybrid_logical_clocks/hybrid_logical_clocks.dart';

void main() {
  // Node name is important for breaking ties when ordering
  HLC.initialize(clientNode: ClientNode("node123"));

  // Issue a local timestamp and get a string representation
  final localEventStamp = HLC().issueLocalEventPacked();
  // 2025-02-20T00:45:58.249062Z-0000-node123
  print(localEventStamp);

  // Receive a mock packed representation of a timestamp from another client
  // 2025-02-20T00:57:09.251113Z-ff01-node123
  print(HLC().receivePackedAndRepack(
      "${DateTime.now().toUtc().add(Duration(minutes: 11, seconds: 11)).toIso8601String()}-FF00-node999"));

  // Get a send timestamp, then pack:
  final localSendStamp = HLC().send();
  // 2025-02-20T00:57:09.251113Z-ff02-node123
  print(HLC().pack(localSendStamp));

  // Timestamps are comparable and have an ordering
  assert(localEventStamp.compareTo(HLC().pack(localSendStamp)) < 0);
}
