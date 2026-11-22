/// Form validators. Each returns null when valid, or an error message.
class Validators {
  static String? required(String? v, {String message = 'Required'}) => (v == null || v.trim().isEmpty) ? message : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter your email';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(v.trim()) ? null : 'Enter a valid email address';
  }

  /// Pakistani mobile numbers: 03XXXXXXXXX or +923XXXXXXXXX.
  static String? phonePk(String? v) {
    final n = normalizePhone(v ?? '');
    if (n.isEmpty) return 'Enter your phone number';
    return RegExp(r'^\+923\d{9}$').hasMatch(n) ? null : 'Use a Pakistani mobile number, e.g. 03001234567';
  }

  static String normalizePhone(String v) {
    final digits = v.replaceAll(RegExp(r'[\s\-()]'), '');
    if (RegExp(r'^03\d{9}$').hasMatch(digits)) return '+92${digits.substring(1)}';
    if (RegExp(r'^923\d{9}$').hasMatch(digits)) return '+$digits';
    return digits;
  }

  static String? password(String? v) {
    if (v == null || v.length < 8) return 'At least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) return 'Use letters and numbers';
    return null;
  }

  static String? cnic(String? v) {
    if (v == null || v.trim().isEmpty) return null; // optional
    return RegExp(r'^\d{5}-\d{7}-\d$').hasMatch(v.trim()) ? null : 'Format: 12345-1234567-1';
  }

  static String? cgpa(String? v, {double max = 4.0}) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    if (n == null || n < 0 || n > max) return 'Enter a value between 0 and ${max.toStringAsFixed(1)}';
    return null;
  }

  static String? score(String? value, String? max) {
    if (value == null || value.trim().isEmpty) return null;
    final v = double.tryParse(value.trim());
    final m = double.tryParse((max ?? '').trim());
    if (v == null || v < 0) return 'Enter a number';
    if (m != null && v > m) return 'Cannot exceed the maximum ($m)';
    return null;
  }

  static String? httpsUrl(String? v, {bool optional = true}) {
    if (v == null || v.trim().isEmpty) return optional ? null : 'Enter a link';
    final u = Uri.tryParse(v.trim());
    return (u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.contains('.')) ? null : 'Enter a valid web link';
  }

  static String? year(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v.trim());
    return (n == null || n < 1950 || n > 2100) ? 'Enter a valid year' : null;
  }
}
