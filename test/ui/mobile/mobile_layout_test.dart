import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/mobile/mobile_layout.dart';

void main() {
  group('MobileLayout.isCompact', () {
    test('standard phone widths are compact at 100% text', () {
      final scaler = TextScaler.noScaling;
      for (final width in [320.0, 344.0, 360.0, 390.0, 412.0, 599.0]) {
        expect(MobileLayout.isCompact(width, scaler), isTrue,
            reason: '$width should be compact');
      }
    });

    test('desktop widths are not compact at 100% text', () {
      final scaler = TextScaler.noScaling;
      for (final width in [600.0, 640.0, 720.0, 834.0, 1000.0, 1180.0]) {
        expect(MobileLayout.isCompact(width, scaler), isFalse,
            reason: '$width should not be compact');
      }
    });

    test('boundary is exact at 600 logical px', () {
      final scaler = TextScaler.noScaling;
      expect(MobileLayout.isCompact(599.999, scaler), isTrue);
      expect(MobileLayout.isCompact(600.0, scaler), isFalse);
    });

    test('threshold scales with system text scale (clamped 1.0–2.0)', () {
      expect(MobileLayout.isCompact(659, TextScaler.linear(1.1)), isTrue);
      expect(MobileLayout.isCompact(661, TextScaler.linear(1.1)), isFalse,
          reason: '600 * 1.1 is the threshold (float-safe margin)');
      expect(MobileLayout.isCompact(839, TextScaler.linear(1.4)), isTrue);
      expect(MobileLayout.isCompact(841, TextScaler.linear(1.4)), isFalse,
          reason: '600 * 1.4 is the threshold (float-safe margin)');
      // At 200% text the threshold grows to 1200, so a 1180 window is
      // intentionally compact (large text needs the mobile layout).
      expect(MobileLayout.isCompact(1180, TextScaler.linear(2.0)), isTrue);
      expect(MobileLayout.isCompact(1201, TextScaler.linear(2.0)), isFalse,
          reason: 'scale clamps at 2.0, so 1200 is the widest threshold');
      expect(MobileLayout.isCompact(720, TextScaler.noScaling), isFalse,
          reason: 'wide-screen acceptance widths stay non-compact at 100%');
    });
  });
}
