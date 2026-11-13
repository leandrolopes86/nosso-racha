import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/vip_plans_config.dart';

class VipPlanBadge extends StatefulWidget {
  final String plan;
  final DateTime? expiresAt;
  final bool compact;

  const VipPlanBadge({
    super.key,
    required this.plan,
    required this.expiresAt,
    this.compact = false,
  });

  @override
  State<VipPlanBadge> createState() => _VipPlanBadgeState();
}

class VipUserBadge extends StatefulWidget {
  final String uid;
  final String fallbackPlan;
  final DateTime? fallbackExpiresAt;
  final bool compact;

  const VipUserBadge({
    super.key,
    required this.uid,
    this.fallbackPlan = '',
    this.fallbackExpiresAt,
    this.compact = false,
  });

  @override
  State<VipUserBadge> createState() => _VipUserBadgeState();
}

class _VipUserBadgeState extends State<VipUserBadge> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _badgeStream;

  @override
  void initState() {
    super.initState();
    _badgeStream = _streamFor(widget.uid);
  }

  @override
  void didUpdateWidget(covariant VipUserBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _badgeStream = _streamFor(widget.uid);
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _streamFor(String uid) =>
      FirebaseFirestore.instance
          .collection('vip_public_badges')
          .doc(uid)
          .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _badgeStream,
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return VipPlanBadge(
            plan: widget.fallbackPlan,
            expiresAt: widget.fallbackExpiresAt,
            compact: widget.compact,
          );
        }
        final data = snapshot.data!.data();
        if (data == null) {
          return VipPlanBadge(
            plan: widget.fallbackPlan,
            expiresAt: widget.fallbackExpiresAt,
            compact: widget.compact,
          );
        }
        final expiresAt = data['expiresAt'];
        return VipPlanBadge(
          plan: data['plan'] as String? ?? '',
          expiresAt: expiresAt is Timestamp ? expiresAt.toDate() : null,
          compact: widget.compact,
        );
      },
    );
  }
}

class _VipPlanBadgeState extends State<VipPlanBadge> {
  Timer? _expirationTimer;

  bool get _isActive =>
      VipPlansConfig.isPaidVipTier(widget.plan) &&
      widget.expiresAt != null &&
      widget.expiresAt!.isAfter(DateTime.now());

  @override
  void initState() {
    super.initState();
    _scheduleExpiration();
  }

  @override
  void didUpdateWidget(covariant VipPlanBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan != widget.plan ||
        oldWidget.expiresAt != widget.expiresAt) {
      _scheduleExpiration();
    }
  }

  void _scheduleExpiration() {
    _expirationTimer?.cancel();
    final expiresAt = widget.expiresAt;
    if (VipPlansConfig.isPaidVipTier(widget.plan) &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now())) {
      _expirationTimer = Timer(expiresAt.difference(DateTime.now()), () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _expirationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isActive) return const SizedBox.shrink();
    final colorHex = VipPlansConfig.tierFor(widget.plan)?.color ?? '#d6a52d';
    final color = Color(
      int.parse(colorHex.substring(1), radix: 16) | 0xFF000000,
    );
    final label = VipPlansConfig.displayNameFor(widget.plan).toUpperCase();

    return Tooltip(
      message:
          'VIP $label ativo até ${widget.expiresAt!.day.toString().padLeft(2, '0')}/'
          '${widget.expiresAt!.month.toString().padLeft(2, '0')}/${widget.expiresAt!.year}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 6 : 8,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.workspace_premium,
              size: widget.compact ? 13 : 15,
              color: color,
            ),
            if (!widget.compact) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
