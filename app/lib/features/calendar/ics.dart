import '../../data/models/activity.dart';

/// Builds an iCalendar (RFC 5545) file so users can sync deadlines into Google/Outlook/Apple calendars.
String buildIcs(List<CalendarEvent> events, {DateTime? nowUtc}) {
  String ts(DateTime d) {
    final u = d.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  String esc(String s) => s.replaceAll('\\', '\\\\').replaceAll(';', '\\;').replaceAll(',', '\\,').replaceAll('\n', '\\n');

  /// Lines longer than 75 octets must be folded (approximated by characters, safe for ASCII-heavy text).
  String fold(String line) {
    if (line.length <= 74) return line;
    final b = StringBuffer(line.substring(0, 74));
    for (var i = 74; i < line.length; i += 73) {
      b.write('\r\n ${line.substring(i, i + 73 > line.length ? line.length : i + 73)}');
    }
    return b.toString();
  }

  const labels = {
    'interested_deadline': 'Deadline', 'saved_deadline': 'Deadline', 'application_deadline': 'Application deadline',
    'interview': 'Interview', 'follow_up': 'Follow up', 'custom_reminder': 'Reminder',
  };
  final stamp = ts(nowUtc ?? DateTime.now().toUtc());
  final lines = <String>['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Mauqa//Opportunities//EN', 'CALSCALE:GREGORIAN', 'X-WR-CALNAME:Mauqa', 'X-WR-TIMEZONE:Asia/Karachi'];
  for (final e in events) {
    final uid = '${e.type}-${e.opportunityId ?? e.applicationId ?? e.reminderId ?? e.title.hashCode}-${e.at.millisecondsSinceEpoch}@mauqa';
    lines.addAll([
      'BEGIN:VEVENT',
      'UID:$uid',
      'DTSTAMP:$stamp',
      'DTSTART:${ts(e.at)}',
      'DTEND:${ts(e.at.add(const Duration(minutes: 30)))}',
      fold('SUMMARY:${esc('${labels[e.type] ?? 'Mauqa'}: ${e.title}')}'),
      'BEGIN:VALARM', 'ACTION:DISPLAY', 'DESCRIPTION:${esc(e.title)}', 'TRIGGER:-P1D', 'END:VALARM',
      'END:VEVENT',
    ]);
  }
  lines.add('END:VCALENDAR');
  return '${lines.join('\r\n')}\r\n';
}
