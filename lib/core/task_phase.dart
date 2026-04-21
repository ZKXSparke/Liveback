// Owner: shared (Phase 1 SSoT). Reference: Doc 1 §A.2.
// DO NOT edit without an architecture amendment to Doc 1 Appendix A.
//
// TaskPhase is emitted by FixService.fix via the onPhase callback and is
// also carried inside PhaseChanged worker events (Doc 1 §A.4). The zh labels
// are the single source of truth for the TaskList row "current phase" text.

/// The three coarse-grained phases of the single-file fix pipeline.
///
/// Worker (Doc 1 §A.4) and fix_service (Doc 2 §6) MUST agree on this enum;
/// any new phase is an architecture amendment that propagates to both docs.
enum TaskPhase {
  /// motion_photo_parser scanning JPEG/MP4/SEF segments.
  parsing,

  /// sef_writer building the inline marker + SEFH/SEFT trailer bytes.
  injectingSef,

  /// Streaming the output bytes to the sandbox file.
  writing,
}

extension TaskPhaseLabel on TaskPhase {
  /// zh-CN label shown on TaskList rows (v1.1 §5.3 + brand §5.2).
  String get zh => switch (this) {
        TaskPhase.parsing => '解析中',
        TaskPhase.injectingSef => '注入 SEF',
        TaskPhase.writing => '写入中',
      };
}
