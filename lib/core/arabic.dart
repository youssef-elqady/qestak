/// Normalizes text for searching only. Stored names are never modified.
String normalizeArabic(String input) {
  final b = StringBuffer();
  for (final c in input.toLowerCase().runes) {
    // diacritics + tatweel
    if ((c >= 0x064B && c <= 0x065F) || c == 0x0640 || c == 0x0670) continue;
    switch (c) {
      case 0x0623: // أ
      case 0x0625: // إ
      case 0x0622: // آ
      case 0x0671: // ٱ
        b.write('ا');
      case 0x0649: // ى
      case 0x0626: // ئ
        b.write('ي');
      case 0x0629: // ة
        b.write('ه');
      case 0x0624: // ؤ
        b.write('و');
      default:
        if (c >= 0x0660 && c <= 0x0669) {
          b.writeCharCode(c - 0x0660 + 0x30);
        } else if (c >= 0x06F0 && c <= 0x06F9) {
          b.writeCharCode(c - 0x06F0 + 0x30);
        } else {
          b.writeCharCode(c);
        }
    }
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Digits only (Arabic-Indic digits converted).
String normalizePhone(String input) =>
    normalizeArabic(input).replaceAll(RegExp(r'[^0-9]'), '');

/// Egyptian mobile -> international format for wa.me links.
String whatsappNumber(String phone) {
  final d = normalizePhone(phone);
  if (d.startsWith('00')) return d.substring(2);
  if (d.startsWith('0')) return '20${d.substring(1)}';
  return d;
}
