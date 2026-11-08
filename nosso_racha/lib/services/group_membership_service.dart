import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/plan_limits.dart';
import '../models/user_model.dart';

class GroupMembershipService {
  final FirebaseFirestore _firestore;

  GroupMembershipService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<void> addMember({
    required String groupId,
    required String userId,
    String role = 'member',
  }) async {
    if (role != 'member' && role != 'co_organizer') {
      throw ArgumentError.value(role, 'role', 'Papel de membro inválido.');
    }

    final groupRef = _firestore.collection('groups').doc(groupId);
    final memberRef = groupRef.collection('members').doc(userId);
    final userRef = _firestore.collection('users').doc(userId);

    await _firestore.runTransaction((transaction) async {
      final memberSnapshot = await transaction.get(memberRef);
      if (memberSnapshot.exists) return;

      final groupSnapshot = await transaction.get(groupRef);
      final groupData = groupSnapshot.data();
      if (groupData == null) throw StateError('Organização não encontrada.');

      final userSnapshot = await transaction.get(userRef);
      final userData = userSnapshot.data();
      if (userData == null) throw StateError('Atleta não encontrado.');

      final ownerId = UserModel.groupOwnerId(groupData);
      if (ownerId == null || ownerId.isEmpty) {
        throw StateError('A organização não possui proprietário válido.');
      }
      final ownerSnapshot = await transaction.get(
        _firestore.collection('users').doc(ownerId),
      );
      final ownerData = ownerSnapshot.data();
      if (ownerData == null) {
        throw StateError('O perfil do organizador não foi encontrado.');
      }
      final athleteCount = groupData['athlete_count'];
      final coOrganizerCount = groupData['co_organizer_count'];
      if (athleteCount is! int || coOrganizerCount is! int) {
        throw StateError(
          'Os limites desta organização ainda não foram inicializados. '
          'Execute a migração de contadores do Firestore.',
        );
      }

      final existingGroupIds = <String>{
        ...List<String>.from(userData['group_ids'] ?? const <String>[]),
        if (userData['group_id'] is String &&
            (userData['group_id'] as String).isNotEmpty)
          userData['group_id'] as String,
      };
      final targetLimits = _limitsForUser(userData);
      if (targetLimits.maxGroupMemberships != null &&
          !existingGroupIds.contains(groupId) &&
          existingGroupIds.length >= targetLimits.maxGroupMemberships!) {
        throw StateError(
          'O limite de organizações do seu plano foi atingido '
          '(${targetLimits.maxGroupMemberships}).',
        );
      }

      final ownerPlan = UserModel.effectivePlanForGroupOwner(
        ownerId: ownerId,
        ownerData: ownerData,
        groupData: groupData,
      );
      final ownerLimits = PlanLimits.forOrganizerPlan(ownerPlan);
      if (role == 'member' && ownerLimits.maxAthletesPerGroup != null) {
        if (athleteCount >= ownerLimits.maxAthletesPerGroup!) {
          throw StateError(
            'A organização atingiu o limite de '
            '${ownerLimits.maxAthletesPerGroup} atletas do plano.',
          );
        }
      }
      if (role == 'co_organizer' &&
          ownerLimits.maxCoOrganizersPerGroup != null) {
        if (coOrganizerCount >= ownerLimits.maxCoOrganizersPerGroup!) {
          throw StateError(
            'A organização atingiu o limite de '
            '${ownerLimits.maxCoOrganizersPerGroup} co-organizadores do plano.',
          );
        }
      }

      transaction.set(memberRef, {
        'uid': userId,
        'role': role,
        'joined_at': FieldValue.serverTimestamp(),
      });
      final membershipNonce = _firestore.collection('groups').doc().id;
      transaction.update(groupRef, {
        if (role == 'member') 'athlete_count': athleteCount + 1,
        if (role == 'co_organizer') 'co_organizer_count': coOrganizerCount + 1,
        'capacity_member_uid': userId,
        'capacity_member_role': role,
        'capacity_member_delta': 1,
        'capacity_member_nonce': membershipNonce,
      });
      if (!existingGroupIds.contains(groupId)) {
        transaction.update(userRef, {
          'group_ids': FieldValue.arrayUnion([groupId]),
          'membership_change_group_id': groupId,
          'membership_change_nonce': membershipNonce,
        });
      }
    });
  }

  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    final groupRef = _firestore.collection('groups').doc(groupId);
    final memberRef = groupRef.collection('members').doc(userId);
    final userRef = _firestore.collection('users').doc(userId);
    await _firestore.runTransaction((transaction) async {
      final memberSnapshot = await transaction.get(memberRef);
      if (!memberSnapshot.exists) return;
      final memberData = memberSnapshot.data();
      final role = memberData?['role'] as String? ?? '';
      if (role == 'owner') {
        throw StateError('O proprietário não pode ser removido do grupo.');
      }
      if (role != 'member' && role != 'co_organizer') {
        throw StateError('O papel do membro não é válido.');
      }

      final groupSnapshot = await transaction.get(groupRef);
      final groupData = groupSnapshot.data();
      final userSnapshot = await transaction.get(userRef);
      if (groupData == null || userSnapshot.data() == null) {
        throw StateError('A organização ou o atleta não foi encontrado.');
      }
      final athleteCount = groupData['athlete_count'];
      final coOrganizerCount = groupData['co_organizer_count'];
      if (athleteCount is! int || coOrganizerCount is! int) {
        throw StateError(
          'Os limites desta organização ainda não foram inicializados. '
          'Execute a migração de contadores do Firestore.',
        );
      }
      if ((role == 'member' && athleteCount == 0) ||
          (role == 'co_organizer' && coOrganizerCount == 0)) {
        throw StateError('Os contadores da organização estão inconsistentes.');
      }

      final membershipNonce = _firestore.collection('groups').doc().id;
      transaction.delete(memberRef);
      transaction.update(groupRef, {
        if (role == 'member') 'athlete_count': athleteCount - 1,
        if (role == 'co_organizer') 'co_organizer_count': coOrganizerCount - 1,
        'capacity_member_uid': userId,
        'capacity_member_role': role,
        'capacity_member_delta': -1,
        'capacity_member_nonce': membershipNonce,
      });

      final userData = userSnapshot.data()!;
      final groupIds = List<String>.from(
        userData['group_ids'] ?? const <String>[],
      );
      if (groupIds.contains(groupId)) {
        final userUpdates = <String, dynamic>{
          'group_ids': FieldValue.arrayRemove([groupId]),
          'last_removed_group_id': groupId,
          'last_membership_change_nonce': _firestore
              .collection('groups')
              .doc()
              .id,
          'membership_change_group_id': groupId,
          'membership_change_nonce': membershipNonce,
        };
        if (userData['group_id'] == groupId) {
          userUpdates['group_id'] = FieldValue.delete();
        }
        transaction.update(userRef, userUpdates);
      } else if (userData['group_id'] == groupId) {
        transaction.update(userRef, {
          'group_id': FieldValue.delete(),
          'last_removed_group_id': groupId,
          'last_membership_change_nonce': _firestore
              .collection('groups')
              .doc()
              .id,
          'membership_change_group_id': groupId,
          'membership_change_nonce': membershipNonce,
        });
      }
    });
  }

  PlanLimits _limitsForUser(Map<String, dynamic> userData) {
    return UserModel.fromMap(
      userData['uid'] as String? ?? '',
      userData,
    ).planLimits;
  }
}
