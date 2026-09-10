/// Shared helpers for formatting and grouping dates/times in the UI.
class DateTimeUtils {
  DateTimeUtils._();

  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Returns a human-friendly relative timestamp with full words,
  /// e.g. "Just now", "10 minutes ago", "1 hour ago", "Yesterday".
  static String formatRelative(DateTime value) {
    final now = DateTime.now();
    final diff = now.difference(value);

    if (diff.inMinutes < 1) return 'Just now';

    if (diff.inMinutes < 60) {
      final minutes = diff.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    }

    if (diff.inHours < 24) {
      final hours = diff.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    }

    if (diff.inDays == 1) return 'Yesterday';

    if (diff.inDays < 7) {
      final days = diff.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    }

    return '${_monthNames[value.month - 1]} ${value.day}, ${value.year}';
  }
}
