enum GroupFeature { settings, finance, reports, athleteManagement }

class PlanTierConfig {
  final int defaultLimit;
  final Map<String, int> featureLimits;

  const PlanTierConfig({
    required this.defaultLimit,
    this.featureLimits = const {},
  });

  int limitFor(String feature) => featureLimits[feature] ?? defaultLimit;
}

class VipPlansConfig {
  static const int defaultLimit = 50;

  static const Map<String, PlanTierConfig> plans = {
    'free': PlanTierConfig(defaultLimit: defaultLimit),
    'bronze': PlanTierConfig(defaultLimit: defaultLimit),
    'silver': PlanTierConfig(defaultLimit: defaultLimit),
    'gold': PlanTierConfig(defaultLimit: defaultLimit),
    'platinum': PlanTierConfig(defaultLimit: defaultLimit),
  };

  static const Map<String, Set<GroupFeature>> _featuresByPlan = {
    'organizer_vip': {
      GroupFeature.settings,
      GroupFeature.finance,
      GroupFeature.reports,
      GroupFeature.athleteManagement,
    },
  };

  static bool hasPlan(String plan) => plans.containsKey(_normalizePlan(plan));

  static bool isPaidVipTier(String? plan) {
    if (plan == null) return false;
    return const {
      'bronze',
      'silver',
      'gold',
      'ouro',
      'prata',
      'platinum',
    }.contains(_normalizePlan(plan));
  }

  static String appPlanForVipTier(String plan) {
    return switch (_normalizePlan(plan)) {
      'platinum' => 'organizer_vip',
      'bronze' || 'silver' || 'gold' || 'ouro' || 'prata' => 'athlete_vip',
      _ => _normalizePlan(plan),
    };
  }

  static int limitFor(String plan, String feature) {
    final normalizedPlan = _normalizePlan(plan);
    final config = plans[normalizedPlan];
    if (config == null) {
      throw ArgumentError.value(plan, 'plan', 'Plano não configurado.');
    }
    return config.limitFor(feature);
  }

  static Set<GroupFeature> featuresFor(String plan) =>
      _featuresByPlan[appPlanForVipTier(plan)] ?? const {};

  static bool isActiveStatus(String? status) =>
      status == null || status == 'active' || status == 'trialing';

  static String _normalizePlan(String plan) => plan.trim().toLowerCase();
}
