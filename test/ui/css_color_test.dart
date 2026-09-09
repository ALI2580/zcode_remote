import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/css_color.dart';

void main() {
  test('Oklab midpoint uses perceptual lightness, not gamma RGB averaging', () {
    final middle =
        mixOklab(const Color(0xFF000000), const Color(0xFFFFFFFF), .5);
    // L=0.5 maps to linear RGB=0.125, then the sRGB transfer curve.
    expect(middle.r, closeTo(.38857286, .000001));
    expect(middle.g, closeTo(middle.r, .000001));
    expect(middle.b, closeTo(middle.r, .000001));
    expect(middle.a, 1);
  });
  test('transparent colors do not darken a premultiplied mix', () {
    const blue = Color(0xFF0B7FFF);
    final mixed = mixOklab(const Color(0x00FFFFFF), blue, .78);
    expect(mixed.a, closeTo(.78, .000001));
    expect(mixed.r, closeTo(blue.r, .000001));
    expect(mixed.g, closeTo(blue.g, .000001));
    expect(mixed.b, closeTo(blue.b, .000001));
  });
}
