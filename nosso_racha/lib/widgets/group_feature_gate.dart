import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/vip_plans_config.dart';
import '../services/group_plan_service.dart';

class GroupFeatureGate extends StatefulWidget {
  final String groupId;
  final GroupFeature feature;
  final Widget child;

  const GroupFeatureGate({
    super.key,
    required this.groupId,
    required this.feature,
    required this.child,
  });

  @override
  State<GroupFeatureGate> createState() => _GroupFeatureGateState();
}

class _GroupFeatureGateState extends State<GroupFeatureGate> {
  late Stream<GroupPlanAccess> _accessStream;

  @override
  void initState() {
    super.initState();
    _watchAccess();
  }

  @override
  void didUpdateWidget(covariant GroupFeatureGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId) _watchAccess();
  }

  void _watchAccess() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    _accessStream = userId == null
        ? Stream.error(StateError('Entre na sua conta para continuar.'))
        : GroupPlanService().watchAccess(
            groupId: widget.groupId,
            userId: userId,
          );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GroupPlanAccess>(
      stream: _accessStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                'Não foi possível validar o acesso: ${snapshot.error}',
              ),
            ),
          );
        }
        if (snapshot.data?.allows(widget.feature) != true) {
          return const Scaffold(
            body: Center(
              child: Text('Este recurso exige um plano VIP ativo neste grupo.'),
            ),
          );
        }
        return widget.child;
      },
    );
  }
}
