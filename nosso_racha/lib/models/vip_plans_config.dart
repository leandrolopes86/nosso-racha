import 'package:cloud_firestore/cloud_firestore.dart';

enum GroupFeature { settings, finance, reports, athleteManagement }

class PlanTierConfig {
  final String id;
  final String displayName;
  final String appPlan;
  final String color;
  final bool active;
  final int defaultLimit;
  final Map<String, int?> featureLimits;
  final Map<String, int?> limits;
  final Set<GroupFeature> features;

  const PlanTierConfig({
    this.id = '',
    this.displayName = '',
    this.appPlan = 'athlete_vip',
    this.color = '#18764f',
    this.active = true,
    required this.defaultLimit,
    this.featureLimits = const {},
    this.limits = const {},
    this.features = const {},
  });

  int? limitFor(String feature) => featureLimits.containsKey(feature)
      ? featureLimits[feature]
      : defaultLimit;
}

class VipPlansConfig {
  static const int defaultLimit = 50;

  static final Map<String, PlanTierConfig> _defaultPlans = {
    'free': PlanTierConfig(
      id: 'free',
      displayName: 'Free',
      appPlan: 'free',
      color: '#64748b',
      defaultLimit: defaultLimit,
      limits: const {
        'maxGroupMemberships': 2,
        'maxOwnedOrganizations': 0,
        'maxOpenEvents': 3,
        'maxAthletesPerGroup': 40,
        'maxCoOrganizersPerGroup': 3,
      },
      featureLimits: const {'reports': 50},
    ),
    'bronze': PlanTierConfig(
      id: 'bronze',
      displayName: 'Bronze',
      appPlan: 'athlete_vip',
      color: '#b77945',
      defaultLimit: defaultLimit,
      limits: const {
        'maxGroupMemberships': 10,
        'maxOwnedOrganizations': 0,
        'maxOpenEvents': 3,
        'maxAthletesPerGroup': 40,
        'maxCoOrganizersPerGroup': 3,
      },
      featureLimits: const {'reports': 50},
    ),
    'silver': PlanTierConfig(
      id: 'silver',
      displayName: 'Silver',
      appPlan: 'athlete_vip',
      color: '#8795a1',
      defaultLimit: defaultLimit,
      limits: const {
        'maxGroupMemberships': 10,
        'maxOwnedOrganizations': 0,
        'maxOpenEvents': 3,
        'maxAthletesPerGroup': 40,
        'maxCoOrganizersPerGroup': 3,
      },
      featureLimits: const {'reports': 50},
    ),
    'gold': PlanTierConfig(
      id: 'gold',
      displayName: 'Gold',
      appPlan: 'athlete_vip',
      color: '#d6a52d',
      defaultLimit: defaultLimit,
      limits: const {
        'maxGroupMemberships': 10,
        'maxOwnedOrganizations': 0,
        'maxOpenEvents': 3,
        'maxAthletesPerGroup': 40,
        'maxCoOrganizersPerGroup': 3,
      },
      featureLimits: const {'reports': 50},
    ),
    'platinum': PlanTierConfig(
      id: 'platinum',
      displayName: 'Platinum',
      appPlan: 'organizer_vip',
      color: '#18764f',
      defaultLimit: defaultLimit,
      limits: const {
        'maxGroupMemberships': 10,
        'maxOwnedOrganizations': null,
        'maxOpenEvents': null,
        'maxAthletesPerGroup': null,
        'maxCoOrganizersPerGroup': null,
      },
      featureLimits: const {'reports': null},
      features: {
        GroupFeature.settings,
        GroupFeature.finance,
        GroupFeature.reports,
        GroupFeature.athleteManagement,
      },
    ),
  };

  static Map<String, PlanTierConfig> _plans = Map.of(_defaultPlans);

  static Map<String, PlanTierConfig> get plans => Map.unmodifiable(_plans);

  static Future<void> loadFromFirestore({FirebaseFirestore? firestore}) async {
    final snapshot = await (firestore ?? FirebaseFirestore.instance)
        .collection('settings')
        .doc('vip_plans')
        .get();
    loadFromMap(snapshot.data());
  }

  static void loadFromMap(Map<String, dynamic>? data) {
    if (data == null) {
      _plans = Map.of(_defaultPlans);
      return;
    }

    final rawPlans = data['plans'];
    if (rawPlans is! Map) {
      throw const FormatException(
        'O catálogo settings/vip_plans não contém um mapa de planos.',
      );
    }

    final loadedPlans = Map<String, PlanTierConfig>.of(_defaultPlans);
    for (final entry in rawPlans.entries) {
      final id = entry.key;
      final value = entry.value;
      if (id is! String || !_isValidPlanId(id)) {
        throw const FormatException(
          'O catálogo settings/vip_plans contém um ID ou plano inválido.',
        );
      }
      final canonicalId = _canonicalPlanId(id);
      if (!_defaultPlans.containsKey(canonicalId)) continue;
      if (value is! Map) {
        throw const FormatException(
          'O catálogo settings/vip_plans contém um ID ou plano inválido.',
        );
      }
      final parsed = _parsePlan(canonicalId, Map<String, dynamic>.from(value));
      if (id == 'prata' && rawPlans.containsKey('silver')) continue;
      if (id == 'ouro' && rawPlans.containsKey('gold')) continue;
      final defaults = _defaultPlans[canonicalId]!;
      loadedPlans[canonicalId] = PlanTierConfig(
        id: canonicalId,
        displayName: defaults.displayName,
        appPlan: defaults.appPlan,
        color: parsed.color,
        active: canonicalId == 'free' || parsed.active,
        defaultLimit: parsed.defaultLimit,
        limits: parsed.limits,
        featureLimits: parsed.featureLimits,
        features: canonicalId == 'platinum'
            ? parsed.features
            : defaults.features,
      );
    }
    _plans = loadedPlans;
  }

