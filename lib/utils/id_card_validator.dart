import 'package:intl/intl.dart';

class IdCardValidationResult {
  final bool isValid;
  final bool isAdult;
  final DateTime? birthDate;
  final String? errorMessage;

  const IdCardValidationResult({
    required this.isValid,
    required this.isAdult,
    this.birthDate,
    this.errorMessage,
  });
}

class IdCardValidator {
  IdCardValidator._();

  static const List<int> _weights = [
    7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2,
  ];

  static const List<String> _checkCodes = [
    '1', '0', 'X', '9', '8', '7', '6', '5', '4', '3', '2',
  ];

  static IdCardValidationResult validate(String idCard, {int adultAge = 18}) {
    idCard = idCard.trim().toUpperCase();

    if (idCard.isEmpty) {
      return const IdCardValidationResult(
        isValid: false,
        isAdult: false,
        errorMessage: '请输入身份证号码',
      );
    }

    if (idCard.length != 18) {
      return const IdCardValidationResult(
        isValid: false,
        isAdult: false,
        errorMessage: '身份证号码应为18位',
      );
    }

    final regex = RegExp(r'^\d{17}[\dX]$');
    if (!regex.hasMatch(idCard)) {
      return const IdCardValidationResult(
        isValid: false,
        isAdult: false,
        errorMessage: '身份证号码格式不正确',
      );
    }

    final birthStr = idCard.substring(6, 14);
    final yearStr = birthStr.substring(0, 4);
    final monthStr = birthStr.substring(4, 6);
    final dayStr = birthStr.substring(6, 8);

    final year = int.tryParse(yearStr);
    final month = int.tryParse(monthStr);
    final day = int.tryParse(dayStr);

    if (year == null || month == null || day == null) {
      return const IdCardValidationResult(
        isValid: false,
        isAdult: false,
        errorMessage: '身份证中的出生日期无效',
      );
    }

    if (month < 1 || month > 12) {
      return const IdCardValidationResult(
        isValid: false,
        isAdult: false,
        errorMessage: '身份证中的月份无效',
      );
    }

    if (day < 1 || day > 31) {
      return const IdCardValidationResult(
        isValid: false,
        isAdult: false,
        errorMessage: '身份证中的日期无效',
      );
    }

    DateTime? birthDate;
    try {
      birthDate = DateTime(year, month, day);
      if (birthDate.year != year ||
          birthDate.month != month ||
          birthDate.day != day) {
        return const IdCardValidationResult(
          isValid: false,
          isAdult: false,
          errorMessage: '身份证中的出生日期不存在',
        );
      }
    } catch (_) {
      return const IdCardValidationResult(
        isValid: false,
        isAdult: false,
        errorMessage: '身份证中的出生日期无效',
      );
    }

    final now = DateTime.now();
    if (birthDate.isAfter(now)) {
      return const IdCardValidationResult(
        isValid: false,
        isAdult: false,
        errorMessage: '出生日期不能晚于今天',
      );
    }

    if (!_validateCheckCode(idCard)) {
      return const IdCardValidationResult(
        isValid: false,
        isAdult: false,
        errorMessage: '身份证号码校验码错误，请检查是否输入正确',
      );
    }

    final adultDate = DateTime(
      now.year - adultAge,
      now.month,
      now.day,
    );
    final isAdult = birthDate.isBefore(adultDate) ||
        (birthDate.year == adultDate.year &&
         birthDate.month == adultDate.month &&
         birthDate.day == adultDate.day);

    if (!isAdult) {
      return IdCardValidationResult(
        isValid: true,
        isAdult: false,
        birthDate: birthDate,
        errorMessage: '根据身份证信息，您未满18周岁，无法使用本应用',
      );
    }

    return IdCardValidationResult(
      isValid: true,
      isAdult: true,
      birthDate: birthDate,
    );
  }

  static bool _validateCheckCode(String idCard) {
    int sum = 0;
    for (int i = 0; i < 17; i++) {
      final digit = int.parse(idCard[i]);
      sum += digit * _weights[i];
    }
    final mod = sum % 11;
    final expectedCheckCode = _checkCodes[mod];
    return idCard[17] == expectedCheckCode;
  }

  static String? formatBirthDate(String idCard) {
    final result = validate(idCard);
    if (!result.isValid || result.birthDate == null) return null;
    return DateFormat('yyyy年MM月dd日').format(result.birthDate!);
  }

  static String? maskIdCard(String idCard) {
    if (idCard.length != 18) return null;
    return '${idCard.substring(0, 6)}********${idCard.substring(14)}';
  }
}
