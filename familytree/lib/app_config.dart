class AppConfig {
  AppConfig._();

  // Firestore collections
  static const String membersCollection       = 'members';
  static const String mastersCollection       = 'masters';
  static const String familiesCollection      = 'families';
  static const String resetRequestsCollection = 'password_reset_requests';
  static const String fcmTokensCollection     = 'fcm_tokens';

  // Storage
  static const String profileImagesPath = 'profile_images';

  // Roles
  static const String masterRole = 'master';
  static const String adminRole  = 'admin';
  static const String memberRole = 'member';

  // Google API Key for Places / Maps
  static const String googleApiKey = 'AIzaSyABNOR5Y5RBkep9P-1xh0U245dHMMdKl1g';
}
