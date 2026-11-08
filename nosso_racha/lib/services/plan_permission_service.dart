import '../models/vip_plans_config.dart';

class PlanPermissionService {
  bool canPerformAction({
    required String plan,
    required String feature,
    required int currentUsage,
  }) {
    if (feature.trim().isEmpty) {
      throw ArgumentError.value(
        feature,
        'feature',
        'Informe a funcionalidade.',
      );
    }
    if (currentUsage < 0) {
      throw ArgumentError.value(
        currentUsage,
        'currentUsage',
        'O uso atual não pode ser negativo.',
      );
    }
    if (!VipPlansConfig.hasPlan(plan)) return false;

    final limit = VipPlansConfig.limitFor(plan, feature);
    return limit == null || currentUsage < limit;
  }
}
