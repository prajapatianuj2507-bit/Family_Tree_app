import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/services/firebase_service.dart';
import '../models/family_model.dart';
import '../models/member_model.dart';

class FamilyProvider extends ChangeNotifier {
  List<MemberModel> _members        = [];
  FamilyModel?      _activeFamily;
  String?           _activeFamilyId;
  bool              _isLoading       = false;
  String?           _errorMessage;
  StreamSubscription<List<MemberModel>>? _memberSub;
  StreamSubscription<FamilyModel?>?      _familySub;

  List<MemberModel> get members        => List.unmodifiable(_members);
  FamilyModel?      get activeFamily   => _activeFamily;
  bool              get isLoading      => _isLoading;
  String?           get errorMessage   => _errorMessage;
  String?           get activeFamilyId => _activeFamilyId;

  void startListening(String familyId) {
    if (_activeFamilyId == familyId) return; // already listening to this family
    _memberSub?.cancel();
    _familySub?.cancel();
    _activeFamilyId = familyId;
    _isLoading      = true;
    notifyListeners();

    // Listen to the family document for photo / metadata
    _familySub = FirebaseService.instance.familyStream(familyId).listen(
      (family) {
        _activeFamily = family;
        notifyListeners();
      },
      onError: (_) {}, // non-critical, silently ignore
    );

    // Listen to the members sub-collection
    _memberSub = FirebaseService.instance.membersStream(familyId).listen(
      (list) {
        _members      = list;
        _isLoading    = false;
        _errorMessage = null;
        notifyListeners();
      },
      onError: (e) {
        _isLoading    = false;
        _errorMessage = 'Failed to load members: $e';
        notifyListeners();
      },
    );
  }

  void stopListening() {
    _memberSub?.cancel();
    _familySub?.cancel();
    _memberSub      = null;
    _familySub      = null;
    _members        = [];
    _activeFamily   = null;
    _activeFamilyId = null;
    notifyListeners();
  }

  Future<String?> addMember({
    required MemberModel member,
    File? profileImage,
  }) async {
    try {
      final password = await FirebaseService.instance.addMember(member);

      if (profileImage != null) {
        try {
          await Future.delayed(const Duration(milliseconds: 400));
          final saved = _members.firstWhere(
                (m) => m.mobileNumber == member.mobileNumber,
            orElse: () => throw const FirebaseServiceException('Member not found after save.'),
          );
          final url = await FirebaseService.instance.uploadProfileImage(
              memberId: saved.id, imageFile: profileImage);
          await FirebaseService.instance.updateMember(
              saved.copyWith(profileImageUrl: url));
        } catch (imageErr) {
          debugPrint('Error uploading profile image offline: $imageErr');
        }
      }
      return password;
    } on FirebaseServiceException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateMember(MemberModel member) async {
    try {
      await FirebaseService.instance.updateMember(member);
      return true;
    } on FirebaseServiceException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateMemberMap({
    required String id,
    required Map<String, dynamic> data,
  }) async {
    try {
      await FirebaseService.instance.updateMemberMap(id: id, data: data);
      final idx = _members.indexWhere((m) => m.id == id);
      if (idx != -1) {
        _members[idx] = MemberModel.fromMap({..._members[idx].toMap(), ...data});
        notifyListeners();
      }
      return true;
    } on FirebaseServiceException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteMember(String memberId) async {
    try {
      final familyId = _activeFamilyId ?? '';
      await FirebaseService.instance.deleteMember(memberId, familyId);
      return true;
    } on FirebaseServiceException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  MemberModel? findById(String? id) {
    if (id == null) return null;
    try { return _members.firstWhere((m) => m.id == id); }
    catch (_) { return null; }
  }

  List<MemberModel> childrenOf(String parentId) =>
      _members.where((m) =>
      m.fatherId == parentId || m.motherId == parentId).toList();

  @override
  void dispose() { stopListening(); super.dispose(); }
}
