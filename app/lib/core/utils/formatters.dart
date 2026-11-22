import 'package:intl/intl.dart';

/// Pakistan Standard Time is UTC+5 all year (no daylight saving). All timestamps from the backend are UTC;
/// we always display them in PKT regardless of the phone's timezone so deadlines match official notices.
class Pkt {
  static const offset = Duration(hours: 5);

  /// Wall-clock PKT time represented as a UTC DateTime (fields read as PKT).
  static DateTime toPkt(DateTime utc) => utc.toUtc().add(offset);

  /// Converts a PKT wall-clock date/time chosen by the user into a real UTC instant.
  static DateTime fromPktWallClock(int y, int m, int d, [int hh = 0, int mm = 0]) =>
      DateTime.utc(y, m, d, hh, mm).subtract(offset);

  static DateTime nowPkt() => toPkt(DateTime.now().toUtc());

  static String date(DateTime? utc, {String locale = 'en'}) =>
      utc == null ? '—' : DateFormat('d MMM yyyy', 'en_US').format(toPkt(utc));

  static String dateTime(DateTime? utc, {String locale = 'en'}) =>
      utc == null ? '—' : '${DateFormat('d MMM yyyy, h:mm a', 'en_US').format(toPkt(utc))} PKT';

  /// Whole calendar days (in PKT) between today and the deadline. 0 = closes today, negative = passed.
  static int daysUntil(DateTime utcDeadline, {DateTime? nowUtc}) {
    final n = toPkt(nowUtc ?? DateTime.now().toUtc());
    final d = toPkt(utcDeadline);
    return DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(n.year, n.month, n.day)).inDays;
  }
}

String formatPkr(num? amount) {
  if (amount == null) return '';
  return 'PKR ${NumberFormat.decimalPattern('en').format(amount)}';
}

DateTime? parseTs(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toUtc();

String timeAgo(DateTime utc, {DateTime? now}) {
  final d = (now ?? DateTime.now().toUtc()).difference(utc);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return Pkt.date(utc);
}
