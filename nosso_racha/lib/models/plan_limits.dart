import 'vip_plans_config.dart';

class PlanLimits {
  final int? maxGroupMemberships;
  final int? maxOwnedOrganizations;
  final int? maxOpenEvents;
  final int? maxAthletesPerGroup;
  final int? maxCoOrganizersPerGroup;
  final bool canCreateOrganizations;

  const PlanLimits({
    required this.maxGroupMemberships,
    required this.maxOwnedOrganizations,
    required this.maxOpenEvents,
    required this.maxAthletesPerGroup,
    required this.maxCoOrganizersPerGroup,
    required this.canCreateOrganizations,
  });

  static const freeAthlete = PlanLimits(
    maxGroupMemberships: 2,
    maxOwnedOrganizations: 0,
    maxOpenEvents: 3,
    maxAthletesPerGroup: 40,
    maxCoOrganizersPerGroup: 3,
    canCreateOrganizations: false,
  );

  static const athleteVip = PlanLimits(
    maxGroupMemberships: 10,
    maxOwnedOrganizations: 0,
    maxOpenEvents: 3,
    maxAthletesPerGroup: 40,
    maxCoOrganizersPerGroup: 3,
    canCreateOrganizations: false,
  );

  static const organizer = PlanLimits(
    maxGroupMemberships: 2,
    maxOwnedOrganizations: 0,
    maxOpenEvents: 3,
    maxAthletesPerGroup: 40,
    maxCoOrganizersPerGroup: 3,
    canCreateOrganizations: false,
  );

  static const organizerVip = PlanLimits(
    maxGroupMemberships: 10,
    maxOwnedOrganizations: null,
    maxOpenEvents: null,
    maxAthletesPerGroup: null,
    maxCoOrganizersPerGroup: null,
    canCreateOrganizations: true,
  );

  static PlanLimits forPlan(String plan) => switch (plan) {
    'athlete_vip' => athleteVip,
    'organizer_vip' => organizerVip,
    _ => freeAthlete,
  };

  static PlanLimits forOrganizerPlan(String plan) =>
      plan == 'organizer_vip' ? organizerVip : organizer;

  static PlanLimits forVipTier(String tier, String fallbackPlan) {
    final normalizedTier = tier.trim().toLowerCase().replaceAll(' ', '_');
    final config = VipPlansConfig.plans[normalizedTier];
    if (config == null) return forPlan(fallbackPlan);
    final fallback = forPlan(
      config.appPlan == 'free' ? 'free' : config.appPlan,
    );
    int? configuredLimit(String field, int? defaultValue) =>
        config.limits.containsKey(field) ? config.limits[field] : defaultValue;

    return PlanLimits(
      maxGroupMemberships: configuredLimit(
        'maxGroupMemberships',
        fallback.maxGroupMemberships,
      ),
      maxOwnedOrganizations: configuredLimit(
        'maxOwnedOrganizations',
        fallback.maxOwnedOrganizations,
      ),
      maxOpenEvents: configuredLimit('maxOpenEvents', fallback.maxOpenEvents),
      maxAthletesPerGroup: configuredLimit(
        'maxAthletesPerGroup',
        fallback.maxAthletesPerGroup,
      ),
      maxCoOrganizersPerGroup: configuredLimit(
        'maxCoOrganizersPerGroup',
        fallback.maxCoOrganizersPerGroup,
      ),
      canCreateOrganizations:
          config.appPlan == 'organizer_vip' &&
          (config.limits['maxOwnedOrganizations'] == null ||
              config.limits['maxOwnedOrganizations']! > 0),
    );
  }
}
