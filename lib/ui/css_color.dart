import 'dart:math' as math;
import 'package:flutter/painting.dart';

/// CSS `color-mix(in oklab, first (1-t), second t)` for sRGB theme tokens.
/// Alpha is premultiplied before interpolation (CSS Color 4 section 12.3).
Color mixOklab(Color first, Color second, double t) {
  if (t <= 0) return first;
  if (t >= 1) return second;
  final a = first.a * (1 - t), b = second.a * t, alpha = a + b;
  if (alpha == 0) return const Color(0x00000000);
  List<double> lab(Color color) {
    double linear(double c) =>
        c <= .04045 ? c / 12.92 : math.pow((c + .055) / 1.055, 2.4).toDouble();
    double root(double c) => c.sign * math.pow(c.abs(), 1 / 3).toDouble();
    final r = linear(color.r), g = linear(color.g), b = linear(color.b);
    final l = root(.4122214708 * r + .5363325363 * g + .0514459929 * b);
    final m = root(.2119034982 * r + .6806995451 * g + .1073969566 * b);
    final s = root(.0883024619 * r + .2817188376 * g + .6299787005 * b);
    return [
      .2104542553 * l + .7936177850 * m - .0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + .4505937099 * s,
      .0259040371 * l + .7827717662 * m - .8086757660 * s
    ];
  }

  final x = lab(first), y = lab(second);
  final mixed = [for (var i = 0; i < 3; i++) (x[i] * a + y[i] * b) / alpha];
  double cube(double c) => c * c * c;
  final l = cube(mixed[0] + .3963377774 * mixed[1] + .2158037573 * mixed[2]);
  final m = cube(mixed[0] - .1055613458 * mixed[1] - .0638541728 * mixed[2]);
  final s = cube(mixed[0] - .0894841775 * mixed[1] - 1.2914855480 * mixed[2]);
  double gamma(double c) =>
      (c <= .0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4) - .055)
          .toDouble()
          .clamp(0.0, 1.0);
  return Color.from(
      alpha: alpha,
      red: gamma(4.0767416621 * l - 3.3077115913 * m + .2309699292 * s),
      green: gamma(-1.2684380046 * l + 2.6097574011 * m - .3413193965 * s),
      blue: gamma(-.0041960863 * l - .7034186147 * m + 1.7076147010 * s));
}
