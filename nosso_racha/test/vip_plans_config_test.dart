import 'package:flutter_test/flutter_test.dart';
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
}
