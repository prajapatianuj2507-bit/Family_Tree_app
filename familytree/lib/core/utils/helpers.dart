// lib/core/utils/helpers.dart

import 'dart:math';

class Helpers {
  Helpers._();

  /// Generates a cryptographically-random 8-digit numeric password.
  /// Example output: "48293710"
  static String generateEightDigitPassword() {
    final Random rng = Random.secure();
    // Ensures the first digit is never 0 (true 8-digit number).
    final int first = rng.nextInt(9) + 1;
    final StringBuffer sb = StringBuffer(first.toString());
    for (int i = 0; i < 7; i++) {
      sb.write(rng.nextInt(10));
    }
    return sb.toString();
  }

  /// Validates a 10-digit Indian mobile number.
  static bool isValidMobile(String mobile) {
    final RegExp regex = RegExp(r'^[6-9]\d{9}$');
    return regex.hasMatch(mobile);
  }

  /// Capitalises the first letter of a string.
  static String capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// Returns initials (up to 2 chars) from a full name for avatar fallback.
  static String getInitials(String firstName, String lastName) {
    final String f = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    final String l = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    return '$f$l';
  }
}