  static bool hasPlan(String plan) => _plans.containsKey(_normalizePlan(plan));

  static bool isPaidVipTier(String? plan) {
    if (plan == null) return false;
    final normalized = _normalizePlan(plan);
    final tier = _plans[normalized];
    if (tier != null) return tier.appPlan != 'free';
    return const {'bronze', 'silver', 'gold', 'platinum'}.contains(normalized);
  }

  static String appPlanForVipTier(String plan) {
    final normalized = _normalizePlan(plan);
    final tier = _plans[normalized];
    if (tier != null) return tier.appPlan;
    return switch (normalized) {
      'platinum' => 'organizer_vip',
      'bronze' || 'silver' || 'gold' => 'athlete_vip',
      _ => normalized,
    };
  }

  static int? limitFor(String plan, String feature) {
    final normalizedPlan = _normalizePlan(plan);
    final config = _plans[normalizedPlan];
    if (config == null) {
      throw ArgumentError.value(plan, 'plan', 'Plano não configurado.');
    }
    return config.limitFor(feature);
  }

  static int? planLimit(String plan, String field) {
    final config = _plans[_normalizePlan(plan)];
    if (config == null || !config.limits.containsKey(field)) return null;
    return config.limits[field];
  }

  static PlanTierConfig? tierFor(String plan) => _plans[_normalizePlan(plan)];

  static String displayNameFor(String? plan) {
    if (plan == null || plan.trim().isEmpty) return 'Free';
    return tierFor(plan)?.displayName ?? 'Free';
  }

  static Set<GroupFeature> featuresFor(String plan) {
    final normalized = _normalizePlan(plan);
    if (normalized == 'organizer_vip') {
      return _plans['platinum']?.features ?? const {};
    }
    return _plans[normalized]?.features ?? const {};
  }

  static Set<GroupFeature> featuresForVipTier(String plan) {
    final normalized = _normalizePlan(plan);
    final tier = _plans[normalized];
    return tier?.features ?? featuresFor(appPlanForVipTier(plan));
  }

  static bool isActiveStatus(String? status) =>
      status == null || status == 'active' || status == 'trialing';

  static PlanTierConfig _parsePlan(String id, Map<String, dynamic> value) {
    final appPlan = value['appPlan'];
    final displayName = value['displayName'];
    final color = value['color'];
    final defaultLimit = value['defaultLimit'];
    final rawLimits = value['limits'];
    final rawFeatureLimits = value['featureLimits'];
    final rawFeatures = value['features'];

    if (displayName is! String ||
        displayName.trim().length < 2 ||
        !const {'free', 'athlete_vip', 'organizer_vip'}.contains(appPlan) ||
        color is! String ||
        !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color) ||
        defaultLimit is! int ||
        defaultLimit < 0 ||
        rawLimits is! Map ||
        rawFeatureLimits is! Map ||
        rawFeatures is! List) {
      throw FormatException('A definição do plano "$id" está malformada.');
    }

    final limits = _parseLimits(rawLimits, id);
    final featureLimits = _parseLimits(rawFeatureLimits, id);
    final features = <GroupFeature>{};
    for (final feature in rawFeatures) {
      final parsedFeature = switch (feature) {
        'settings' => GroupFeature.settings,
        'finance' => GroupFeature.finance,
        'reports' => GroupFeature.reports,
        'athleteManagement' => GroupFeature.athleteManagement,
        _ => null,
      };
      if (parsedFeature == null) {
        throw FormatException('O plano "$id" contém um recurso desconhecido.');
      }
      features.add(parsedFeature);
    }

    return PlanTierConfig(
      id: id,
      displayName: displayName.trim(),
      appPlan: appPlan as String,
      color: color,
      active: value['active'] == true,
      defaultLimit: defaultLimit,
      limits: limits,
      featureLimits: featureLimits,
      features: features,
    );
  }

  static Map<String, int?> _parseLimits(Map raw, String planId) {
    final limits = <String, int?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String ||
          (entry.value != null && (entry.value is! int || entry.value < 0))) {
        throw FormatException('Os limites do plano "$planId" são inválidos.');
      }
      limits[entry.key as String] = entry.value as int?;
    }
    return limits;
  }

  static bool _isValidPlanId(String id) =>
      RegExp(r'^[a-z][a-z0-9_]{1,39}$').hasMatch(id);

  static String _normalizePlan(String plan) =>
      _canonicalPlanId(plan.trim().toLowerCase().replaceAll(' ', '_'));

  static String _canonicalPlanId(String id) => switch (id) {
    'prata' => 'silver',
    'ouro' => 'gold',
    _ => id,
  };
}
