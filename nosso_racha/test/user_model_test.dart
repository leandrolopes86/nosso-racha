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
    test('reads required personal data from canonical and legacy fields', () {
      final canonicalUser = UserModel.fromMap('user-1', {
        'name': 'Test User',
        'cpf': '529.982.247-25',
        'phone': '(11) 99999-9999',
        'birthDate': '2000-01-01',
      });
      final legacyUser = UserModel.fromMap('user-2', {
        'personal_info': {
          'full_name': 'Legacy User',
          'cpf': '529.982.247-25',
          'phone_raw': '(11) 99999-9999',
          'birth_date': '2000-01-01',
        },
      });

      expect(canonicalUser.isProfileComplete, isTrue);
      expect(legacyUser.isProfileComplete, isTrue);
    });

    test('does not gate existing profiles without the enforcement marker', () {
      final existingUser = UserModel.fromMap('existing-user', {
        'name': 'Existing User',
        'personal_info': {'full_name': 'Existing User'},
      });

      expect(existingUser.requiresPersonalData, isFalse);
      expect(existingUser.isProfileComplete, isTrue);
    });

    test('requires a valid CPF, phone number, and adult birth date', () {
      final incompleteUser = UserModel(
        uid: 'user-1',
        name: 'Test User',
        email: 'test@example.com',
        requiresPersonalData: true,
        cpf: '111.111.111-11',
        phone: '(11) 1234-5678',
        birthDate: '2015-01-01',
      );

      expect(incompleteUser.isProfileComplete, isFalse);
    });

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
      'serializes required profile values in canonical Firestore fields',
      () {
        final user = UserModel(
          uid: 'user-1',
          name: 'Test User',
          email: 'test@example.com',
          cpf: '529.982.247-25',
          phone: '(11) 99999-9999',
          birthDate: '2000-01-01',
          requiresPersonalData: true,
        );
        final data = user.toMap();

        expect(data['uid'], 'user-1');
        expect(data['name'], 'Test User');
        expect(data['email'], 'test@example.com');
        expect(data['cpf'], '529.982.247-25');
        expect(data['phone'], '(11) 99999-9999');
        expect(data['birthDate'], '2000-01-01');
        expect(data['requires_personal_data'], isTrue);
        expect(data['createdAt'], isNotNull);
      },
    );

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
