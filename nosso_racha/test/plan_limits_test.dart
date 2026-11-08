import 'package:flutter_test/flutter_test.dart';
import 'package:nosso_racha/models/plan_limits.dart';
import 'package:nosso_racha/models/user_model.dart';

void main() {
  group('PlanLimits', () {
    test('defines free and athlete VIP organization limits', () {
      expect(PlanLimits.forPlan('free').maxGroupMemberships, 2);
      expect(PlanLimits.forPlan('athlete_vip').maxGroupMemberships, 10);
      expect(PlanLimits.forPlan('free').maxOwnedOrganizations, 0);
      expect(PlanLimits.forPlan('athlete_vip').maxOwnedOrganizations, 0);
      expect(PlanLimits.forPlan('athlete_vip').canCreateOrganizations, isFalse);
    });

    test('defines organizer limits and unlimited organizer VIP capacity', () {
      expect(PlanLimits.forOrganizerPlan('free').maxGroupMemberships, 2);
      expect(PlanLimits.forOrganizerPlan('free').maxOwnedOrganizations, 0);
      expect(
        PlanLimits.forOrganizerPlan('free').canCreateOrganizations,
        isFalse,
      );
      expect(PlanLimits.forOrganizerPlan('free').maxOpenEvents, 3);
      expect(PlanLimits.forOrganizerPlan('free').maxAthletesPerGroup, 40);
      expect(PlanLimits.forOrganizerPlan('free').maxCoOrganizersPerGroup, 3);
      expect(PlanLimits.forPlan('organizer_vip').maxGroupMemberships, 10);
      expect(PlanLimits.forPlan('organizer_vip').maxOwnedOrganizations, isNull);
      expect(PlanLimits.forPlan('organizer_vip').maxOpenEvents, isNull);
      expect(PlanLimits.forPlan('organizer_vip').maxAthletesPerGroup, isNull);
      expect(
        PlanLimits.forPlan('organizer_vip').maxCoOrganizersPerGroup,
        isNull,
      );
    });

    test('uses organizer policy for staff accounts without VIP plan', () {
      final organizer = UserModel(
        uid: 'organizer',
        name: 'Organizer',
        email: 'organizer@example.com',
        role: 'org',
      );

      expect(organizer.planLimits.maxOpenEvents, 3);
      expect(organizer.canCreateOrganizations, isFalse);
    });

    test('organizer VIP can create communities and events', () {
      final organizer = UserModel(
        uid: 'organizer-vip',
        name: 'Organizer VIP',
        email: 'organizer-vip@example.com',
        plan: 'organizer_vip',
      );

      expect(organizer.canCreateOrganizations, isTrue);
      expect(organizer.canCreateEvent, isTrue);
    });
  });
}
