import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionModel {
  final String id;
  final String description;
  final double amount;
  final String type; // 'credit' ou 'debit'
  final DateTime date;
  final String category;
  final String relatedEventId;
  final String relatedUserId;
  final String registeredByUid;
  final String registeredByName;
  final String groupId;

  TransactionModel({
    this.id = '', // <--- Alterado: Não é mais 'required' na criação local
    required this.description,
    required this.amount,
    required this.type,
    required this.date,
    this.category = '',
    this.relatedEventId = '',
    this.relatedUserId = '',
    this.registeredByUid = '',
    this.registeredByName = '',
    this.groupId = '',
  });

  factory TransactionModel.fromMap(String id, Map<String, dynamic> map) {
    // PROTEÇÃO CONTRA NULL TIMESTAMPS (FieldValue.serverTimestamp pendente)
    DateTime parsedDate = DateTime.now(); // Valor padrão de segurança

    if (map['date'] != null) {
      if (map['date'] is Timestamp) {
        parsedDate = (map['date'] as Timestamp).toDate();
      } else if (map['date'] is String) {
        parsedDate = DateTime.tryParse(map['date']) ?? DateTime.now();
      }
    }

    return TransactionModel(
      id: id,
      description: map['description'] ?? 'Sem descrição',
      // Converte de forma segura tanto inteiros quanto decimais do Firebase
      amount: (map['amount'] ?? 0).toDouble(),
      type: map['type'] ?? 'credit',
      date: parsedDate, // Usa a data protegida
      category: map['category'] ?? '',
      relatedEventId: map['related_event_id'] ?? '',
      relatedUserId: map['related_user_id'] ?? '',
      registeredByUid: map['registered_by_uid'] ?? '',
      registeredByName: map['registered_by_name'] ?? '',
      groupId: map['group_id'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'description': description,
      'amount': amount,
      'type': type,
      'date': Timestamp.fromDate(date),
      'category': category,
      'related_event_id': relatedEventId,
      'related_user_id': relatedUserId,
      'registered_by_uid': registeredByUid,
      'registered_by_name': registeredByName,
      'group_id': groupId,
    };
  }
}
