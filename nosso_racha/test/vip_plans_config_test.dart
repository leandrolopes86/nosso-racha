import 'package:flutter_test/flutter_test.dart';
import 'package:nosso_racha/models/plan_limits.dart';
import 'package:nosso_racha/models/vip_plans_config.dart';

void main() {
  test('organizer VIP enables group administration features', () {
    expect(
      VipPlansConfig.featuresFor('organizer_vip'),
      containsAll(GroupFeature.values),
    );
  });

  test('Platinum tier enables organizer VIP group features', () {
    expect(
      VipPlansConfig.featuresFor('Platinum'),
      containsAll(GroupFeature.values),
    );
    expect(VipPlansConfig.appPlanForVipTier('Platinum'), 'organizer_vip');
  });

  test('free and unknown plans do not enable VIP group features', () {
    expect(VipPlansConfig.featuresFor('free'), isEmpty);
    expect(VipPlansConfig.featuresFor('unknown_plan'), isEmpty);
  });

  test('only active or trialing subscriptions are accepted', () {
    expect(VipPlansConfig.isActiveStatus(null), isTrue);
    expect(VipPlansConfig.isActiveStatus('active'), isTrue);
    expect(VipPlansConfig.isActiveStatus('trialing'), isTrue);
    expect(VipPlansConfig.isActiveStatus('expired'), isFalse);
    expect(VipPlansConfig.isActiveStatus('canceled'), isFalse);
  });

  test('keeps the five standard plans in order and ignores other tiers', () {
    addTearDown(() => VipPlansConfig.loadFromMap(null));
    VipPlansConfig.loadFromMap({
      'plans': {
        'community_plus': {
          'displayName': 'Community Plus',
          'appPlan': 'organizer_vip',
          'color': '#287348',
          'active': true,
          'defaultLimit': 50,
          'limits': {
            'maxGroupMemberships': 8,
            'maxOwnedOrganizations': 2,
            'maxOpenEvents': 5,
            'maxAthletesPerGroup': 65,
            'maxCoOrganizersPerGroup': 4,
          },
          'featureLimits': {'reports': 12},
          'features': ['finance', 'reports'],
        },
        'prata': {
          'displayName': 'Prata',
          'appPlan': 'athlete_vip',
          'color': '#287348',
          'active': true,
          'defaultLimit': 50,
          'limits': {'maxGroupMemberships': 8},
          'featureLimits': {'reports': 12},
          'features': [],
        },
      },
    });

    expect(VipPlansConfig.plans.keys, [
      'free',
      'bronze',
      'silver',
      'gold',
      'platinum',
    ]);
    expect(VipPlansConfig.hasPlan('community_plus'), isFalse);
    expect(VipPlansConfig.isPaidVipTier('community_plus'), isFalse);
    expect(VipPlansConfig.isPaidVipTier('prata'), isTrue);
    expect(VipPlansConfig.appPlanForVipTier('prata'), 'athlete_vip');
    expect(VipPlansConfig.tierFor('silver')?.displayName, 'Silver');
    expect(VipPlansConfig.displayNameFor('prata'), 'Silver');
    expect(VipPlansConfig.displayNameFor('ouro'), 'Gold');
    expect(VipPlansConfig.displayNameFor('community_plus'), 'Free');
    expect(VipPlansConfig.limitFor('prata', 'reports'), 12);
    expect(
      PlanLimits.forVipTier('silver', 'athlete_vip').maxGroupMemberships,
      8,
    );
    expect(
      PlanLimits.forVipTier('community_plus', 'free').maxGroupMemberships,
      2,
    );
  });

  test('treats a canonical plan null feature limit as unlimited', () {
    addTearDown(() => VipPlansConfig.loadFromMap(null));
    VipPlansConfig.loadFromMap({
      'plans': {
        'gold': {
          'displayName': 'Gold',
          'appPlan': 'athlete_vip',
          'color': '#287348',
          'active': true,
          'defaultLimit': 50,
          'limits': {},
          'featureLimits': {'reports': null},
          'features': [],
        },
      },
    });

    expect(VipPlansConfig.limitFor('gold', 'reports'), isNull);
  });
}
