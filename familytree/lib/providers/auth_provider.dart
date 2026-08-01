import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../app_config.dart';
import '../core/services/firebase_service.dart';
import '../models/member_model.dart';

enum AuthStatus { initial, authenticated, unauthenticated, loading, error }

class AuthProvider extends ChangeNotifier {
  AuthStatus   _status      = AuthStatus.initial;
  MemberModel? _currentUser;
  String?      _errorMessage;
  StreamSubscription<User?>? _authSub;

  /// True while a login/register/signOut call is actively in progress.
  /// Prevents the authStateChanges listener from interfering mid-operation.
  bool _loginInProgress = false;

  AuthProvider() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  // ── Getters ───────────────────────────────────────────────────
  AuthStatus   get status       => _status;
  MemberModel? get currentUser  => _currentUser;
  String?      get errorMessage => _errorMessage;
  bool         get isLoading    => _status == AuthStatus.loading || _status == AuthStatus.initial;
  bool         get isMaster     => _currentUser?.role == AppConfig.masterRole;
  bool         get isAdmin      => _currentUser?.role == AppConfig.adminRole;
  String?      get familyId     => _currentUser?.familyId;
  String?      get masterId     => isMaster ? _currentUser?.id : null;

  // ── Auth State Listener ───────────────────────────────────────

  /// Called by FirebaseAuth whenever the auth state changes (login, logout, app restart).
  Future<void> _onAuthChanged(User? firebaseUser) async {
    // Skip if a manual login/register/signOut call is in progress.
    // Those methods set state themselves and call notifyListeners in their finally block.
    if (_loginInProgress) return;

    if (firebaseUser == null) {
      _currentUser  = null;
      _status       = AuthStatus.unauthenticated;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    // User exists (app restart / hot restart) — restore the session.
    _status = AuthStatus.loading;
    notifyListeners();
    await _tryRestoreSession(firebaseUser.uid);
  }

  /// Fetches the user's Firestore profile to restore a previous session.
  Future<void> _tryRestoreSession(String uid) async {
    try {
      // Check master collection first
      final master = await FirebaseService.instance.getMasterByUid(uid);
      if (master != null && master.role == AppConfig.masterRole) {
        _currentUser  = master;
        _status       = AuthStatus.authenticated;
        _errorMessage = null;
        notifyListeners();
        FirebaseService.instance.registerDeviceToken(
          memberId: master.id,
          familyId: 'master',
        );
        FirebaseService.instance.processPendingNotification();
        return;
      }

      // Check member collection
      final member = await FirebaseService.instance.getMemberByUid(uid);
      if (member != null) {
        _currentUser  = member;
        _status       = AuthStatus.authenticated;
        _errorMessage = null;
        notifyListeners();
        // Register device token for push notifications in the background
        FirebaseService.instance.registerDeviceToken(
          memberId: member.id,
          familyId: member.familyId,
        );
        FirebaseService.instance.processPendingNotification();
        return;
      }

      // Auth user exists but no Firestore profile found.
      // Do NOT sign out — fall back cleanly to unauthenticated.
      _currentUser  = null;
      _status       = AuthStatus.unauthenticated;
      _errorMessage = 'Profile document not found.';
      notifyListeners();
    } catch (e) {
      // Network drop or permission delay during restore.
      // Use error state instead of forcing an automated logout loop.
      _currentUser  = null;
      _status       = AuthStatus.error;
      _errorMessage = 'Session restoration error: $e';
      notifyListeners();
    }
  }

  // ── Auth Operations ───────────────────────────────────────────

  Future<bool> registerMaster({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String mobileNumber,
  }) async {
    // ✅ Guard UP first — before any async work and before _setLoading()
    // so the authStateChanges listener can never fire in the window between
    // Firebase completing and our state being set.
    _loginInProgress = true;
    _setLoading();
    try {
      _currentUser  = await FirebaseService.instance.registerMaster(
        email: email, password: password,
        firstName: firstName, lastName: lastName,
        mobileNumber: mobileNumber,
      );
      _status       = AuthStatus.authenticated;
      _errorMessage = null;
      if (_currentUser != null) {
        FirebaseService.instance.registerDeviceToken(
          memberId: _currentUser!.id,
          familyId: 'master',
        );
        FirebaseService.instance.processPendingNotification();
      }
      return true;
    } on FirebaseServiceException catch (e) {
      _setError(e.message);
      return false;
    } catch (e) {
      _setError('Unexpected error: $e');
      return false;
    } finally {
      // ✅ Guard drops here — AFTER state is fully set.
      // notifyListeners() fires exactly once, at the very end.
      _loginInProgress = false;
      notifyListeners();
    }
  }

  Future<bool> loginMaster({
    required String email,
    required String password,
  }) async {
    _loginInProgress = true;
    _setLoading();
    try {
      _currentUser  = await FirebaseService.instance.signInMaster(
          email: email, password: password);
      _status       = AuthStatus.authenticated;
      _errorMessage = null;
      if (_currentUser != null) {
        FirebaseService.instance.registerDeviceToken(
          memberId: _currentUser!.id,
          familyId: 'master',
        );
        FirebaseService.instance.processPendingNotification();
      }
      return true;
    } on FirebaseServiceException catch (e) {
      _setError(e.message);
      return false;
    } catch (e) {
      _setError('Unexpected error: $e');
      return false;
    } finally {
      _loginInProgress = false;
      notifyListeners();
    }
  }

  Future<bool> loginMember({
    required String mobile,
    required String password,
  }) async {
    _loginInProgress = true;
    _setLoading();
    try {
      _currentUser  = await FirebaseService.instance.signInMember(
          mobile: mobile, password: password);
      _status       = AuthStatus.authenticated;
      _errorMessage = null;
      if (_currentUser != null) {
        FirebaseService.instance.registerDeviceToken(
          memberId: _currentUser!.id,
          familyId: _currentUser!.familyId,
        );
        FirebaseService.instance.processPendingNotification();
      }
      return true;
    } on FirebaseServiceException catch (e) {
      _setError(e.message);
      return false;
    } catch (e) {
      _setError('Login failed. Please check your credentials.');
      return false;
    } finally {
      _loginInProgress = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _loginInProgress = true;
    try {
      await FirebaseService.instance.revokeDeviceToken();
    } catch (_) {}
    await FirebaseService.instance.signOut();
    _currentUser     = null;
    _status          = AuthStatus.unauthenticated;
    _errorMessage    = null;
    _loginInProgress = false; // drop guard before final notify
    notifyListeners();
  }

  // ── Private Helpers ───────────────────────────────────────────

  /// Sets loading state WITHOUT calling notifyListeners.
  /// The finally block in each public method calls notifyListeners exactly once.
  void _setLoading() {
    _status       = AuthStatus.loading;
    _errorMessage = null;
    // intentionally no notifyListeners() here
  }

  /// Sets error state WITHOUT calling notifyListeners.
  /// The finally block in each public method calls notifyListeners exactly once.
  void _setError(String message) {
    _status       = AuthStatus.unauthenticated;
    _errorMessage = message;
    // intentionally no notifyListeners() here
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}