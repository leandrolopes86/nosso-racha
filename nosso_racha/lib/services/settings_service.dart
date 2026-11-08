import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class SettingsService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- LEITURA ---
  Stream<DocumentSnapshot> getAppConfigStream() {
    return _firestore.collection('settings').doc('app_config').snapshots();
  }

  Stream<DocumentSnapshot> getFinanceSettingsStream() {
    return _firestore.collection('settings').doc('finance').snapshots();
  }

  Stream<DocumentSnapshot> getGroupSettingsStream(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('settings')
        .doc('general')
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> getGroupStream(
    String groupId,
  ) {
    return _firestore.collection('groups').doc(groupId).snapshots();
  }

  Future<void> saveGroupProfile({
    required String groupId,
    required String name,
    required String city,
    required String neighborhood,
  }) async {
    await _firestore.collection('groups').doc(groupId).update({
      'name': name,
      'city': city,
      'neighborhood': neighborhood,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveGroupSettings({
    required String groupId,
    required bool includeGoalkeepers,
    required bool considerPositions,
  }) async {
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('settings')
        .doc('general')
        .set({
          'default_include_goalkeepers': includeGoalkeepers,
          'default_consider_positions': considerPositions,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
    notifyListeners();
  }

  // --- ESCRITA ---
  Future<void> saveGlobalTheme(String themeMode) async {
    try {
      await _firestore.collection('settings').doc('app_config').set({
        'forced_theme': themeMode,
      }, SetOptions(merge: true));
      notifyListeners();
    } catch (e) {
      throw Exception('Erro ao salvar tema: $e');
    }
  }

  // ATUALIZADO: Salvar preferências de Sorteio (Goleiros e Posições)
  Future<void> saveSortPreference({
    required bool includeGoalkeepers,
    required bool considerPositions, // <--- NOVO PARÂMETRO
  }) async {
    try {
      await _firestore.collection('settings').doc('app_config').set({
        'default_include_goalkeepers': includeGoalkeepers,
        'default_consider_positions': considerPositions, // <--- NOVO CAMPO
      }, SetOptions(merge: true));
      notifyListeners();
    } catch (e) {
      throw Exception('Erro ao salvar preferência de sorteio: $e');
    }
  }

  Future<void> savePixSettings({
    required String pixKey,
    required String beneficiary,
    required String bankName,
  }) async {
    try {
      // Mantido para compatibilidade, mas o PaymentGatewayService é o principal agora
      await _firestore.collection('settings').doc('finance').set({
        'pix_key': pixKey,
        'beneficiary': beneficiary,
        'bank_name': bankName,
      }, SetOptions(merge: true));
      notifyListeners();
    } catch (e) {
      throw Exception('Erro ao salvar PIX: $e');
    }
  }
}
