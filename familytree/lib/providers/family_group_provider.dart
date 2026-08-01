import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/services/firebase_service.dart';
import '../models/family_model.dart';

class FamilyGroupProvider extends ChangeNotifier {
  List<FamilyModel> _families     = [];
  bool              _isLoading    = false;
  String?           _errorMessage;
  StreamSubscription<List<FamilyModel>>? _sub;

  List<FamilyModel> get families     => List.unmodifiable(_families);
  bool              get isLoading    => _isLoading;
  String?           get errorMessage => _errorMessage;

  void startListening(String masterId) {
    _sub?.cancel();
    _isLoading = true;
    notifyListeners();

    _sub = FirebaseService.instance.familiesStream(masterId).listen(
          (list) {
        // Sort by creation date newest first
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _families     = list;
        _isLoading    = false;
        _errorMessage = null;
        notifyListeners();
      },
      onError: (e) {
        _isLoading    = false;
        _errorMessage = 'Failed to load families: $e';
        notifyListeners();
      },
    );
  }

  void stopListening() {
    _sub?.cancel();
    _sub      = null;
    _families = [];
    notifyListeners();
  }

  Future<FamilyModel?> createFamily({
    required String masterId,
    required String familyName,
    required String description,
    File? photoFile,              // ← ADD THIS
  }) async {
    try {
      final family = await FirebaseService.instance.createFamily(
        masterId:    masterId,
        familyName:  familyName,
        description: description,
        photoFile:   photoFile,   // ← ADD THIS
      );
      return family;
    } on FirebaseServiceException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return null;
    }
  }

// ⚠️ UPDATED: Now safely receives and passes optional file parameters downstream
  Future<bool> updateFamily(FamilyModel family, {File? photoFile}) async {
    try {
      await FirebaseService.instance.updateFamily(family, photoFile: photoFile);
      return true;
    } catch (e) {
      // ⚠️ STORAGE SAFEGUARD: If backend layers throw an error because an old storage reference path is missing,
      // bypass the broken asset target, clear the photo pointer record, and commit the text updates to Firestore.
      if (e.toString().contains('object-not-found')) {
        try {
          await FirebaseService.instance.updateFamily(family.copyWith(photoUrl: null), photoFile: null);
          return true;
        } catch (retryError) {
          _errorMessage = retryError.toString();
          notifyListeners();
          return false;
        }
      }
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteFamily(String familyId) async {
    try {
      await FirebaseService.instance.deleteFamily(familyId);
      return true;
    } on FirebaseServiceException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
