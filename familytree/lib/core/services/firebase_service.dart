import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../app_config.dart';
import '../../main.dart';
import '../../models/family_model.dart';
import '../../models/member_model.dart';
import '../../models/event_model.dart';
import '../../views/family_group/event_detail_screen.dart';
import '../utils/helpers.dart';

class FirebaseServiceException implements Exception {
  final String message;
  const FirebaseServiceException(this.message);
  @override
  String toString() => message;
}

class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  final FirebaseAuth      _auth    = FirebaseAuth.instance;
  final FirebaseFirestore _db      = FirebaseFirestore.instance;
  final FirebaseStorage   _storage = FirebaseStorage.instance;

  Map<String, dynamic>? _pendingNotificationData;

  // ── MASTER REGISTRATION ───────────────────────────────────────
  Future<MemberModel> registerMaster({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String mobileNumber,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password.trim());
      final uid = cred.user!.uid;
      final master = MemberModel(
        id: uid, familyId: '', firstName: firstName.trim(),
        lastName: lastName.trim(), mobileNumber: mobileNumber.trim(),
        password: '', gender: Gender.male,
        designation: Designation.other, role: AppConfig.masterRole,
      );
      await _db.collection(AppConfig.mastersCollection).doc(uid).set(master.toMap());
      return master;
    } on FirebaseAuthException catch (e) {
      throw FirebaseServiceException(_authError(e.code));
    }
  }

  // ── MASTER LOGIN ──────────────────────────────────────────────
  Future<MemberModel> signInMaster({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signOut();
      final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password.trim());
      final uid = cred.user!.uid;
      final doc = await _db.collection(AppConfig.mastersCollection).doc(uid).get();
      if (!doc.exists) {
        await _auth.signOut();
        throw const FirebaseServiceException(
            'Master profile not found. Please register first.');
      }
      final master = MemberModel.fromMap(doc.data()!);
      if (master.role != AppConfig.masterRole) {
        await _auth.signOut();
        throw const FirebaseServiceException('Access denied.');
      }
      return master;
    } on FirebaseAuthException catch (e) {
      throw FirebaseServiceException(_authError(e.code));
    }
  }

  // ── MEMBER LOGIN ──────────────────────────────────────────────
  Future<MemberModel> signInMember({
    required String mobile,
    required String password,
  }) async {
    final cleanMobile   = mobile.trim();
    final cleanPassword = password.trim();

    if (!Helpers.isValidMobile(cleanMobile)) {
      throw const FirebaseServiceException(
          'Please enter a valid 10-digit mobile number.');
    }

    // Step 1: Validate password against Firestore FIRST
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _db
          .collection(AppConfig.membersCollection)
          .where('mobileNumber', isEqualTo: cleanMobile)
          .limit(1)
          .get();
    } catch (e) {
      throw FirebaseServiceException(
          'Could not reach the database. Check your connection.\n$e');
    }

    if (snap.docs.isEmpty) {
      throw const FirebaseServiceException(
          'No account found for this number. Contact your Family Admin.');
    }

    final memberDoc      = snap.docs.first;
    final memberData     = memberDoc.data();
    final storedPassword = memberData['password'] as String? ?? '';

    if (storedPassword.isEmpty || storedPassword != cleanPassword) {
      throw const FirebaseServiceException(
          'Incorrect password. Contact your Family Admin if you have forgotten it.');
    }

    // Step 2: Determine which synthetic email to use.
    // We store 'authEmail' in Firestore so we always reuse the exact same
    // email that was used when the Auth account was successfully created.
    // This survives UID migrations and alias fallbacks.
    String syntheticEmail = memberData['authEmail'] as String? ?? '';
    if (syntheticEmail.isEmpty) {
      syntheticEmail = '$cleanMobile@familytree.internal';
    }

    UserCredential cred;
    try {
      cred = await _auth.signInWithEmailAndPassword(
        email:    syntheticEmail,
        password: cleanPassword,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        // No Auth account yet — create one fresh
        cred = await _createAuthAccount(
          preferredEmail: syntheticEmail,
          password:       cleanPassword,
          memberDocRef:   memberDoc.reference,
        );
      } else if (e.code == 'wrong-password') {
        // Auth account exists but password is stale — resync it
        cred = await _forceResyncAuthUser(
          syntheticEmail:  syntheticEmail,
          correctPassword: cleanPassword,
          memberDocRef:    memberDoc.reference,
        );
      } else {
        throw FirebaseServiceException(_authError(e.code));
      }
    }

    final authUid = cred.user!.uid;
    final member  = MemberModel.fromMap(memberData);

    // Step 3: Sync UID if Firebase Auth UID differs from Firestore doc ID
    if (member.id != authUid) {
      try {
        final updated = member.copyWith(id: authUid);
        await _db
            .collection(AppConfig.membersCollection)
            .doc(authUid)
            .set(updated.toMap(), SetOptions(merge: true));
        try { await memberDoc.reference.delete(); } catch (_) {}
        await _fixRelationships(member.id, authUid, member.familyId);
        return updated;
      } catch (_) {
        return member.copyWith(id: authUid);
      }
    }

    return member;
  }

  // ── CREATE AUTH ACCOUNT (handles email-already-in-use with alias) ──
  // Creates a Firebase Auth account. If the preferred email is already taken
  // by a stale orphan we can't delete, it falls back to a timestamped alias
  // and saves it in Firestore so future logins reuse the same alias.
  Future<UserCredential> _createAuthAccount({
    required String preferredEmail,
    required String password,
    required DocumentReference memberDocRef,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email:    preferredEmail,
        password: password,
      );
      // Save the email used so future logins hit the right account
      await memberDocRef.set({'authEmail': preferredEmail}, SetOptions(merge: true));
      return cred;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // Stale orphan account exists that we cannot delete (unknown password).
        // Create a unique alias and store it permanently in Firestore.
        final ts     = DateTime.now().millisecondsSinceEpoch;
        final parts  = preferredEmail.split('@');
        final alias  = '${parts[0]}+$ts@${parts[1]}';
        final cred   = await _auth.createUserWithEmailAndPassword(
          email:    alias,
          password: password,
        );
        await memberDocRef.set({'authEmail': alias}, SetOptions(merge: true));
        return cred;
      }
      throw FirebaseServiceException(_authError(e.code));
    }
  }

  // ── FORCE RESYNC: wrong-password on existing Auth account ────
  // The Auth account exists but has a stale password. We try to sign in
  // as the stale user with every password we might know so we can delete
  // it cleanly. If none work, fall back to alias approach.
  Future<UserCredential> _forceResyncAuthUser({
    required String syntheticEmail,
    required String correctPassword,
    required DocumentReference memberDocRef,
  }) async {
    await _auth.signOut();

    // Try signing in as the stale user with common password candidates.
    // We don't have the old password here, but we can try the correct one
    // (maybe Auth is actually right and Firestore is stale — shouldn't happen
    // but worth trying), then give up and use alias approach.
    User? staleUser;
    for (final pwd in [correctPassword]) {
      try {
        final staleCred = await _auth.signInWithEmailAndPassword(
          email:    syntheticEmail,
          password: pwd,
        );
        staleUser = staleCred.user;
        break;
      } on FirebaseAuthException catch (_) {}
    }

    if (staleUser != null) {
      // We signed in — update the password in-place (cleanest path)
      try {
        await staleUser.updatePassword(correctPassword);
        await memberDocRef.set({'authEmail': syntheticEmail}, SetOptions(merge: true));
        return await _auth.signInWithEmailAndPassword(
          email:    syntheticEmail,
          password: correctPassword,
        );
      } on FirebaseAuthException catch (_) {}
      // If updatePassword failed, delete and recreate
      try { await staleUser.delete(); } catch (_) {}
    }

    // Stale user couldn't be signed into or deleted — use alias
    return await _createAuthAccount(
      preferredEmail: syntheticEmail,
      password:       correctPassword,
      memberDocRef:   memberDocRef,
    );
  }

  /// Fixes parent/spouse references across a family after a UID migration.
  Future<void> _fixRelationships(
      String oldId, String newId, String familyId) async {
    if (familyId.isEmpty) return;
    try {
      final snap = await _db
          .collection(AppConfig.membersCollection)
          .where('familyId', isEqualTo: familyId)
          .get();
      for (final doc in snap.docs) {
        if (doc.id == oldId || doc.id == newId) continue;
        final m       = MemberModel.fromMap(doc.data());
        final updates = <String, dynamic>{};
        if (m.fatherId == oldId) updates['fatherId'] = newId;
        if (m.motherId == oldId) updates['motherId'] = newId;
        if (m.spouseId == oldId) updates['spouseId'] = newId;
        if (updates.isNotEmpty) {
          try { await doc.reference.update(updates); } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> signOut() => _auth.signOut();

  // ── FAMILY CRUD ───────────────────────────────────────────────
  Future<FamilyModel> createFamily({
    required String masterId,
    required String familyName,
    required String description,
    File? photoFile,
  }) async {
    final ref = _db.collection(AppConfig.familiesCollection).doc();
    String? photoUrl;
    if (photoFile != null) {
      try {
        photoUrl = await _uploadFamilyPhoto(ref.id, photoFile);
      } catch (e) {
        debugPrint('Error uploading family photo offline: $e');
      }
    }
    final family = FamilyModel(
      id: ref.id, masterId: masterId,
      familyName: familyName.trim(), description: description.trim(),
      memberCount: 0, createdAt: DateTime.now(), photoUrl: photoUrl,
    );
    await ref.set(family.toMap());
    return family;
  }

  Future<void> updateFamily(FamilyModel family, {File? photoFile}) async {
    String? photoUrl = family.photoUrl;
    if (photoFile != null) {
      try {
        photoUrl = await _uploadFamilyPhoto(family.id, photoFile);
      } catch (e) {
        debugPrint('Error uploading family photo offline in update: $e');
      }
    }
    await _db
        .collection(AppConfig.familiesCollection)
        .doc(family.id)
        .set(family.copyWith(photoUrl: photoUrl).toMap(), SetOptions(merge: true));
  }

  Future<void> deleteFamily(String familyId) async {
    final members = await _db
        .collection(AppConfig.membersCollection)
        .where('familyId', isEqualTo: familyId)
        .get();
    final batch = _db.batch();
    for (final doc in members.docs) batch.delete(doc.reference);
    batch.delete(_db.collection(AppConfig.familiesCollection).doc(familyId));
    await batch.commit();
  }

  Future<String> _uploadFamilyPhoto(String familyId, File file) async {
    final ref = _storage.ref().child('family_photos').child('$familyId.jpg');
    final task = await ref.putFile(
        file, SettableMetadata(contentType: 'image/jpeg'));
    return await task.ref.getDownloadURL();
  }

  Stream<List<FamilyModel>> familiesStream(String masterId) {
    return _db
        .collection(AppConfig.familiesCollection)
        .where('masterId', isEqualTo: masterId)
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => FamilyModel.fromMap(d.data())).toList());
  }

  Stream<FamilyModel?> familyStream(String familyId) {
    return _db
        .collection(AppConfig.familiesCollection)
        .doc(familyId)
        .snapshots()
        .map((doc) => doc.exists ? FamilyModel.fromMap(doc.data()!) : null);
  }

  Future<FamilyModel?> getFamily(String familyId) async {
    final doc = await _db
        .collection(AppConfig.familiesCollection)
        .doc(familyId)
        .get();
    return doc.exists ? FamilyModel.fromMap(doc.data()!) : null;
  }

  Stream<int> memberCountStream(String familyId) {
    return _db
        .collection(AppConfig.membersCollection)
        .where('familyId', isEqualTo: familyId)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  // ── MEMBER CRUD ───────────────────────────────────────────────
  Future<String> addMember(MemberModel member) async {
    if (await _mobileExists(member.mobileNumber)) {
      throw FirebaseServiceException(
          'Mobile ${member.mobileNumber} is already registered.');
    }

    final password       = Helpers.generateEightDigitPassword();
    final syntheticEmail = '${member.mobileNumber.trim()}@familytree.internal';
    String uid;
    String usedEmail = syntheticEmail;

    try {
      final tempApp = await Firebase.initializeApp(
        name: 'TempAuthApp_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      UserCredential cred;
      try {
        cred = await tempAuth.createUserWithEmailAndPassword(
          email:    syntheticEmail,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          // Stale orphan — use alias so addMember never fails
          final ts    = DateTime.now().millisecondsSinceEpoch;
          final parts = syntheticEmail.split('@');
          usedEmail   = '${parts[0]}+$ts@${parts[1]}';
          cred = await tempAuth.createUserWithEmailAndPassword(
            email:    usedEmail,
            password: password,
          );
        } else {
          rethrow;
        }
      }
      uid = cred.user!.uid;
      await tempApp.delete();
    } catch (e) {
      final ref = _db.collection(AppConfig.membersCollection).doc();
      uid       = ref.id;
      usedEmail = syntheticEmail;
    }

    final ref = _db.collection(AppConfig.membersCollection).doc(uid);
    await ref.set(member.copyWith(id: uid, password: password).toMap()
      ..['authEmail'] = usedEmail);

    try {
      await _db
          .collection(AppConfig.familiesCollection)
          .doc(member.familyId)
          .update({'memberCount': FieldValue.increment(1)});
    } catch (_) {}

    return password;
  }

  Future<void> updateMember(MemberModel member) async {
    await _db
        .collection(AppConfig.membersCollection)
        .doc(member.id)
        .set(member.toMap(), SetOptions(merge: true));
  }

  Future<void> updateMemberMap({
    required String id,
    required Map<String, dynamic> data,
  }) async {
    await _db
        .collection(AppConfig.membersCollection)
        .doc(id)
        .set(data, SetOptions(merge: true));
  }

  // Safe update — finds real doc by mobile if id is stale
  Future<void> safeUpdateMember(MemberModel member) async {
    final directDoc = await _db
        .collection(AppConfig.membersCollection)
        .doc(member.id)
        .get();

    if (directDoc.exists) {
      await directDoc.reference.set(member.toMap(), SetOptions(merge: true));
      return;
    }

    final snap = await _db
        .collection(AppConfig.membersCollection)
        .where('mobileNumber', isEqualTo: member.mobileNumber)
        .limit(1)
        .get();

    if (snap.docs.isNotEmpty) {
      final realId    = snap.docs.first.id;
      final corrected = member.copyWith(id: realId);
      await snap.docs.first.reference
          .set(corrected.toMap(), SetOptions(merge: true));
    } else {
      await _db
          .collection(AppConfig.membersCollection)
          .doc(member.id)
          .set(member.toMap(), SetOptions(merge: true));
    }
  }

  Future<void> deleteMember(String memberId, String familyId) async {
    await _db.collection(AppConfig.membersCollection).doc(memberId).delete();
    if (familyId.isNotEmpty) {
      try {
        await _db
            .collection(AppConfig.familiesCollection)
            .doc(familyId)
            .update({'memberCount': FieldValue.increment(-1)});
      } catch (_) {}
    }
  }

  Stream<List<MemberModel>> membersStream(String familyId) {
    return _db
        .collection(AppConfig.membersCollection)
        .where('familyId', isEqualTo: familyId)
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => MemberModel.fromMap(d.data())).toList());
  }

  Future<String> uploadProfileImage({
    required String memberId,
    required File imageFile,
  }) async {
    final ref = _storage
        .ref()
        .child(AppConfig.profileImagesPath)
        .child('$memberId.jpg');
    final task = await ref.putFile(
        imageFile, SettableMetadata(contentType: 'image/jpeg'));
    return await task.ref.getDownloadURL();
  }

  // ── PASSWORD RESET ─────────────────────────────────────────────────────────
  //
  // ROOT CAUSE OF "permission" ERROR:
  // Your Firestore rules have: allow create: if true; (but NO allow update)
  // Using mobile as doc ID means the 2nd request is an UPDATE → BLOCKED.
  //
  // FIX: Use a unique auto-generated doc ID every time.
  // The doc always gets CREATED (never updated) → always passes rules.
  // resetRequestsStream queries by mobileNumber field instead of doc ID.
  //
  // NO CHANGES NEEDED TO FIRESTORE RULES.
  //
  Future<void> sendPasswordResetRequest(String mobile) async {
    final cleanMobile = mobile.trim();
    if (!Helpers.isValidMobile(cleanMobile)) {
      throw const FirebaseServiceException(
          'Please enter a valid 10-digit mobile number.');
    }

    // Verify the member actually exists before creating the request
    final memberSnap = await _db
        .collection(AppConfig.membersCollection)
        .where('mobileNumber', isEqualTo: cleanMobile)
        .limit(1)
        .get();

    if (memberSnap.docs.isEmpty) {
      throw const FirebaseServiceException(
          'No account found for this number. Contact your Family Admin.');
    }

    // Block duplicate requests — if a pending request already exists for this
    // mobile, tell the user to wait. They cannot spam the master with requests.
    final existing = await _db
        .collection(AppConfig.resetRequestsCollection)
        .where('mobileNumber', isEqualTo: cleanMobile)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw const FirebaseServiceException(
          'A reset request is already pending. Please wait for your Family Admin to approve or reject it before sending another.');
    }

    // Always create a NEW document with auto-generated ID → always a "create"
    // → always allowed by "allow create: if true" rule.
    await _db.collection(AppConfig.resetRequestsCollection).add({
      'mobileNumber': cleanMobile,
      'status':       'pending',
      'requestedAt':  DateTime.now().toIso8601String(),
      'resolvedAt':   null,
      'newPassword':  null,
    });
  }

  Stream<List<Map<String, dynamic>>> resetRequestsStream(List<String> familyIds) {
    if (familyIds.isEmpty) return Stream.value([]);

    return _db
        .collection(AppConfig.resetRequestsCollection)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .asyncMap((snap) async {
      final requests = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data   = doc.data();
        final mobile = data['mobileNumber'] as String? ?? '';
        if (mobile.isEmpty) continue;

        final member = await getMemberByMobile(mobile);
        if (member == null) continue;

        if (familyIds.contains(member.familyId)) {
          requests.add({
            ...data,
            'id':         doc.id,   // use real doc ID (not mobile number)
            'memberId':   member.id,
            'memberName': member.fullName,
            'familyId':   member.familyId,
          });
        }
      }
      return requests;
    });
  }

  Future<String> approvePasswordReset(
      String requestId, String memberId) async {
    final newPassword = Helpers.generateEightDigitPassword();

    // Get member's stored authEmail so we use the right Auth account
    final memberDoc = await _db
        .collection(AppConfig.membersCollection)
        .doc(memberId)
        .get();
    final memberData      = memberDoc.data() ?? {};
    final currentPassword = memberData['password'] as String? ?? '';
    final authEmail       = memberData['authEmail'] as String?
        ?? '${memberData['mobileNumber']}@familytree.internal';

    try {
      final tempApp = await Firebase.initializeApp(
        name: 'TempApprove_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);

      try {
        final cred = await tempAuth.signInWithEmailAndPassword(
          email:    authEmail,
          password: currentPassword,
        );
        await cred.user?.updatePassword(newPassword);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' || e.code == 'wrong-password' ||
            e.code == 'invalid-credential') {
          try {
            await tempAuth.createUserWithEmailAndPassword(
              email:    authEmail,
              password: newPassword,
            );
          } on FirebaseAuthException catch (ce) {
            if (ce.code == 'email-already-in-use') {
              // Can't sign in, can't create — just update Firestore password.
              // Login will handle Auth resync next time via alias.
              debugPrint('approvePasswordReset: Auth orphan — Firestore updated only.');
            }
          }
        }
      }
      await tempApp.delete();
    } catch (e) {
      debugPrint('approvePasswordReset: Auth sync warning: $e');
    }

    final batch = _db.batch();
    batch.set(
      _db.collection(AppConfig.membersCollection).doc(memberId),
      {'password': newPassword},
      SetOptions(merge: true),
    );
    batch.update(
      _db.collection(AppConfig.resetRequestsCollection).doc(requestId),
      {
        'status':      'approved',
        'newPassword': newPassword,
        'resolvedAt':  DateTime.now().toIso8601String(),
      },
    );
    await batch.commit();
    return newPassword;
  }

  Future<void> rejectPasswordReset(String requestId) async {
    await _db
        .collection(AppConfig.resetRequestsCollection)
        .doc(requestId)
        .update({
      'status':     'rejected',
      'resolvedAt': DateTime.now().toIso8601String(),
    });
  }

  // ── LOOKUPS ───────────────────────────────────────────────────
  Future<MemberModel?> getMemberByMobile(String mobile) async {
    final snap = await _db
        .collection(AppConfig.membersCollection)
        .where('mobileNumber', isEqualTo: mobile)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return MemberModel.fromMap(snap.docs.first.data());
  }

  Future<MemberModel?> getMemberByUid(String uid) async {
    try {
      final doc = await _db
          .collection(AppConfig.membersCollection)
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      return doc.exists ? MemberModel.fromMap(doc.data()!) : null;
    } catch (e) {
      debugPrint('Firestore server getMemberByUid failed, trying cache fallback: $e');
      try {
        final doc = await _db
            .collection(AppConfig.membersCollection)
            .doc(uid)
            .get(const GetOptions(source: Source.cache));
        return doc.exists ? MemberModel.fromMap(doc.data()!) : null;
      } catch (cacheErr) {
        debugPrint('Firestore cache fallback getMemberByUid failed: $cacheErr');
        return null;
      }
    }
  }

  Future<MemberModel?> getMasterByUid(String uid) async {
    try {
      final doc = await _db
          .collection(AppConfig.mastersCollection)
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      return doc.exists ? MemberModel.fromMap(doc.data()!) : null;
    } catch (e) {
      debugPrint('Firestore server getMasterByUid failed, trying cache fallback: $e');
      try {
        final doc = await _db
            .collection(AppConfig.mastersCollection)
            .doc(uid)
            .get(const GetOptions(source: Source.cache));
        return doc.exists ? MemberModel.fromMap(doc.data()!) : null;
      } catch (cacheErr) {
        debugPrint('Firestore cache fallback getMasterByUid failed: $cacheErr');
        return null;
      }
    }
  }

  Future<bool> _mobileExists(String mobile) async {
    try {
      final snap = await _db
          .collection(AppConfig.membersCollection)
          .where('mobileNumber', isEqualTo: mobile)
          .limit(1)
          .get(const GetOptions(source: Source.serverAndCache));
      return snap.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Firestore _mobileExists failed, trying cache fallback: $e');
      try {
        final snap = await _db
            .collection(AppConfig.membersCollection)
            .where('mobileNumber', isEqualTo: mobile)
            .limit(1)
            .get(const GetOptions(source: Source.cache));
        return snap.docs.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  User? get currentUser => _auth.currentUser;

  // ── AUTH ERROR MESSAGES ───────────────────────────────────────
  String _authError(String code) {
    switch (code) {
      case 'user-not-found':
      case 'invalid-credential':     return 'Invalid credentials. Please try again.';
      case 'wrong-password':         return 'Incorrect password.';
      case 'invalid-email':          return 'Invalid email address.';
      case 'email-already-in-use':   return 'An account with this email already exists.';
      case 'weak-password':          return 'Password must be at least 6 characters.';
      case 'user-disabled':          return 'This account has been disabled.';
      case 'too-many-requests':      return 'Too many attempts. Please try again later.';
      case 'network-request-failed': return 'Network error. Check your connection.';
      default:                       return 'Authentication failed ($code). Please try again.';
    }
  }

  // ── FAMILY EVENTS CRUD ─────────────────────────────────────────

  Stream<List<EventModel>> eventsStream(String familyId) {
    return _db
        .collection(AppConfig.familiesCollection)
        .doc(familyId)
        .collection('events')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => EventModel.fromMap(doc.data(), docId: doc.id))
            .toList());
  }

  Future<void> createEvent({
    required String familyId,
    required EventModel event,
    required List<File> files,
  }) async {
    try {
      final docRef = _db
          .collection(AppConfig.familiesCollection)
          .doc(familyId)
          .collection('events')
          .doc();

      final eventId = docRef.id;
      final List<EventAttachment> uploadedAttachments = [];

      for (final file in files) {
        final fileName = file.path.split('/').last.split('\\').last;
        final fileType = _getFileType(fileName);

        final storageRef = _storage
            .ref()
            .child('families')
            .child(familyId)
            .child('events')
            .child(eventId)
            .child(fileName);

        try {
          final uploadTask = await storageRef.putFile(file);
          final downloadUrl = await uploadTask.ref.getDownloadURL();

          uploadedAttachments.add(EventAttachment(
            fileUrl: downloadUrl,
            fileType: fileType,
            fileName: fileName,
          ));
        } catch (uploadErr) {
          debugPrint('Error uploading event attachment offline: $uploadErr');
        }
      }

      final finalEvent = event.copyWith(
        eventId: eventId,
        familyId: familyId,
        attachments: uploadedAttachments,
      );

      await docRef.set(finalEvent.toMap());
    } catch (e) {
      throw FirebaseServiceException('Failed to create family event: $e');
    }
  }

  Future<void> updateEvent({
    required String familyId,
    required EventModel event,
    required List<File> newFiles,
  }) async {
    try {
      final docRef = _db
          .collection(AppConfig.familiesCollection)
          .doc(familyId)
          .collection('events')
          .doc(event.eventId);

      final List<EventAttachment> uploadedAttachments = List.from(event.attachments);

      for (final file in newFiles) {
        final fileName = file.path.split('/').last.split('\\').last;
        final fileType = _getFileType(fileName);

        final storageRef = _storage
            .ref()
            .child('families')
            .child(familyId)
            .child('events')
            .child(event.eventId)
            .child(fileName);

        try {
          final uploadTask = await storageRef.putFile(file);
          final downloadUrl = await uploadTask.ref.getDownloadURL();

          uploadedAttachments.add(EventAttachment(
            fileUrl: downloadUrl,
            fileType: fileType,
            fileName: fileName,
          ));
        } catch (uploadErr) {
          debugPrint('Error uploading event attachment offline: $uploadErr');
        }
      }

      final finalEvent = event.copyWith(
        attachments: uploadedAttachments,
      );

      await docRef.update(finalEvent.toMap());
    } catch (e) {
      throw FirebaseServiceException('Failed to update family event: $e');
    }
  }

  Future<void> deleteEvent({
    required String familyId,
    required String eventId,
  }) async {
    try {
      await _db
          .collection(AppConfig.familiesCollection)
          .doc(familyId)
          .collection('events')
          .doc(eventId)
          .delete();
    } catch (e) {
      throw FirebaseServiceException('Failed to delete family event: $e');
    }
  }

  Future<EventModel?> getEvent(String familyId, String eventId) async {
    try {
      final doc = await _db
          .collection(AppConfig.familiesCollection)
          .doc(familyId)
          .collection('events')
          .doc(eventId)
          .get();
      return doc.exists ? EventModel.fromMap(doc.data()!, docId: doc.id) : null;
    } catch (e) {
      debugPrint('Error getting event: $e');
      return null;
    }
  }

  Stream<EventModel?> getEventStream(String familyId, String eventId) {
    return _db
        .collection(AppConfig.familiesCollection)
        .doc(familyId)
        .collection('events')
        .doc(eventId)
        .snapshots()
        .map((doc) => doc.exists ? EventModel.fromMap(doc.data()!, docId: doc.id) : null);
  }

  Stream<List<Map<String, dynamic>>> masterNotificationsStream() {
    return _db
        .collection('notifications')
        .where('recipientId', isEqualTo: 'master')
        .snapshots()
        .map((snap) {
          final docs = snap.docs.map((doc) => {
                ...doc.data(),
                'id': doc.id,
              }).toList();
          docs.sort((a, b) {
            final aTime = a['createdAt'];
            final bTime = b['createdAt'];
            if (aTime == null || bTime == null) return 0;
            DateTime aDt = aTime is Timestamp ? aTime.toDate() : DateTime.tryParse(aTime.toString()) ?? DateTime.now();
            DateTime bDt = bTime is Timestamp ? bTime.toDate() : DateTime.tryParse(bTime.toString()) ?? DateTime.now();
            return bDt.compareTo(aDt);
          });
          return docs;
        });
  }

  Stream<List<Map<String, dynamic>>> memberNotificationsStream(String familyId) {
    return _db
        .collection('notifications')
        .where('familyId', isEqualTo: familyId)
        .snapshots()
        .map((snap) {
          final docs = snap.docs
              .map((doc) => {
                    ...doc.data(),
                    'id': doc.id,
                  })
              .where((data) => data['recipientId'] != 'master')
              .toList();
          docs.sort((a, b) {
            final aTime = a['createdAt'];
            final bTime = b['createdAt'];
            if (aTime == null || bTime == null) return 0;
            DateTime aDt = aTime is Timestamp ? aTime.toDate() : DateTime.tryParse(aTime.toString()) ?? DateTime.now();
            DateTime bDt = bTime is Timestamp ? bTime.toDate() : DateTime.tryParse(bTime.toString()) ?? DateTime.now();
            return bDt.compareTo(aDt);
          });
          return docs;
        });
  }

  String _getFileType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return 'image';
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) return 'video';
    if (ext == 'pdf') return 'pdf';
    return 'doc';
  }

  // ── FCM TOKEN MANAGEMENT ──────────────────────────────────────

  Future<void> registerDeviceToken({
    required String memberId,
    required String familyId,
  }) async {
    try {
      final fcm = FirebaseMessaging.instance;
      await fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      final token = await fcm.getToken();
      if (token != null) {
        await _db
            .collection(AppConfig.fcmTokensCollection)
            .doc(token)
            .set({
          'token': token,
          'memberId': memberId,
          'familyId': familyId,
          'platform': kIsWeb ? 'web' : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'),
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error registering device token for FCM: $e');
    }
  }

  Future<void> revokeDeviceToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _db
            .collection(AppConfig.fcmTokensCollection)
            .doc(token)
            .delete();
      }
    } catch (e) {
      debugPrint('Error revoking device token: $e');
    }
  }

  // ── PUSH NOTIFICATION SYSTEM INITIALIZATION ───────────────────────

  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> handleNotificationClick(Map<String, dynamic> data) async {
    final eventId = data['eventId'] as String?;
    final familyId = data['familyId'] as String?;
    if (eventId == null || familyId == null) return;

    if (_auth.currentUser == null) {
      _pendingNotificationData = data;
      debugPrint('Notification clicked but user not authenticated. Stored as pending.');
      return;
    }

    _pendingNotificationData = null; // Clear if it was pending

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = FamilyTreeApp.navigatorKey.currentState;
      if (state != null) {
        final event = await getEvent(familyId, eventId);
        if (event != null) {
          state.push(
            MaterialPageRoute(
              builder: (_) => EventDetailScreen(event: event),
            ),
          );
        } else {
          debugPrint('Notification deep-link: Event $eventId in family $familyId not found.');
        }
      } else {
        debugPrint('Notification deep-link: navigatorKey state is null.');
      }
    });
  }

  void processPendingNotification() {
    if (_pendingNotificationData != null && _auth.currentUser != null) {
      final data = _pendingNotificationData!;
      _pendingNotificationData = null;
      handleNotificationClick(data);
    }
  }

  Future<void> markNotificationsAsRead(String userId, List<String> notificationIds) async {
    try {
      final batch = _db.batch();
      for (final id in notificationIds) {
        final docRef = _db.collection('notifications').doc(id);
        batch.set(docRef, {
          'readBy': FieldValue.arrayUnion([userId])
        }, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error marking notifications as read: $e');
    }
  }

  Future<void> initializeNotifications() async {
    try {
      final fcm = FirebaseMessaging.instance;

      // On iOS, configure foreground notification presentation options
      await fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Initialize Flutter Local Notifications for Android
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: DarwinInitializationSettings(),
      );

      await _localNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            try {
              final Map<String, dynamic> data = jsonDecode(payload);
              handleNotificationClick(data);
            } catch (e) {
              debugPrint('Error parsing local notification payload: $e');
            }
          }
        },
      );

      // Create standard Notification Channel for Android 8.0+
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'family_tree_events', // id
        'Family Tree Events', // name
        description: 'Notifications for new family events and tree updates.',
        importance: Importance.max,
        playSound: true,
      );

      await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // Listen to Foreground Messages and show local notification
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        final android = message.notification?.android;

        if (notification != null && !kIsWeb) {
          final payloadStr = jsonEncode(message.data);
          _localNotificationsPlugin.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                channel.id,
                channel.name,
                channelDescription: channel.description,
                importance: Importance.max,
                priority: Priority.high,
                icon: android?.smallIcon ?? '@mipmap/ic_launcher',
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            payload: payloadStr,
          );
        }
      });

      // Listen to FCM notification clicks when app is in background but open
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('FCM onMessageOpenedApp: ${message.data}');
        handleNotificationClick(message.data);
      });

      // Check if the app was launched from a terminated state via a notification click
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('FCM getInitialMessage: ${initialMessage.data}');
        handleNotificationClick(initialMessage.data);
      }

      // Register top-level background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('Error during notification system initialization: $e');
    }
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}