import 'package:flutter_test/flutter_test.dart';
import 'package:nosso_racha/models/user_model.dart';

void main() {
  group('UserModel group memberships', () {
    test('resolves supported owner and organizer field names', () {
      expect(UserModel.groupOwnerId({'owner_id': 'owner-1'}), 'owner-1');
      expect(UserModel.groupOwnerId({'ownerId': 'owner-2'}), 'owner-2');
      expect(
        UserModel.groupOwnerId({'organizer_id': 'organizer-1'}),
        'organizer-1',
      );
      expect(
        UserModel.groupOwnerId({'organizer_uid': 'organizer-2'}),
        'organizer-2',
      );
      expect(UserModel.groupOwnerId({'owner_id': '  '}), isNull);
    });

    test('reads multiple group ids and keeps the legacy group id', () {
      final user = UserModel.fromMap('user-1', {
        'group_ids': ['group-1', 'group-2'],
        'group_id': 'legacy-group',
      });

      expect(
        user.groupIds,
        containsAll(['group-1', 'group-2', 'legacy-group']),
      );
    });

    test('serializes all group memberships', () {
      final user = UserModel(
        uid: 'user-1',
        name: 'Test User',
        email: 'test@example.com',
        groupIds: const ['group-1', 'group-2'],
      );

      expect(user.toMap()['group_ids'], ['group-1', 'group-2']);
    });
  });

  group('UserModel player profile', () {
    test('reads plan and PIX key from Firestore data', () {
      final user = UserModel.fromMap('user-1', {
        'plan': 'athlete_vip',
        'payment_info': {'pix_key': 'keeper@example.com'},
      });

      expect(user.plan, 'athlete_vip');
      expect(user.pixKey, 'keeper@example.com');
      expect(user.canPlayMultiplePositions, isTrue);
    });

    test('free athlete cannot select multiple positions', () {
      final user = UserModel(
        uid: 'user-1',
        name: 'Test User',
        email: 'test@example.com',
      );

      expect(user.canPlayMultiplePositions, isFalse);
    });

    test('organizer can play multiple positions', () {
      final user = UserModel(
        uid: 'organizer-1',
        name: 'Organizer',
        email: 'organizer@example.com',
        role: 'org',
      );

      expect(user.canPlayMultiplePositions, isTrue);
    });

    test('serializes plan and PIX key', () {
      final user = UserModel(
        uid: 'user-1',
        name: 'Test User',
        email: 'test@example.com',
        plan: 'athlete_vip',
        pixKey: 'keeper@example.com',
      );
      final data = user.toMap();

      expect(data['plan'], 'athlete_vip');
      expect(
        (data['payment_info'] as Map<String, dynamic>)['pix_key'],
        'keeper@example.com',
      );
    });

    test(
      'maps an active Platinum VIP subscription to organizer permissions',
      () {
        final user = UserModel.fromMap('user-1', {
          'role': 'athlete',
          'vipPlan': 'Platinum',
          'vipExpiresAt': DateTime.now().add(const Duration(days: 30)),
        });

        expect(user.role, 'athlete');
        expect(user.hasActiveVipPlan, isTrue);
        expect(user.effectivePlan, 'organizer_vip');
        expect(user.canCreateEvent, isTrue);
        expect(user.canCreateOrganizations, isTrue);
        expect(user.planLimits.maxOpenEvents, isNull);
      },
    );

    test('does not grant organizer access for expired VIP subscriptions', () {
      final user = UserModel.fromMap('user-1', {
        'vipPlan': 'Platinum',
        'vipExpiresAt': DateTime.now().subtract(const Duration(days: 1)),
      });

      expect(user.hasActiveVipPlan, isFalse);
      expect(user.effectivePlan, 'free');
      expect(user.canCreateEvent, isFalse);
      expect(user.canCreateOrganizations, isFalse);
    });

    test('uses an active group Platinum tier for its owner limits', () {
      final future = DateTime.now().add(const Duration(days: 30));

      expect(
        UserModel.effectivePlanForGroupOwner(
          ownerId: 'owner-1',
          ownerData: const {'plan': 'free'},
          groupData: {'vipPlan': 'Platinum', 'vipExpiresAt': future},
        ),
        'organizer_vip',
      );
      expect(
        UserModel.effectivePlanForGroupOwner(
          ownerId: 'owner-1',
          ownerData: const {'plan': 'free'},
          groupData: {
            'vipPlan': 'Platinum',
            'vipExpiresAt': future.subtract(const Duration(days: 40)),
          },
        ),
        'free',
      );
    });
  });
}
