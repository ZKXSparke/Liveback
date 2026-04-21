// One-shot tool to generate the SEF writer golden fixtures.
//
// Usage:   dart run tool/gen_sef_fixtures.dart
//
// Writes:
//   test/fixtures/sef_writer/inline_marker_24bytes.bin
//   test/fixtures/sef_writer/single_record_32bytes.bin
//
// The produced bytes are asserted byte-exact by sef_writer_test.dart.
// The offset 0x346B8C is the value from Doc 2 §3.6 (close to Sample A's
// 0x346B7C — we deliberately use a slightly different value to prove
// the trailer is not a copy of Sample A).

import 'dart:io';

import 'package:liveback/services/sef_writer.dart';

void main() async {
  final inline = SefWriter.buildInlineMarker();
  final trailer = SefWriter.buildSefTrailer(offsetFromSefhToInlineMarker: 0x346B8C);

  final inlinePath = 'test/fixtures/sef_writer/inline_marker_24bytes.bin';
  final trailerPath = 'test/fixtures/sef_writer/single_record_32bytes.bin';

  await File(inlinePath).writeAsBytes(inline, flush: true);
  await File(trailerPath).writeAsBytes(trailer, flush: true);

  stdout.writeln('wrote ${inline.length} bytes -> $inlinePath');
  stdout.writeln('wrote ${trailer.length} bytes -> $trailerPath');
}
