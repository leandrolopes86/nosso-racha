import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../services/event_service.dart';

class PendingJoinRequests extends StatelessWidget {
  final String eventId;
  final EventService eventService;
  final String? groupId;
  final String userId;
  final bool isEventCreator;

  const PendingJoinRequests({
    super.key,
    required this.eventId,
    required this.eventService,
    required this.groupId,
    required this.userId,
    required this.isEventCreator,
  });

  @override
  Widget build(BuildContext context) {
    if (isEventCreator) return _buildRequestsIcon(context);
    if (groupId == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .snapshots(),
      builder: (context, groupSnapshot) {
        if (!groupSnapshot.hasData || !groupSnapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final group = groupSnapshot.data!.data()!;
        final ownerId =
            group['owner_id'] ??
            group['ownerId'] ??
            group['organizer_id'] ??
            group['organizer_uid'] ??
            group['organizerId'];
        if (ownerId == userId) return _buildRequestsIcon(context);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId)
              .collection('members')
              .doc(userId)
              .snapshots(),
          builder: (context, memberSnapshot) {
            final role = memberSnapshot.data?.data()?['role'];
            if (![
              'owner',
              'organizer',
              'admin',
              'co_organizer',
            ].contains(role)) {
              return const SizedBox.shrink();
            }
            return _buildRequestsIcon(context);
          },
        );
      },
    );
  }

  Widget _buildRequestsIcon(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: eventService.getJoinRequestsStream(eventId),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        final hasError = snapshot.hasError;
        return IconButton(
          tooltip: hasError
              ? 'Não foi possível carregar as solicitações'
              : count == 0
              ? 'Solicitações de participação'
              : '$count solicitação(ões) pendente(s)',
          onPressed: () => _openRequests(context),
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text(count > 99 ? '99+' : '$count'),
            child: Icon(
              hasError
                  ? Icons.error_outline
                  : Icons.notifications_active_outlined,
              color: hasError ? Theme.of(context).colorScheme.error : null,
            ),
          ),
        );
      },
    );
  }

  void _openRequests(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _PendingRequestsSheet(eventId: eventId, eventService: eventService),
    );
  }
}

class _PendingRequestsSheet extends StatefulWidget {
  final String eventId;
  final EventService eventService;

  const _PendingRequestsSheet({
    required this.eventId,
    required this.eventService,
  });

  @override
  State<_PendingRequestsSheet> createState() => _PendingRequestsSheetState();
}

class _PendingRequestsSheetState extends State<_PendingRequestsSheet> {
  final Set<String> _processingRequests = {};

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Solicitações pendentes',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: widget.eventService.getJoinRequestsStream(widget.eventId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _loadErrorMessage(snapshot.error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final requests = [...snapshot.data!.docs]
                  ..sort(
                    (a, b) => _requestedAt(
                      a.data(),
                    ).compareTo(_requestedAt(b.data())),
                  );
                if (requests.isEmpty) {
                  return const Center(
                    child: Text('Não há solicitações pendentes.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount: requests.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    return _buildRequestCard(context, request);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> request,
  ) {
    final data = request.data();
    final profile = data['profile'] as Map<String, dynamic>? ?? const {};
    final name = (profile['name'] as String?)?.trim().isNotEmpty == true
        ? profile['name'] as String
        : (data['nickname'] as String?)?.trim().isNotEmpty == true
        ? data['nickname'] as String
        : data['name'] as String? ?? 'Atleta';
    final role = data['role_in_match'] == 'goalkeeper' ? 'Goleiro' : 'Linha';
    final requestedAt = _requestedAt(data);
    final isProcessing = _processingRequests.contains(request.id);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
              ),
              title: Text(name),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vaga solicitada: $role'),
                    const SizedBox(height: 4),
                    Text(
                      'Pedido em ${DateFormat('dd/MM/yyyy HH:mm').format(requestedAt)}',
                    ),
                  ],
                ),
              ),
              onTap: () => _showAthleteProfile(context, name, profile),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: isProcessing
                      ? null
                      : () => _review(
                          request.id,
                          () => widget.eventService.rejectJoinRequest(
                            widget.eventId,
                            request.id,
                          ),
                        ),
                  icon: const Icon(Icons.close),
                  label: const Text('Recusar'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: isProcessing
                      ? null
                      : () => _review(
                          request.id,
                          () => widget.eventService.approveJoinRequest(
                            widget.eventId,
                            request.id,
                          ),
                        ),
                  icon: isProcessing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Aceitar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _loadErrorMessage(Object? error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Sem permissão para consultar os pedidos. Confirme se sua conta '
            'é organizadora deste evento e se as regras do Firestore foram publicadas.';
      }
      if (error.code == 'failed-precondition') {
        return 'O Firestore não conseguiu executar a consulta. Confira a '
            'configuração do banco e tente novamente.';
      }
    }
    return 'Não foi possível carregar as solicitações. Tente novamente mais tarde.';
  }

  DateTime _requestedAt(Map<String, dynamic> data) {
    final value = data['requested_at'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _showAthleteProfile(
    BuildContext context,
    String name,
    Map<String, dynamic> profile,
  ) {
    final positions = (profile['positions'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    final phone = (profile['phone'] as String?)?.trim() ?? '';
    final ratingValue = profile['rating'];
    final rating = ratingValue is num ? ratingValue.toDouble() : 0.0;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            CircleAvatar(
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(name)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Posição principal: '
              '${positions.isEmpty ? 'Não informada' : positions.first}',
            ),
            const SizedBox(height: 8),
            Text('Telefone: ${phone.isEmpty ? 'Não informado' : phone}'),
            const SizedBox(height: 8),
            Text(
              'Nota técnica cadastrada: '
              '${rating > 0 ? '${rating.toStringAsFixed(0)}/100' : 'Sem avaliação'}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _review(String requestId, Future<void> Function() action) async {
    setState(() => _processingRequests.add(requestId));
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _processingRequests.remove(requestId));
    }
  }
}
