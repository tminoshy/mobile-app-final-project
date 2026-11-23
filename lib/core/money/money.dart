/// Domain amounts are integer cents; decimals exist only at API boundaries.
final class Money {
  static int parse(String input, {bool allowZero = false}) {
    final text = input.trim().replaceAll(r'$', '').replaceAll(',', '');
    if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(text)) {
      throw const FormatException(
        'Enter an amount with at most two decimal places.',
      );
    }
    final parts = text.split('.');
    final cents =
        int.parse(parts[0]) * 100 +
        (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
    if (cents == 0 && !allowZero) {
      throw const FormatException('Amount must be greater than zero.');
    }
    return cents;
  }

  static int fromJson(Object? amount) =>
      amount == null ? 0 : (num.parse(amount.toString()) * 100).round();
  static String toJson(int cents) => input(cents);
  static String input(int cents) =>
      '${cents ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';
  static String format(int cents, {bool signed = false}) {
    final parts = input(cents.abs()).split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return '${cents < 0
        ? '−'
        : signed && cents > 0
        ? '+'
        : ''}\$$whole.${parts[1]}';
  }
}

DateTime parseUtc(String value) => DateTime.parse(
  RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value) ? value : '${value}Z',
).toUtc();
bool sameMonth(DateTime value, DateTime month) {
  final local = value.toLocal();
  return local.year == month.year && local.month == month.month;
}

String monthKey(DateTime month) =>
    '${month.year}-${month.month.toString().padLeft(2, '0')}';
