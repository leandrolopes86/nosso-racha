import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/vip_plans_config.dart';

class GroupPlanAccess {
  final bool isAuthorized;
  final Set<GroupFeature> features;
  final String plan;

  const GroupPlanAccess({
    required this.isAuthorized,
    required this.features,
    required this.plan,
  });

  bool allows(GroupFeature feature) =>
      isAuthorized && features.contains(feature);
}

class GroupPlanService {
  static const managerRoles = {'owner', 'organizer', 'admin', 'co_organizer'};

  final FirebaseFirestore _firestore;

  GroupPlanService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<GroupPlanAccess> loadAccess({
    required String groupId,
    required String userId,
  }) async {
    final groupRef = _firestore.collection('groups').doc(groupId);
    final groupSnapshot = await groupRef.get();
    final group = groupSnapshot.data();
    if (group == null) {
      return _denied();
    }

    final ownerId = UserModel.groupOwnerId(group);
    final membershipSnapshot = userId == ownerId
        ? null
        : await groupRef.collection('members').doc(userId).get();
    final membershipRole = membershipSnapshot?.data()?['role'] as String?;
    final isAuthorized =
        userId == ownerId || managerRoles.contains(membershipRole);
    if (!isAuthorized) return _denied();

    final ownerSnapshot = ownerId == null
        ? null
        : await _firestore.collection('users').doc(ownerId).get();
    return _authorizedAccess(group, ownerSnapshot?.data());
  }

  Stream<GroupPlanAccess> watchAccess({
    required String groupId,
    required String userId,
  }) {
    final groupRef = _firestore.collection('groups').doc(groupId);
    return groupRef.snapshots().asyncExpand((groupSnapshot) {
      final group = groupSnapshot.data();
      if (group == null) return Stream.value(_denied());

      final ownerId = UserModel.groupOwnerId(group);
      final membershipSnapshots = userId == ownerId
          ? Stream<DocumentSnapshot<Map<String, dynamic>>?>.value(null)
          : groupRef
                .collection('members')
                .doc(userId)
                .snapshots()
                .map((snapshot) => snapshot);

      return membershipSnapshots.asyncExpand((membershipSnapshot) {
        final membershipRole = membershipSnapshot?.data()?['role'] as String?;
        final isAuthorized =
            userId == ownerId || managerRoles.contains(membershipRole);
        if (!isAuthorized) return Stream.value(_denied());
        if (ownerId == null) {
          return Stream.value(_authorizedAccess(group, null));
        }

        return _firestore
            .collection('users')
            .doc(ownerId)
            .snapshots()
            .map(
              (ownerSnapshot) => _authorizedAccess(group, ownerSnapshot.data()),
            );
      });
    });
  }

  GroupPlanAccess _authorizedAccess(
    Map<String, dynamic> group,
    Map<String, dynamic>? owner,
  ) {
    final ownerActive =
        owner == null || owner['status'] == null || owner['status'] == 'active';
    final groupTier = _activeVipTier(group);
    final ownerTier = owner == null ? null : _activeVipTier(owner);
    final ownerSubscription =
        owner?['subscription'] as Map<String, dynamic>? ?? {};
    final ownerPlan = owner?['plan'] as String? ?? 'free';
    final ownerStatus =
        ownerSubscription['status'] as String? ??
        owner?['plan_status'] as String?;
    final ownerExpiry =
        ownerSubscription['expires_at'] ?? owner?['plan_expires_at'];
    final ownerSubscriptionActive =
        owner != null &&
        ownerActive &&
        ownerPlan == 'organizer_vip' &&
        VipPlansConfig.isActiveStatus(ownerStatus) &&
        _isFutureTimestamp(ownerExpiry);

    final activePlan = groupTier != null
        ? VipPlansConfig.appPlanForVipTier(groupTier)
        : ownerTier != null
        ? VipPlansConfig.appPlanForVipTier(ownerTier)
        : ownerSubscriptionActive
        ? ownerPlan
        : 'free';
    final active =
        ownerActive &&
        (groupTier != null || ownerTier != null || ownerSubscriptionActive);

    return GroupPlanAccess(
      isAuthorized: true,
      features: active ? VipPlansConfig.featuresFor(activePlan) : const {},
      plan: activePlan,
    );
  }

  String? _activeVipTier(Map<String, dynamic> data) {
    final tier =
        data['vipPlan'] as String? ??
        (VipPlansConfig.isPaidVipTier(data['plan'] as String?)
            ? data['plan'] as String
            : null);
    final expiresAt = data['vipExpiresAt'] ?? data['vip_expires_at'];
    if (!VipPlansConfig.isPaidVipTier(tier) || !_isFutureTimestamp(expiresAt)) {
      return null;
    }
    return tier;
  }

  bool _isFutureTimestamp(Object? value) {
    final expiration = switch (value) {
      Timestamp timestamp => timestamp.toDate(),
      DateTime dateTime => dateTime,
      String string => DateTime.tryParse(string),
      _ => null,
    };
    return expiration != null && expiration.isAfter(DateTime.now());
  }

  GroupPlanAccess _denied() =>
      const GroupPlanAccess(isAuthorized: false, features: {}, plan: 'free');
}
