import 'dart:io';

import 'package:zcode_remote/protocol/conversation.dart';

/// Deterministic algorithm benchmark for ConversationState delta application.
///
/// Run with `dart run tooling/bench_conversation_state.dart`, not a Flutter
/// engine. Fixed fixtures and a fixed delta sequence per round; reports
/// wall-clock per applyFrame call so baseline/optimized runs are comparable.
///
/// Sequence per frame (600 deltas), mirroring a streaming turn over an
/// already-loaded history of N rows:
///   1x row.appended (new assistant row)
///   450x row.delta append to the streaming row (24-char chunk)
///   100x row.upserted of the streaming row
///   30x row.upserted of older rows (deterministic stride)
///   19x row.delta on older rows
void main(List<String> args) {
  final sizes = args.isEmpty ? [1000, 5000, 20000] : args.map(int.parse).toList();
  const warmupRounds = 3;
  const measuredRounds = 7;
  const deltasPerFrame = 600;

  final out = stdout;
  writeln(out, {'bench': 'conversation_state.applyFrame', 'deltasPerFrame': deltasPerFrame});

  for (final n in sizes) {
    // ---- fixture: snapshot with N user/assistant rows ----
    final rows = <Map<String, dynamic>>[
      for (var i = 1; i <= n; i++)
        {
          'rowId': i,
          'kind': i.isOdd ? 'user' : 'assistantText',
          'text': 'row $i ${'x' * 80}',
          'state': 'complete',
        }
    ];

    // ---- fixed delta sequence for one frame ----
    final deltas = buildDeltas(n);
    assert(deltas.length == deltasPerFrame);

    final state = ConversationState();
    var seq = 0;
    // Load the N-row history through the real snapshot path so delta
    // application runs against the fully populated rows list.
    seq += 1;
    var seedGap = false;
    final seedOk = state.applyFrame({
      'payload': {
        'kind': 'snapshot',
        'snapshot': {
          'logEpoch': 'bench-epoch',
          'revision': 1,
          'rows': {
            'window': rows,
            'totalCount': n,
            'firstRowId': 1,
          },
        },
      },
      'toSeq': seq,
    }, onGap: () => seedGap = true);
    if (!seedOk || seedGap) {
      throw StateError('snapshot seed rejected at N=$n');
    }
    if (state.rows.length != n) {
      throw StateError('snapshot seed loaded ${state.rows.length} rows, want $n');
    }

    int runFrame() {
      seq += 1;
      var gap = false;
      final ok = state.applyFrame({
        'payload': {'kind': 'deltas', 'deltas': deltas},
        'fromSeq': seq - 1,
        'toSeq': seq,
      }, onGap: () => gap = true);
      if (!ok || gap) {
        throw StateError('benchmark frame rejected (ok=$ok gap=$gap) at N=$n');
      }
      return seq;
    }

    // seed the streaming rows once so upserts/deltas hit existing rows
    runFrame();

    for (var i = 0; i < warmupRounds; i++) {
      runFrame();
    }
    final samples = <int>[];
    for (var i = 0; i < measuredRounds; i++) {
      final sw = Stopwatch()..start();
      runFrame();
      sw.stop();
      samples.add(sw.elapsedMicroseconds);
    }
    final sorted = samples.toList()..sort();
    final median = sorted[sorted.length ~/ 2];
    final mean = samples.reduce((a, b) => a + b) / samples.length;
    writeln(out, {
      'rows': n,
      'median_us': median,
      'mean_us': mean.round(),
      'min_us': sorted.first,
      'max_us': sorted.last,
      'rounds': measuredRounds,
      'us_per_delta_median': (median / deltasPerFrame).toStringAsFixed(3),
    });
  }
}

List<Map<String, dynamic>> buildDeltas(int n) {
  const streamingRowId = 100000000; // appended below, then targeted
  final deltas = <Map<String, dynamic>>[
    {
      'op': 'row.appended',
      'row': {
        'rowId': streamingRowId,
        'kind': 'assistantText',
        'text': '',
        'state': 'streaming',
      },
    },
  ];
  // 450 streaming appends to the newest row (worst case: scan end).
  for (var i = 0; i < 450; i++) {
    deltas.add({
      'op': 'row.delta',
      'rowId': streamingRowId,
      'path': 'text',
      'append': 'chunk $i ${'y' * 16}',
    });
  }
  // 100 upserts of the streaming row (state/usage refresh pattern).
  for (var i = 0; i < 100; i++) {
    deltas.add({
      'op': 'row.upserted',
      'row': {
        'rowId': streamingRowId,
        'kind': 'assistantText',
        'text': 'streaming $i ${'y' * 16}',
        'state': 'streaming',
      },
    });
  }
  // 30 upserts of older rows, deterministic stride over [1..n].
  for (var i = 0; i < 30; i++) {
    final id = ((i * 7919) % n) + 1;
    deltas.add({
      'op': 'row.upserted',
      'row': {
        'rowId': id,
        'kind': 'assistantText',
        'text': 'updated $i ${'x' * 80}',
        'state': 'complete',
      },
    });
  }
  // 19 appends to older rows (status text changes mid-history).
  for (var i = 0; i < 19; i++) {
    final id = ((i * 104729) % n) + 1;
    deltas.add({
      'op': 'row.delta',
      'rowId': id,
      'path': 'text',
      'append': ' tail $i',
    });
  }
  return deltas;
}

void writeln(IOSink out, Map<String, Object?> data) {
  out.writeln(data.toString());
}
