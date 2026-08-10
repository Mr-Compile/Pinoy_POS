class Validators {
  static String? required(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? minLength(String? value, int min, [String fieldName = 'This field']) {
    if (value != null && value.trim().length < min) {
      return '$fieldName must be at least $min characters';
    }
    return null;
  }

  static String? maxLength(String? value, int max, [String fieldName = 'This field']) {
    if (value != null && value.trim().length > max) {
      return '$fieldName must not exceed $max characters';
    }
    return null;
  }

  static String? numeric(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final number = double.tryParse(value.trim());
    if (number == null) {
      return '$fieldName must be a number';
    }
    return null;
  }

  static String? positiveNumber(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final number = double.tryParse(value.trim());
    if (number == null || number <= 0) {
      return '$fieldName must be greater than 0';
    }
    return null;
  }

  static String? nonNegativeNumber(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final number = double.tryParse(value.trim());
    if (number == null || number < 0) {
      return '$fieldName must be 0 or greater';
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!value.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!value.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if (value == null || value.trim().isEmpty) {
      return 'Please confirm your password';
    }
    if (value != password) {
      return 'Passwords do not match';
    }
    return null;
  }

  static String? pin(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'PIN is required';
    }
    final pinRegex = RegExp(r'^\d{4,6}$');
    if (!pinRegex.hasMatch(value.trim())) {
      return 'PIN must be 4-6 digits';
    }
    return null;
  }

  static String? futureDate(DateTime? value, [String fieldName = 'This date']) {
    if (value == null) {
      return null;
    }
    if (value.isBefore(DateTime.now())) {
      return '$fieldName cannot be in the past';
    }
    return null;
  }

  static String? endDateAfterStartDate(DateTime? endDate, DateTime? startDate) {
    if (endDate == null || startDate == null) {
      return null;
    }
    if (endDate.isBefore(startDate)) {
      return 'End date cannot be earlier than start date';
    }
    return null;
  }

  static String? compose(List<String? Function(String?)> validators, String? value) {
    for (final validator in validators) {
      final error = validator(value);
      if (error != null) {
        return error;
      }
    }
    return null;
  }
}
