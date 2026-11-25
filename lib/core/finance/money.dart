/// All money is stored and computed as integer piastres (1 EGP = 100).
/// No floating point is used anywhere in the financial engine.
class Money {
  Money._();
  static const int piastresPerEgp = 100;

  /// Integer division rounding half away from zero.
  static int roundDiv(int numerator, int denominator) {
    if (denominator <= 0) throw ArgumentError('denominator must be > 0');
    if (numerator < 0) return -roundDiv(-numerator, denominator);
    return (2 * numerator + denominator) ~/ (2 * denominator);
  }

  /// Splits [total] into [parts] amounts that sum exactly to [total].
  /// Rule: every part gets floor(total/parts); the leftover piastres are
  /// given one each to the FIRST installments.
  static List<int> distributeEvenly(int total, int parts) {
    if (parts <= 0) throw ArgumentError('parts must be > 0');
    if (total < 0) throw ArgumentError('total must be >= 0');
    final base = total ~/ parts;
    final rem = total % parts;
    return List<int>.generate(parts, (i) => base + (i < rem ? 1 : 0));
  }

  /// Parses "2,000", "٢٬٠٠٠٫٥٠", "1500.5" into piastres. Max 2 decimals.
  static int parseEgp(String input) {
    final s = _latinDigits(input)
        .replaceAll(RegExp(r'[,\u066C\s]'), '')
        .replaceAll('\u066B', '.');
    final m = RegExp(r'^(-)?(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
    if (m == null) throw FormatException('Invalid amount: $input');
    final whole = int.parse(m.group(2)!);
    final frac = (m.group(3) ?? '0').padRight(2, '0');
    final v = whole * piastresPerEgp + int.parse(frac);
    return m.group(1) != null ? -v : v;
  }

  /// Parses a percentage ("20", "12.5") into basis points (20% = 2000).
  static int parsePercentToBps(String input) {
    final s = _latinDigits(input).trim().replaceAll('\u066B', '.');
    final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
    if (m == null) throw FormatException('Invalid percentage: $input');
    return int.parse(m.group(1)!) * 100 +
        int.parse((m.group(2) ?? '0').padRight(2, '0'));
  }

  static String formatEgp(int piastres, {bool arabicDigits = false}) {
    final neg = piastres < 0;
    final a = piastres.abs();
    final whole = a ~/ piastresPerEgp;
    final frac = a % piastresPerEgp;
    var s = _group(whole.toString());
    if (frac != 0) s = '$s.${frac.toString().padLeft(2, '0')}';
    if (neg) s = '-$s';
    return arabicDigits ? _arabicDigits(s) : s;
  }

  static String _group(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
      b.write(digits[i]);
    }
    return b.toString();
  }

  static String _latinDigits(String s) {
    final b = StringBuffer();
    for (final c in s.codeUnits) {
      if (c >= 0x0660 && c <= 0x0669) {
        b.writeCharCode(c - 0x0660 + 0x30);
      } else if (c >= 0x06F0 && c <= 0x06F9) {
        b.writeCharCode(c - 0x06F0 + 0x30);
      } else {
        b.writeCharCode(c);
      }
    }
    return b.toString();
  }

  static String _arabicDigits(String s) {
    final b = StringBuffer();
    for (final c in s.codeUnits) {
      if (c >= 0x30 && c <= 0x39) {
        b.writeCharCode(c - 0x30 + 0x0660);
      } else if (c == 0x2C) {
        b.write('\u066C');
      } else if (c == 0x2E) {
        b.write('\u066B');
      } else {
        b.writeCharCode(c);
      }
    }
    return b.toString();
  }
}
