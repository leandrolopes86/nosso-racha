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
}
