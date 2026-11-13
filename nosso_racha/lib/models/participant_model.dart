import 'package:cloud_firestore/cloud_firestore.dart';

class ParticipantModel {
  final String uid;
  final String name;
  final String nickname;
  final String status; // 'active', 'queue', 'dropout'
  final DateTime registeredAt;
  final String roleInMatch; // 'goalkeeper' or 'line'
  final String paymentStatus; // 'pending', 'paid'
  final String goaliePaymentStatus;
  final String pixKey;
  final String? paymentGatewayId;
  final String vipPlan;
  final DateTime? vipExpiresAt;
  final bool isStaff;
  final bool isGuest; // Convidado do sistema (sem login)
  final bool isExternal;
  final String attendance; // 'pending', 'present', 'absent', 'substitute'
  final bool isAvulso; // Adicionado na tela de fechamento

  ParticipantModel({
    required this.uid,
    required this.name,
    this.nickname = '',
    required this.status,
    required this.registeredAt,
    this.roleInMatch = 'line',
    this.paymentStatus = 'pending',
    this.goaliePaymentStatus = 'none',
    this.pixKey = '',
    this.paymentGatewayId,
    this.vipPlan = '',
    this.vipExpiresAt,
    this.isStaff = false,
    this.isGuest = false,
    this.isExternal = false,
    this.attendance = 'pending',
    this.isAvulso = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'nickname': nickname,
      'status': status,
      'registered_at': Timestamp.fromDate(registeredAt),
      'role_in_match': roleInMatch,
      'payment_status': paymentStatus,
      'goalie_payment_status': goaliePaymentStatus,
      'payment_gateway_id': paymentGatewayId,
      'vipPlan': vipPlan,
      'vipExpiresAt': vipExpiresAt != null
          ? Timestamp.fromDate(vipExpiresAt!)
          : null,
      'is_staff': isStaff,
      'is_guest': isGuest,
      'is_external': isExternal,
      'attendance': attendance,
      'is_avulso': isAvulso,
    };
  }

  factory ParticipantModel.fromMap(Map<String, dynamic> map) {
    return ParticipantModel(
      uid: map['uid'] ?? map['user_uid'] ?? '', // Compatibilidade
      name: map['name'] ?? '',
      nickname: map['nickname'] ?? '',
      status: map['status'] ?? 'active',
      registeredAt: map['registered_at'] != null
          ? (map['registered_at'] as Timestamp).toDate()
          : DateTime.now(),
      roleInMatch: map['role_in_match'] ?? 'line',
      paymentStatus: map['payment_status'] ?? 'pending',
      goaliePaymentStatus: map['goalie_payment_status'] ?? 'none',
      pixKey: map['pix_key'] ?? '',
      paymentGatewayId: map['payment_gateway_id'],
      vipPlan: map['vipPlan'] as String? ?? '',
      vipExpiresAt: (map['vipExpiresAt'] as Timestamp?)?.toDate(),
      isStaff: map['is_staff'] ?? false,
      isGuest: map['is_guest'] ?? false,
      isExternal: map['is_external'] ?? false,
      attendance: map['attendance'] ?? 'pending',
      isAvulso: map['is_avulso'] ?? false,
    );
  }

  // CORREÇÃO: copyWith incluindo todos os campos opcionais
  ParticipantModel copyWith({
    String? status,
    String? paymentStatus,
    String? goaliePaymentStatus,
    String? pixKey,
    String? attendance,
    bool? isAvulso,
    bool? isExternal,
    String? paymentGatewayId,
    String? vipPlan,
    DateTime? vipExpiresAt,
  }) {
    return ParticipantModel(
      uid: uid,
      name: name,
      nickname: nickname,
      status: status ?? this.status,
      registeredAt: registeredAt,
      roleInMatch: roleInMatch,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      goaliePaymentStatus: goaliePaymentStatus ?? this.goaliePaymentStatus,
      pixKey: pixKey ?? this.pixKey,
      paymentGatewayId: paymentGatewayId ?? this.paymentGatewayId,
      vipPlan: vipPlan ?? this.vipPlan,
      vipExpiresAt: vipExpiresAt ?? this.vipExpiresAt,
      isStaff: isStaff,
      isGuest: isGuest,
      isExternal: isExternal ?? this.isExternal,
      attendance: attendance ?? this.attendance,
      isAvulso: isAvulso ?? this.isAvulso,
    );
  }
}
