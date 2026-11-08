import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart'; // Import necessário

class FinanceService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- LER EXTRATO ---
  Stream<QuerySnapshot> getTransactionsStream(
    String groupId,
    DateTime startDate,
    DateTime endDate,
  ) {
    final endOfDay = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      23,
      59,
      59,
    );

    return _firestore
        .collection('transactions')
        .where('group_id', isEqualTo: groupId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .orderBy('date', descending: true)
        .snapshots();
  }

  // --- LANÇAMENTO MANUAL (Com Auditoria) ---
  Future<void> addManualTransaction({
    required String description,
    required double amount,
    required String type,
    required DateTime date,
    required UserModel registeredBy, // <--- QUEM LANÇOU
    required String groupId,
  }) async {
    try {
      final transaction = TransactionModel(
        description: description,
        amount: amount,
        type: type,
        date: date,
        category: type == 'debit' ? 'event_cost' : 'other',
        registeredByUid: registeredBy.uid,
        registeredByName: registeredBy.name,
        groupId: groupId,
      );

      await _firestore.collection('transactions').add(transaction.toMap());
      notifyListeners();
    } catch (e) {
      throw Exception('Erro ao lançar transação: $e');
    }
  }

  Map<String, double> calculateTotals(List<TransactionModel> transactions) {
    double income = 0;
    double expense = 0;
    for (var t in transactions) {
      if (t.type == 'credit') {
        income += t.amount;
      } else {
        expense += t.amount;
      }
    }
    return {'income': income, 'expense': expense, 'balance': income - expense};
  }
}
