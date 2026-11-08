import 'package:flutter/foundation.dart'; // Para checar plataforma
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/event_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/event_service.dart';
import '../../services/notification_service.dart';
import '../../services/group_plan_service.dart';
import '../../models/vip_plans_config.dart';
import '../../widgets/group_feature_gate.dart';
import '../events/create_event_screen.dart';
import '../events/event_details_screen.dart';
import '../admin/user_management_screen.dart';
import '../admin/settings_screen.dart';
import '../profile/user_profile_screen.dart';
import '../reports/reports_screen.dart';
import '../finance/finance_screen.dart';
import '../misc/easter_egg_screen.dart';

class HomeScreen extends StatefulWidget {
  final String? groupId; // ID do grupo acessado dinamicamente

  const HomeScreen({super.key, this.groupId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showHistory = false;
  int _easterEggCount = 0;
  String _groupName = "Carregando grupo...";
  final Map<String, Future<_EventGroupInfo?>> _groupInfoCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // TODO (Futuro): Reavaliar contexto de permissão específico para notificações do grupo
      if (!mounted || widget.groupId != null) return;
      context.read<NotificationService>().init();
    });
    _loadGroupName();
  }

  // Busca o nome do grupo dinamicamente no Firestore com base no groupId
  Future<void> _loadGroupName() async {
    if (widget.groupId == null) {
      setState(() => _groupName = "LCS - Próximos Jogos");
      return;
    }

    try {
      final groupInfo = await _fetchGroupInfo(widget.groupId!);
      if (mounted) {
        setState(() => _groupName = groupInfo?.name ?? "Grupo indisponível");
      }
    } on FirebaseException {
      if (mounted) {
        setState(() => _groupName = "Grupo indisponível");
      }
    }
  }

  Future<_EventGroupInfo?> _fetchGroupInfo(String groupId) {
    return _groupInfoCache.putIfAbsent(groupId, () async {
      final doc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      final name = data['name'];
      final ownerName = data['owner_name'];
      return _EventGroupInfo(
        name: name is String && name.trim().isNotEmpty ? name.trim() : null,
        ownerName: ownerName is String && ownerName.trim().isNotEmpty
            ? ownerName.trim()
            : null,
      );
    });
  }

  // --- LÓGICA DO EASTER EGG (Só Mobile) ---
  void _handleEasterEgg() {
    if (kIsWeb) {
      return;
    }
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      return;
    }

    _easterEggCount++;

    if (_easterEggCount == 7) {
      _easterEggCount = 0;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const EasterEggScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final eventService = Provider.of<EventService>(context, listen: false);
    final user = authService.currentUser;
    final isCompact = MediaQuery.sizeOf(context).width < 700;

    if (user == null) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _handleEasterEgg,
          behavior: HitTestBehavior.opaque,
          child: Text(_groupName, overflow: TextOverflow.ellipsis),
        ),
        centerTitle: false,
        actions: [
          _buildGroupTools(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UserProfileScreen()),
              ),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: Text(
                  user.name.isNotEmpty == true
                      ? user.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ),
            ),
          ),

          IconButton(
            icon: const Icon(LucideIcons.logOut, color: Colors.white70),
            tooltip: "Sair",
            onPressed: () => authService.signOut(),
          ),
        ],
      ),
      floatingActionButton: (user.canCreateEvent)
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateEventScreen(groupId: widget.groupId),
                ),
              ),
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              icon: const Icon(LucideIcons.plus),
              label: const Text("NOVO JOGO"),
            )
          : null,
      body: Column(
        children: [
          SwitchListTile(
            tileColor: Theme.of(context).cardColor,
            dense: true,
            secondary: Icon(
              _showHistory ? LucideIcons.history : LucideIcons.calendarClock,
              color: _showHistory ? Colors.orange : Colors.green,
            ),
            title: Text(
              _showHistory
                  ? "Exibindo todos (Incluindo Finalizados)"
                  : "Exibindo apenas jogos em aberto",
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            value: _showHistory,
            activeThumbColor: Colors.orange,
            onChanged: (val) => setState(() => _showHistory = val),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = constraints.maxWidth > 1200
                    ? 1200.0
                    : constraints.maxWidth;
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: contentWidth,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: eventService.getEventsStream(
                        groupId: widget.groupId,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          final error = snapshot.error;
                          final message =
                              error is FirebaseException &&
                                  error.code == 'permission-denied'
                              ? 'Você não tem acesso a esta organização.'
                              : 'Não foi possível carregar os eventos: $error';
                          return Center(child: Text(message));
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  LucideIcons.calendarX,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  "Nenhum racha agendado.",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        }

                        final events = snapshot.data!.docs
                            .map(
                              (doc) => EventModel.fromMap(
                                doc.id,
                                doc.data() as Map<String, dynamic>,
                              ),
                            )
                            .toList();

                        events.sort(
                          (a, b) => b.startDateTime.compareTo(a.startDateTime),
                        );

                        // Filtro por Grupo (caso o groupId seja fornecido) e Histórico
                        final filteredEvents = events.where((event) {
                          if (!_showHistory && event.status == 'finished')
                            return false;
                          // A consulta contempla tanto o formato atual quanto o campo legado.
                          if (widget.groupId != null &&
                              event.groupId != widget.groupId) {
                            return false;
                          }
                          return true;
                        }).toList();

                        if (filteredEvents.isEmpty) {
                          return const Center(
                            child: Text(
                              "Nenhum racha em aberto para este grupo.",
                            ),
                          );
                        }

                        return ListView.builder(
                          padding: EdgeInsets.all(isCompact ? 12 : 24),
                          itemCount: filteredEvents.length,
                          itemBuilder: (context, index) {
                            final event = filteredEvents[index];
                            return _buildEventCard(context, event);
                          },
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupTools() {
    final groupId = widget.groupId;
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (groupId == null || userId == null) {
      return const SizedBox.shrink();
    }

    final groupReference = FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: groupReference.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _groupToolsError(snapshot.error!);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _groupToolsLoading();
        }
        final group = snapshot.data?.data();
        if (group == null) return const SizedBox.shrink();

        final ownerId = UserModel.groupOwnerId(group);
        if (ownerId == userId) {
          return _buildAuthorizedGroupTools(groupId, userId);
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: groupReference.collection('members').doc(userId).snapshots(),
          builder: (context, membershipSnapshot) {
            if (membershipSnapshot.hasError) {
              return _groupToolsError(membershipSnapshot.error!);
            }
            if (membershipSnapshot.connectionState == ConnectionState.waiting) {
              return _groupToolsLoading();
            }
            final role = membershipSnapshot.data?.data()?['role'] as String?;
            if (!GroupPlanService.managerRoles.contains(role)) {
              return const SizedBox.shrink();
            }
            return _buildAuthorizedGroupTools(groupId, userId);
          },
        );
      },
    );
  }

  Widget _buildAuthorizedGroupTools(String groupId, String userId) {
    return StreamBuilder<GroupPlanAccess>(
      stream: GroupPlanService().watchAccess(groupId: groupId, userId: userId),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _groupToolsError(snapshot.error!);
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _groupToolsLoading();
        }
        final access = snapshot.data;
        if (access?.isAuthorized != true) return const SizedBox.shrink();

        if (MediaQuery.sizeOf(context).width < 700) {
          return PopupMenuButton<GroupFeature>(
            tooltip: 'Ferramentas do Grupo',
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (feature) => _openGroupFeature(
              feature,
              _groupFeatureScreen(feature, groupId),
            ),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: GroupFeature.settings,
                child: Text('Configurações do Grupo'),
              ),
              PopupMenuItem(
                value: GroupFeature.finance,
                child: Text('Financeiro / Caixa'),
              ),
              PopupMenuItem(
                value: GroupFeature.reports,
                child: Text('Relatórios'),
              ),
              PopupMenuItem(
                value: GroupFeature.athleteManagement,
                child: Text('Gerenciar Atletas'),
              ),
            ],
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(LucideIcons.settings, color: Colors.white),
              tooltip: 'Configurações do Grupo',
              onPressed: () => _openGroupFeature(
                GroupFeature.settings,
                SettingsScreen(groupId: groupId),
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.wallet, color: Colors.white),
              tooltip: 'Financeiro / Caixa',
              onPressed: () => _openGroupFeature(
                GroupFeature.finance,
                FinanceScreen(groupId: groupId),
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.barChart3, color: Colors.white),
              tooltip: 'Relatórios',
              onPressed: () => _openGroupFeature(
                GroupFeature.reports,
                ReportsScreen(groupId: groupId),
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.users, color: Colors.white),
              tooltip: 'Gerenciar Atletas',
              onPressed: () => _openGroupFeature(
                GroupFeature.athleteManagement,
                UserManagementScreen(groupId: groupId),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _groupFeatureScreen(GroupFeature feature, String groupId) {
    return switch (feature) {
      GroupFeature.settings => SettingsScreen(groupId: groupId),
      GroupFeature.finance => FinanceScreen(groupId: groupId),
      GroupFeature.reports => ReportsScreen(groupId: groupId),
      GroupFeature.athleteManagement => UserManagementScreen(groupId: groupId),
    };
  }

  Widget _groupToolsLoading() => const SizedBox(
    width: 24,
    height: 24,
    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
  );

  Widget _groupToolsError(Object error) {
    return IconButton(
      icon: const Icon(LucideIcons.circleAlert, color: Colors.orange),
      tooltip: 'Falha ao validar as permissões do grupo',
      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível validar o acesso ao grupo: $error'),
        ),
      ),
    );
  }

  void _openGroupFeature(GroupFeature feature, Widget screen) {
    final groupId = widget.groupId;
    if (groupId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GroupFeatureGate(groupId: groupId, feature: feature, child: screen),
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, EventModel event) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isChristmas =
        Theme.of(context).scaffoldBackgroundColor.toARGB32() == 0xFFC62828;

    final status = event.status;
    final titleColor = isChristmas ? Colors.white : Colors.black87;
    final subtitleColor = isChristmas ? Colors.white70 : Colors.grey[700];
    final iconColor = isChristmas ? Colors.white70 : Colors.grey;

    Color cardColor = status == 'finished'
        ? (isDark ? Colors.grey[900]! : Colors.grey[100]!)
        : Theme.of(context).cardTheme.color ?? Theme.of(context).cardColor;

    String statusText;
    switch (status) {
      case 'published':
        statusText = "Lista Publicada";
        break;
      case 'finished':
        statusText = "Encerrado";
        break;
      default:
        statusText = "Em Aberto";
    }

    final statusColor = status == 'finished'
        ? Colors.grey
        : status == 'published'
        ? Colors.blue
        : const Color(0xFF2E7D32);
    final formattedDate = DateFormat('dd/MM/yyyy').format(event.startDateTime);
    final weekday = const [
      'segunda-feira',
      'terça-feira',
      'quarta-feira',
      'quinta-feira',
      'sexta-feira',
      'sábado',
      'domingo',
    ][event.startDateTime.weekday - 1];
    final startTime = DateFormat('HH:mm').format(event.startDateTime);
    final endTime = DateFormat('HH:mm').format(event.endDateTime);
    final mapDestination = _eventMapDestination(event);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  EventDetailsScreen(eventId: event.id!, title: event.title),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _buildEventGroupBadge(context, event.groupId),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isChristmas
                          ? Colors.white24
                          : statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isChristmas ? Colors.white70 : statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                event.title,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (event.location.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Tooltip(
                  message: mapDestination == null
                      ? ''
                      : 'Abrir rota no Google Maps',
                  child: InkWell(
                    onTap: mapDestination == null
                        ? null
                        : () => _openEventDirections(mapDestination),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.mapPin,
                            size: 16,
                            color: mapDestination == null
                                ? iconColor
                                : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              event.location,
                              style: TextStyle(
                                color: mapDestination == null
                                    ? subtitleColor
                                    : Theme.of(context).colorScheme.primary,
                                decoration: mapDestination == null
                                    ? null
                                    : TextDecoration.underline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (mapDestination != null) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.directions_outlined,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (event.locationNote?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: Text(
                    event.locationNote!,
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Divider(height: 1, color: isChristmas ? Colors.white24 : null),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              LucideIcons.calendarDays,
                              size: 16,
                              color: iconColor,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '$weekday, $formattedDate',
                                style: TextStyle(color: subtitleColor),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(LucideIcons.clock, size: 16, color: iconColor),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Início $startTime • Fim $endTime',
                                style: TextStyle(color: subtitleColor),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'DETALHES',
                    style: TextStyle(
                      color: isChristmas
                          ? Colors.white
                          : Theme.of(context).colorScheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    LucideIcons.arrowRight,
                    size: 16,
                    color: isChristmas
                        ? Colors.white
                        : Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _eventMapDestination(EventModel event) {
    if (event.latitude != null && event.longitude != null) {
      return '${event.latitude},${event.longitude}';
    }

    final addressParts =
        [
              event.street,
              event.addressNumber,
              event.addressComplement,
              event.neighborhood,
              event.city,
              event.state,
              event.postcode,
              event.country,
            ]
            .whereType<String>()
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty);
    final address = addressParts.join(', ');
    if (address.isEmpty) return null;

    return [
      event.location,
      address,
    ].where((part) => part.trim().isNotEmpty).join(', ');
  }

  Future<void> _openEventDirections(String destination) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination,
    });

    try {
      final opened = kIsWeb
          ? await launchUrl(uri, webOnlyWindowName: '_blank')
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o Google Maps.'),
          ),
        );
      }
    } on PlatformException {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o Google Maps.'),
          ),
        );
      }
    }
  }

  Widget _buildEventGroupBadge(BuildContext context, String? groupId) {
    if (groupId == null || groupId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<_EventGroupInfo?>(
      future: _fetchGroupInfo(groupId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done &&
            !snapshot.hasError) {
          return const SizedBox.shrink();
        }
        if (snapshot.data == null && !snapshot.hasError) {
          return const SizedBox.shrink();
        }

        final groupInfo = snapshot.data;
        final groupName = groupInfo?.name ?? 'Grupo indisponível';
        final ownerName = groupInfo?.ownerName ?? 'Responsável não informado';
        final isChristmas =
            Theme.of(context).scaffoldBackgroundColor.toARGB32() == 0xFFC62828;
        final color = Theme.of(context).colorScheme.primary;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isChristmas
                    ? Colors.white24
                    : color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                groupName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isChristmas ? Colors.white : color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.userRound,
                  size: 13,
                  color: isChristmas ? Colors.white70 : Colors.grey[600],
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    ownerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isChristmas ? Colors.white70 : Colors.grey[700],
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _EventGroupInfo {
  final String? name;
  final String? ownerName;

  const _EventGroupInfo({required this.name, required this.ownerName});
}
