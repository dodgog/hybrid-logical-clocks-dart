/// A Dart implementation of Hybrid Logical Clocks (HLC).
///
/// HLCs combine the best properties of logical and physical clocks to provide
/// a causally-consistent timestamping mechanism for distributed systems.
///
/// This library provides:
/// * [HLC] - The main Hybrid Logical Clock implementation
/// * [Timestamp] - A representation of HLC timestamps
///
/// Example usage:
/// ```dart
/// final hlc = HLC();
/// final timestamp = hlc.now();
/// ```
///
/// For more information about Hybrid Logical Clocks, see:
/// https://cse.buffalo.edu/tech-reports/2014-04.pdf
library;

export 'src/hlc.dart';
export 'src/timestamp.dart';
