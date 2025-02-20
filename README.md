# Hybrid Logical Clocks

A zero-dependency implementation of Hybrid Logical Clocks (HLC) based on the [original paper](https://cse.buffalo.edu/tech-reports/2014-04.pdf) by Sandeep Kulkarni et al.

HLC provides a mechanism for generating timestamps that respect both the happens-before relationship and are closely tied to physical time, making them ideal for distributed systems.

## Features

- 🚫 Zero external dependencies
- ✅ Tested
- 🔧 Highly customizable configuration
- 📦 Simple, singleton-based API
- 📝 Documented

## Getting started

```bash
dart pub add hybrid_logical_clocks
```

## Usage

```dart
// Initialize HLC with a unique node identifier
HLC.initialize(clientNode: ClientNode("node123"));

// Generate timestamps for local events
final localEventStamp = HLC().issueLocalEventPacked();
// Output: "2024-03-20T10:45:58.249Z-0000-node123"

// Process timestamps from other nodes
final receivedStamp = HLC().receivePackedAndRepack(
  "2024-03-20T10:45:59.251Z-0000-node999"
);

// Timestamps are comparable
assert(localEventStamp.compareTo(receivedStamp) < 0);
```

## Additional information

The HLC implementation is highly customizable. You can configure:
- Maximum allowed clock drift
- Counter representation format
- Timestamp string format
- Physical time source
- Custom timestamp packing/unpacking logic

## Further reading

Besides the original paper, you might find these resources helpful to learn 
about hybrid logical clocks:
- https://jaredforsyth.com/posts/hybrid-logical-clocks/
- https://youtu.be/DEcwa68f-jY?feature=shared
