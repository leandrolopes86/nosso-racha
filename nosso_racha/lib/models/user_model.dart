import 'package:cloud_firestore/cloud_firestore.dart';
import 'plan_limits.dart';
import 'vip_plans_config.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String nickname;
  final String phone;
  final String role; // 'master', 'org', 'athlete'
  final String status; // 'active', 'inactive', 'suspended'
  final bool isOwner;
  final List<String> positions;
  final List<String> groupIds;
  final String plan;
  final String vipPlan;
  final DateTime? vipExpiresAt;
  final String pixKey;
  final double rating;
  final String birthDate;

  final Map<String, bool> permissions;

  // Estatísticas
  final int matchesPlayed;
  final int noShows;
  final int unpaidRemovals;

  // Data do último jogo
  final DateTime? lastMatchDate;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.nickname = '',
    this.phone = '',
    this.role = 'athlete',
    this.status = 'active',
    this.isOwner = false,
    this.positions = const [],
    this.groupIds = const [],
    this.plan = 'free',
    this.vipPlan = '',
    this.vipExpiresAt,
    this.pixKey = '',
    this.rating = 0.0,
    this.birthDate = '',
    this.permissions = const {},
    this.matchesPlayed = 0,
    this.noShows = 0,
    this.unpaidRemovals = 0,
    this.lastMatchDate,
  });

  // --- GETTERS DE PERMISSÃO ---
  bool get isMaster => role == 'master' || isOwner;
  bool get isStaff => isMaster || role == 'org';

  bool get hasActiveVipPlan =>
      VipPlansConfig.isPaidVipTier(vipPlan) &&
      vipExpiresAt != null &&
      vipExpiresAt!.isAfter(DateTime.now());

  String get effectivePlan => hasActiveVipPlan
      ? VipPlansConfig.appPlanForVipTier(vipPlan)
      : plan.trim().toLowerCase();

  bool get canCreateEvent =>
      isMaster ||
      permissions['can_create_event'] == true ||
      effectivePlan == 'organizer_vip';
  bool get canSortTeams => isMaster || permissions['can_sort_teams'] == true;
  bool get canEndEvent => isMaster || permissions['can_end_event'] == true;
  bool get canEditEvent => isMaster || permissions['can_edit_event'] == true;

  bool get canAddPlayer => isMaster || permissions['can_add_player'] == true;
  bool get canShareList => isMaster || permissions['can_share_list'] == true;
  bool get canRemoveUnpaid =>
      isMaster || permissions['can_remove_unpaid'] == true;
  bool get canRemovePlayer =>
      isMaster || permissions['can_remove_player'] == true;
  bool get canMarkPaid => isMaster || permissions['can_mark_paid'] == true;
  bool get canReorderList =>
      isMaster || permissions['can_reorder_list'] == true;
  bool get canSyncPayments =>
      isMaster || permissions['can_sync_payments'] == true;

  // --- PERMISSÕES FINANCEIRAS ---
  bool get canViewFinancialSummary =>
      isMaster || permissions['can_view_financial_summary'] == true;
  bool get canViewFinance =>
      isMaster || permissions['can_view_finance'] == true;
  bool get canManageFinance =>
      isMaster || permissions['can_manage_finance'] == true;

  // --- PERMISSÕES DE SORTEIO ---
  bool get canGenerateTiers =>
      isMaster || permissions['can_generate_tiers'] == true;
  bool get canReopenTiers =>
      isMaster || permissions['can_reopen_tiers'] == true;
  bool get canReopenTeams =>
      isMaster || permissions['can_reopen_teams'] == true;

  // --- PERMISSÕES DE JOGO ---
  bool get canRevertMatch =>
      isMaster || permissions['can_revert_match'] == true;
  bool get canEditMatchScore =>
      isMaster || permissions['can_edit_match_score'] == true;
  bool get canUpdateLiveScore =>
      isMaster || permissions['can_update_live_score'] == true;

  bool get canAddGuestPlayer =>
      isMaster || permissions['can_add_guest_player'] == true;

  bool get canRegisterUser =>
      isMaster || permissions['can_register_user'] == true;
  bool get canChangeAccountStatus =>
      isMaster || permissions['can_change_account_status'] == true;
  bool get canEditPersonalData =>
      isMaster || permissions['can_edit_personal_data'] == true;
  bool get canDefinePositions =>
      isMaster || permissions['can_define_positions'] == true;
  bool get canEditTechnicalRating =>
      isMaster || permissions['can_edit_technical_rating'] == true;

  bool get canViewReports =>
      isMaster || permissions['can_view_reports'] == true;
  bool get canAccessUserManagement =>
      isMaster ||
      canRegisterUser ||
      canChangeAccountStatus ||
      canEditPersonalData;

  factory UserModel.fromMap(String uid, Map<String, dynamic> data) {
    final personal = data['personal_info'] as Map<String, dynamic>? ?? {};
    final football = data['football_stats'] as Map<String, dynamic>? ?? {};
    final stats = data['stats'] as Map<String, dynamic>? ?? {};
    final perms = data['permissions'] as Map<String, dynamic>? ?? {};
    final groupIds = <String>{
      ...List<String>.from(data['group_ids'] ?? const <String>[]),
      if (data['group_id'] is String && (data['group_id'] as String).isNotEmpty)
        data['group_id'] as String,
    }.toList();

    return UserModel(
      uid: uid,
      name: personal['full_name'] ?? '',
      email: data['email'] ?? '',
      nickname: football['nickname'] ?? '',
      phone: personal['phone_raw'] ?? '',
      role: data['role'] ?? 'athlete',
      status: data['status'] ?? 'active',
      isOwner: data['is_owner'] ?? false,
      positions: List<String>.from(football['positions'] ?? []),
      groupIds: groupIds,
      plan: data['plan'] ?? 'free',
      vipPlan:
          data['vipPlan'] as String? ??
          (VipPlansConfig.isPaidVipTier(data['plan'] as String?)
              ? data['plan'] as String
              : ''),
      vipExpiresAt: _dateTimeFrom(
        data['vipExpiresAt'] ?? data['vip_expires_at'],
      ),
      pixKey: (data['payment_info'] as Map<String, dynamic>?)?['pix_key'] ?? '',
      rating: (football['rating'] ?? 0).toDouble(),
      birthDate: personal['birth_date'] ?? '',
      permissions: Map<String, bool>.from(perms),
      matchesPlayed: stats['matches_played'] ?? 0,
      noShows: stats['no_shows'] ?? 0,
      unpaidRemovals: stats['unpaid_removals'] ?? 0,
      lastMatchDate: (stats['last_match_date'] as Timestamp?)?.toDate(),
    );
  }

  static String effectivePlanForGroupOwner({
    required String ownerId,
    required Map<String, dynamic> ownerData,
    required Map<String, dynamic> groupData,
  }) {
    final groupTier = _activeOrganizerVipTier({
      'vipPlan': groupData['vipPlan'],
      'vipExpiresAt': groupData['vipExpiresAt'] ?? groupData['vip_expires_at'],
    });
    if (groupTier != null) {
      return VipPlansConfig.appPlanForVipTier(groupTier);
    }
    return UserModel.fromMap(ownerId, ownerData).effectivePlan;
  }

  static String? effectiveVipTierForGroupOwner({
    required String ownerId,
    required Map<String, dynamic> ownerData,
    required Map<String, dynamic> groupData,
  }) {
    final groupTier = _activeOrganizerVipTier({
      'vipPlan': groupData['vipPlan'],
      'vipExpiresAt': groupData['vipExpiresAt'] ?? groupData['vip_expires_at'],
    });
    if (groupTier != null) return groupTier;
    final owner = UserModel.fromMap(ownerId, ownerData);
    return owner.hasActiveVipPlan && owner.effectivePlan == 'organizer_vip'
        ? owner.vipPlan
        : null;
  }

  static String? groupOwnerId(Map<String, dynamic> groupData) {
    for (final field in const [
      'owner_id',
      'ownerId',
      'organizer_id',
      'organizer_uid',
      'organizerId',
    ]) {
      final value = groupData[field];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  // --- ADICIONADO: Método toMap para gravação no Firestore ---
  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'role': role,
      'status': status,
      'is_owner': isOwner,
      'group_ids': groupIds,
      'plan': plan,
      'vipPlan': vipPlan,
      'vipExpiresAt': vipExpiresAt != null
          ? Timestamp.fromDate(vipExpiresAt!)
          : null,
      'permissions': permissions,
      'personal_info': {
        'full_name': name,
        'phone_raw': phone,
        'birth_date': birthDate,
      },
      'football_stats': {
        'nickname': nickname,
        'positions': positions,
        'rating': rating,
      },
      'payment_info': {'pix_key': pixKey},
      'stats': {
        'matches_played': matchesPlayed,
        'no_shows': noShows,
        'unpaid_removals': unpaidRemovals,
        'last_match_date': lastMatchDate != null
            ? Timestamp.fromDate(lastMatchDate!)
            : null,
      },
    };
  }

  // Retorna true se os dados obrigatórios do perfil estiverem preenchidos
  bool get isProfileComplete {
    return phone.trim().isNotEmpty && name.trim().isNotEmpty;
  }

  bool get isPro {
    return role == 'org' || role == 'master' || role == 'pro';
  }

  static DateTime? _dateTimeFrom(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  bool get canPlayMultiplePositions =>
      isStaff ||
      effectivePlan == 'athlete_vip' ||
      effectivePlan == 'organizer_vip';

  PlanLimits get planLimits {
    if (hasActiveVipPlan && effectivePlan == 'organizer_vip') {
      return PlanLimits.forVipTier(vipPlan, effectivePlan);
    }
    if (effectivePlan == 'organizer_vip') return PlanLimits.organizerVip;
    if (isStaff || canCreateEvent) return PlanLimits.organizer;
    if (hasActiveVipPlan) {
      return PlanLimits.forVipTier(vipPlan, effectivePlan);
    }
    return PlanLimits.forPlan(effectivePlan);
  }

  bool get canCreateOrganizations =>
      isMaster || planLimits.canCreateOrganizations;

  static String? _activeOrganizerVipTier(Map<String, dynamic> data) {
    final tier = data['vipPlan'] as String?;
    final expiry = _dateTimeFrom(
      data['vipExpiresAt'] ?? data['vip_expires_at'],
    );
    if (tier == null ||
        !VipPlansConfig.isPaidVipTier(tier) ||
        VipPlansConfig.appPlanForVipTier(tier) != 'organizer_vip' ||
        expiry == null ||
        !expiry.isAfter(DateTime.now())) {
      return null;
    }
    return tier;
  }
}
