import 'package:flutter_test/flutter_test.dart';
import 'package:nosso_racha/models/vip_plans_config.dart';
import 'package:nosso_racha/services/plan_permission_service.dart';

void main() {
  group('VipPlansConfig', () {
    test('configures every supported plan with the default limit of 50', () {
      expect(
        VipPlansConfig.plans.keys,
        containsAll(['free', 'bronze', 'silver', 'gold', 'platinum']),
      );
      for (final plan in VipPlansConfig.plans.keys) {
        expect(VipPlansConfig.limitFor(plan, 'maxAthletes'), 50);
      }
    });

    test('feature-specific limits override the plan default', () {
      const config = PlanTierConfig(
        defaultLimit: 50,
        featureLimits: {'maxAthletes': 80},
      );

      expect(config.limitFor('maxAthletes'), 80);
      expect(config.limitFor('maxGroups'), 50);
    });

    test('normalizes plan names and rejects unconfigured plans', () {
      expect(VipPlansConfig.limitFor(' Bronze ', 'maxGroups'), 50);
      expect(
        () => VipPlansConfig.limitFor('unknown', 'maxGroups'),
        throwsArgumentError,
      );
    });
  });

  group('PlanPermissionService', () {
    final service = PlanPermissionService();

    test('allows actions only while usage is below the configured limit', () {
      expect(
        service.canPerformAction(
          plan: 'free',
          feature: 'maxAthletes',
          currentUsage: 49,
        ),
        isTrue,
      );
      expect(
        service.canPerformAction(
          plan: 'free',
          feature: 'maxAthletes',
          currentUsage: 50,
        ),
        isFalse,
      );
    });

    test('denies access for unknown plans', () {
      expect(
        service.canPerformAction(
          plan: 'unknown',
          feature: 'maxAthletes',
          currentUsage: 0,
        ),
        isFalse,
      );
    });

    test('rejects invalid feature names and usage counts', () {
      expect(
        () => service.canPerformAction(
          plan: 'free',
          feature: ' ',
          currentUsage: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => service.canPerformAction(
          plan: 'free',
          feature: 'maxAthletes',
          currentUsage: -1,
        ),
        throwsArgumentError,
      );
    });
  });
}
