/// Returns a [DateTime] representing the start of [date]'s calendar day
/// (year, month and day only; time is midnight).
DateTime startOfDay(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

/// Returns the Monday of the week containing [date].
DateTime startOfWeek(DateTime date) {
  return startOfDay(date.subtract(Duration(days: date.weekday - 1)));
}
