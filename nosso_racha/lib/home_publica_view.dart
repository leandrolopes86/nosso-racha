import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/auth_service.dart';
import 'services/event_service.dart';
import 'models/event_model.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/profile/profile_modal.dart';
import 'screens/home/home_screen.dart';
import 'screens/group/create_group_modal.dart';
import 'screens/events/event_details_screen.dart';

class HomePublicaView extends StatefulWidget {
  const HomePublicaView({super.key});

  @override
  State<HomePublicaView> createState() => _HomePublicaViewState();
}

class _HomePublicaViewState extends State<HomePublicaView> {
  String _filtroBairro = '';
  Map<String, dynamic>? _meuGrupo;
  List<Map<String, dynamic>> _meusGrupos = [];
  String? _usuarioDosGrupos;
  String? _carregamentoDeGruposAgendadoPara;
  bool _carregandoGrupo = false;
  bool _processandoConvite = false;
  bool _conviteProcessado = false;
  Position? _currentPosition;
  bool _isLoadingLocation = false;
  String _locationMessage = 'Obtendo localização...';
  late final Stream<QuerySnapshot> _publicEventsStream;
  final Map<String, Future<String?>> _groupNameFutures = {};

  @override
  void initState() {
    super.initState();
    _publicEventsStream = context.read<EventService>().getEventsStream();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buscarMeuGrupo();
      _loadCurrentLocation();
    });
  }

  Future<String?> _getGroupName(String groupId) {
    return _groupNameFutures.putIfAbsent(groupId, () async {
      final snapshot = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .get();
      final name = snapshot.data()?['name'];
      return name is String && name.trim().isNotEmpty ? name.trim() : null;
    });
  }

  Future<void> _loadCurrentLocation() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLocation = true;
      _currentPosition = null;
      _locationMessage = 'Obtendo localização...';
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(
            () => _locationMessage =
                'Ative a localização para priorizar os rachas próximos.',
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(
            () => _locationMessage =
                'Permita o acesso à localização para ver os rachas próximos.',
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _locationMessage =
              'Localização ativa; eventos com coordenadas aparecem primeiro.';
        });
      }
    } on Exception catch (error) {
      debugPrint('Falha ao obter localização do dispositivo: $error');
      if (mounted) {
        setState(() {
          _currentPosition = null;
          _locationMessage =
              'Não foi possível obter sua localização. Tente novamente.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  double? _distanceToEventKm(EventModel event) {
    final position = _currentPosition;
    final latitude = event.latitude;
    final longitude = event.longitude;
    if (position == null ||
        latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }

    return Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          latitude,
          longitude,
        ) /
        1000;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processInviteLink();
    });
  }

  Future<void> _processInviteLink() async {
    if (_processandoConvite || _conviteProcessado || !mounted) return;

    final uri = Uri.base;
    final eventId = uri.queryParameters['event'];
    final token = uri.queryParameters['invite'];
    if (eventId == null || token == null) return;

    _processandoConvite = true;
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final eventService = Provider.of<EventService>(context, listen: false);
      if (authService.isLoading) {
        _processandoConvite = false;
        return;
      }
      if (authService.currentUser == null) {
        final loginResult = await showDialog<bool>(
          context: context,
          builder: (context) => const LoginScreen(),
        );
        if (!mounted) return;
        if (loginResult != true) {
          _processandoConvite = false;
          return;
        }
        await authService.reloadUser();
      }

      final user = authService.currentUser;
      if (user == null) {
        throw StateError('Entre na sua conta para abrir este convite.');
      }

      await eventService.redeemPrivateEventInvite(
        eventId: eventId,
        token: token,
        userId: user.uid,
      );
      if (!mounted) return;

      _conviteProcessado = true;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              EventDetailsScreen(eventId: eventId, title: 'Evento privado'),
        ),
      );
    } catch (error) {
      if (mounted) {
        _conviteProcessado = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir o convite: $error')),
        );
      }
    } finally {
      _processandoConvite = false;
    }
  }

  Future<void> _buscarMeuGrupo() async {
    if (!mounted) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;

    if (user != null) {
      setState(() {
        _carregandoGrupo = true;
        _usuarioDosGrupos = user.uid;
      });
      try {
        final groupsById = <String, Map<String, dynamic>>{};
        final groupIds = user.groupIds.toSet();
        final groupSnapshots = await Future.wait(
          groupIds.map(
            (groupId) => FirebaseFirestore.instance
                .collection('groups')
                .doc(groupId)
                .get(),
          ),
        );
        for (final doc in groupSnapshots) {
          if (doc.exists) {
            groupsById[doc.id] = {...doc.data()!, 'id': doc.id};
          }
        }

        if (user.isStaff ||
            user.canCreateEvent ||
            user.canCreateOrganizations) {
          final ownedGroupSnapshots = await Future.wait([
            FirebaseFirestore.instance
                .collection('groups')
                .where('owner_id', isEqualTo: user.uid)
                .get(),
            FirebaseFirestore.instance
                .collection('groups')
                .where('ownerId', isEqualTo: user.uid)
                .get(),
            FirebaseFirestore.instance
                .collection('groups')
                .where('organizer_id', isEqualTo: user.uid)
                .get(),
            FirebaseFirestore.instance
                .collection('groups')
                .where('organizer_uid', isEqualTo: user.uid)
                .get(),
            FirebaseFirestore.instance
                .collection('groups')
                .where('organizerId', isEqualTo: user.uid)
                .get(),
          ]);
          for (final snapshot in ownedGroupSnapshots) {
            for (final doc in snapshot.docs) {
              groupsById[doc.id] = {...doc.data(), 'id': doc.id};
            }
          }
        }

        if (mounted) {
          final groups = groupsById.values.toList()
            ..sort(
              (a, b) => (a['name'] as String? ?? '').toLowerCase().compareTo(
                (b['name'] as String? ?? '').toLowerCase(),
              ),
            );
          setState(() {
            _meusGrupos = groups;
            _meuGrupo = _meusGrupos.isEmpty ? null : _meusGrupos.first;
            _carregandoGrupo = false;
          });
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _meusGrupos = [];
            _meuGrupo = null;
            _carregandoGrupo = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Não foi possível carregar os grupos: $error'),
            ),
          );
        }
      }
    } else if (mounted) {
      setState(() {
        _meuGrupo = null;
        _meusGrupos = [];
        _usuarioDosGrupos = null;
        _carregandoGrupo = false;
      });
    }
  }

  Future<void> _retryProfileLoad() async {
    try {
      await context.read<AuthService>().reloadUser();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível carregar o perfil: $error')),
      );
    }
  }

  void _mostrarDialogoLoginObrigatorio(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.sports_soccer, color: Colors.green),
            SizedBox(width: 8),
            Text("Acesse sua conta"),
          ],
        ),
        content: const Text(
          "Para visualizar os detalhes completos do racha, ver a lista de inscritos e pedir para jogar, você precisa estar conectado.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await showDialog<bool>(
                context: context,
                builder: (context) => const LoginScreen(),
              );
              setState(() {});
              _buscarMeuGrupo();
            },
            child: const Text("Entrar / Cadastre-se"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final currentUser = authService.currentUser;

    if (currentUser == null && authService.profileError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Não foi possível sincronizar seu perfil.'),
                const SizedBox(height: 8),
                Text(
                  '${authService.profileError}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _retryProfileLoad,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (currentUser != null &&
        _usuarioDosGrupos != currentUser.uid &&
        !_carregandoGrupo &&
        _carregamentoDeGruposAgendadoPara != currentUser.uid) {
      _carregamentoDeGruposAgendadoPara = currentUser.uid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _carregamentoDeGruposAgendadoPara = null;
        if (mounted &&
            Provider.of<AuthService>(context, listen: false).currentUser?.uid ==
                currentUser.uid &&
            _usuarioDosGrupos != currentUser.uid &&
            !_carregandoGrupo) {
          _buscarMeuGrupo();
        }
      });
    }

    final bool isLoggedIn = currentUser != null;
    final bool isOrganizer =
        isLoggedIn && (currentUser.isStaff || currentUser.canCreateEvent);
    final bool canCreateOrganizations =
        currentUser?.canCreateOrganizations == true;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 1,
            title: Row(
              children: [
                const Icon(Icons.sports_soccer, color: Colors.green, size: 28),
                const SizedBox(width: 8),
                Text(
                  'Nosso Racha',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.grey[900],
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            actions: [
              if (!isLoggedIn) ...[
                TextButton(
                  onPressed: () async {
                    await showDialog<bool>(
                      context: context,
                      builder: (context) => const LoginScreen(),
                    );
                    setState(() {});
                    _buscarMeuGrupo();
                  },
                  child: Text(
                    'Entrar',
                    style: TextStyle(
                      color: Colors.grey[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    right: 12.0,
                    top: 8,
                    bottom: 8,
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      final resultadoRegistro = await showDialog<bool>(
                        context: context,
                        builder: (context) => const RegisterScreen(),
                      );
                      if (resultadoRegistro == true) {
                        setState(() {});
                        _buscarMeuGrupo();
                      }
                    },
                    child: const Text(
                      'Cadastre-se',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ] else ...[
                InkWell(
                  onTap: () async {
                    await showDialog(
                      context: context,
                      builder: (context) => const ProfileModal(),
                    );
                    setState(() {});
                    _buscarMeuGrupo();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.green[100],
                          child: Text(
                            currentUser.name.isNotEmpty
                                ? currentUser.name[0].toUpperCase()
                                : 'U',
                            style: TextStyle(
                              color: Colors.green[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentUser.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              isOrganizer ? 'Organizador' : 'Atleta',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  tooltip: 'Sair da conta',
                  onPressed: () async {
                    final bool? confirmarSaida = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text("Sair da conta"),
                        content: const Text(
                          "Deseja realmente sair da sua conta?",
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text("Cancelar"),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text("Sair"),
                          ),
                        ],
                      ),
                    );

                    if (confirmarSaida == true && mounted) {
                      await authService.signOut();
                      setState(() {
                        _meuGrupo = null;
                        _meusGrupos = [];
                        _usuarioDosGrupos = null;
                        _carregamentoDeGruposAgendadoPara = null;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Você saiu da sua conta com sucesso."),
                          backgroundColor: Colors.grey,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- HERO SECTION ----
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 32,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green[900]!, Colors.green[700]!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'O ponto de encontro do\nfutebol amador.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Encontre rachas abertos na sua região, garanta sua vaga na linha ou lucre como goleiro remunerado.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: 'Digite seu bairro ou cidade...',
                              border: InputBorder.none,
                              icon: Icon(Icons.search, color: Colors.green),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _filtroBairro = value.toLowerCase();
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              _currentPosition == null
                                  ? Icons.location_searching
                                  : Icons.near_me,
                              color: Colors.white70,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _locationMessage,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Atualizar localização',
                              visualDensity: VisualDensity.compact,
                              onPressed: _isLoadingLocation
                                  ? null
                                  : _loadCurrentLocation,
                              icon: _isLoadingLocation
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.refresh,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ---- GESTÃO DE GRUPO PRO / ORGANIZADOR ----
                  if (isOrganizer &&
                      (canCreateOrganizations || _meusGrupos.isNotEmpty)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '⭐ Gestão de Grupo PRO',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          if (_meuGrupo == null &&
                              !_carregandoGrupo &&
                              canCreateOrganizations)
                            ElevatedButton.icon(
                              onPressed: () async {
                                final criado = await showDialog(
                                  context: context,
                                  builder: (context) =>
                                      const CreateGroupModal(),
                                );
                                if (criado == true) {
                                  _buscarMeuGrupo();
                                }
                              },
                              icon: const Icon(Icons.add_business, size: 16),
                              label: const Text(
                                'Criar Meu Grupo',
                                style: TextStyle(fontSize: 12),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple[800],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _carregandoGrupo
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : _meuGrupo != null
                        ? CardRachaCompacto(
                            nomeRacha: _meuGrupo!['name'] ?? 'Meu Grupo',
                            bairro: _meuGrupo!['neighborhood'] ?? '',
                            cidade: _meuGrupo!['city'] ?? '',
                            dataHora: 'Painel do Grupo',
                            badgeTexto: 'GRUPO ATIVO',
                            badgeCor: Colors.purple[50]!,
                            badgeTextoCor: Colors.purple[800]!,
                            botaoTexto: 'Abrir Painel / HomeScreen',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      HomeScreen(groupId: _meuGrupo!['id']),
                                ),
                              );
                            },
                          )
                        : CardRachaCompacto(
                            nomeRacha: 'Você ainda não tem um grupo',
                            bairro: 'Crie seu grupo para gerenciar rachas',
                            cidade: 'Acesse para começar',
                            dataHora: 'Área PRO',
                            badgeTexto: 'PENDENTE',
                            badgeCor: Colors.orange[50]!,
                            badgeTextoCor: Colors.orange[800]!,
                            botaoTexto: 'Criar Meu Grupo',
                            onPressed: () async {
                              final criado = await showDialog(
                                context: context,
                                builder: (context) => const CreateGroupModal(),
                              );
                              if (criado == true) {
                                _buscarMeuGrupo();
                              }
                            },
                          ),
                  ],

                  if (isLoggedIn && !isOrganizer && _meusGrupos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Minhas organizações',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._meusGrupos.map(
                            (grupo) => CardRachaCompacto(
                              nomeRacha: grupo['name'] ?? 'Minha organização',
                              bairro: grupo['neighborhood'] ?? '',
                              cidade: grupo['city'] ?? '',
                              dataHora: 'Eventos privados da organização',
                              badgeTexto: 'MEMBRO',
                              badgeCor: Colors.purple[50]!,
                              badgeTextoCor: Colors.purple[800]!,
                              botaoTexto: 'Ver eventos',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => HomeScreen(
                                    groupId: grupo['id'] as String,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ---- RACHAS & VAGAS ABERTAS (GRID RESPONSIVO) ----
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '🔥 Rachas & Vagas Abertas',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'Perto de você',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StreamBuilder<QuerySnapshot>(
                    stream: _publicEventsStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Center(
                            child: Text(
                              'Não foi possível carregar os eventos públicos.',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Center(
                            child: Text(
                              "Nenhum racha disponível no momento.",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        );
                      }

                      final rawDocs = snapshot.data!.docs;
                      final events = rawDocs.map((doc) {
                        return EventModel.fromMap(
                          doc.id,
                          doc.data() as Map<String, dynamic>,
                        );
                      }).toList();
                      events.sort(
                        (a, b) => b.startDateTime.compareTo(a.startDateTime),
                      );

                      // Filtra rachas finalizados ou ocultos por visibilidade privada
                      final activeEvents = events
                          .where(
                            (e) =>
                                e.status != 'finished' &&
                                (e.visibility == 'public' ||
                                    e.visibility == 'moderated'),
                          )
                          .toList();
                      final eventDistancesKm = <String, double>{};
                      for (final event in activeEvents) {
                        final eventId = event.id;
                        final distance = _distanceToEventKm(event);
                        if (eventId != null && distance != null) {
                          eventDistancesKm[eventId] = distance;
                        }
                      }
                      activeEvents.sort((a, b) {
                        final distanceA = a.id == null
                            ? null
                            : eventDistancesKm[a.id];
                        final distanceB = b.id == null
                            ? null
                            : eventDistancesKm[b.id];
                        if (distanceA != null && distanceB == null) return -1;
                        if (distanceA == null && distanceB != null) return 1;
                        if (distanceA != null && distanceB != null) {
                          final byDistance = distanceA.compareTo(distanceB);
                          if (byDistance != 0) return byDistance;
                        }
                        return b.startDateTime.compareTo(a.startDateTime);
                      });

                      if (activeEvents.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Center(
                            child: Text(
                              "Nenhum racha em aberto.",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        );
                      }

                      return LayoutBuilder(
                        builder: (context, constraints) {
                          int crossAxisCount = 1;
                          if (constraints.maxWidth > 900) {
                            crossAxisCount = 3;
                          } else if (constraints.maxWidth > 600) {
                            crossAxisCount = 2;
                          }

                          final filteredEvents = activeEvents.where((event) {
                            if (_filtroBairro.isNotEmpty &&
                                !event.location.toLowerCase().contains(
                                  _filtroBairro,
                                ) &&
                                !event.title.toLowerCase().contains(
                                  _filtroBairro,
                                )) {
                              return false;
                            }
                            return true;
                          }).toList();

                          if (filteredEvents.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Center(
                                child: Text(
                                  "Nenhum racha encontrado com esse termo.",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            );
                          }

                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  mainAxisExtent: 240,
                                ),
                            itemCount: filteredEvents.length,
                            itemBuilder: (context, i) {
                              final event = filteredEvents[i];

                              return FutureBuilder<String?>(
                                future: isLoggedIn && event.groupId != null
                                    ? _getGroupName(event.groupId!)
                                    : null,
                                builder: (context, groupSnapshot) {
                                  String nomeGrupo = event.groupId == null
                                      ? 'Organização Independente'
                                      : event.groupName ?? 'Organização';
                                  if (groupSnapshot.data != null) {
                                    nomeGrupo = groupSnapshot.data!;
                                  } else if (groupSnapshot.hasError) {
                                    debugPrint(
                                      'Falha ao carregar o nome do grupo '
                                      '${event.groupId}: '
                                      '${groupSnapshot.error}',
                                    );
                                  }

                                  return CardRachaCompactoGrid(
                                    event: event,
                                    nomeGrupo: nomeGrupo,
                                    isUserLoggedIn: isLoggedIn,
                                    distanceKm: event.id == null
                                        ? null
                                        : eventDistancesKm[event.id],
                                    onPressed: () {
                                      if (!isLoggedIn) {
                                        _mostrarDialogoLoginObrigatorio(
                                          context,
                                        );
                                      } else {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                EventDetailsScreen(
                                                  eventId: event.id!,
                                                  title: event.title,
                                                ),
                                          ),
                                        );
                                      }
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                ],
              );
            }, childCount: 1),
          ),
        ],
      ),
    );
  }
}

// ---- GRID CARD LIMPO E ORGANIZADO ----
class CardRachaCompactoGrid extends StatelessWidget {
  final EventModel event;
  final String nomeGrupo;
  final bool isUserLoggedIn;
  final double? distanceKm;
  final VoidCallback onPressed;

  const CardRachaCompactoGrid({
    super.key,
    required this.event,
    required this.nomeGrupo,
    required this.isUserLoggedIn,
    this.distanceKm,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
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
    final mapDestination = _eventMapDestination;
    final distanceLabel = distanceKm == null
        ? null
        : distanceKm! < 1
        ? '${(distanceKm! * 1000).round()} m'
        : '${distanceKm!.toStringAsFixed(1)} km';

    String statusPt = 'AGENDADO';
    Color statusColor = Colors.green[800]!;
    Color statusBg = Colors.green[50]!;
    if (event.status == 'published') {
      statusPt = 'ABERTO';
      statusColor = Colors.blue[800]!;
      statusBg = Colors.blue[50]!;
    } else if (event.status == 'in_progress') {
      statusPt = 'EM ANDAMENTO';
      statusColor = Colors.orange[800]!;
      statusBg = Colors.orange[50]!;
    }

    final int totalVagasLinha = event.maxLinePlayers;

    final int goleirosInscritos = event.participants
        .where((p) => p.roleInMatch == 'goalkeeper' && p.status == 'active')
        .length;
    final int goleirosExternosInscritos = event.participants
        .where(
          (p) =>
              p.roleInMatch == 'goalkeeper' &&
              p.status == 'active' &&
              p.isExternal,
        )
        .length;
    final int linhaInscritos = event.participants
        .where((p) => p.roleInMatch == 'line' && p.status == 'active')
        .length;

    final int vagasExternasRestantes =
        (event.externalGoalkeeperSlots - goleirosExternosInscritos).clamp(
          0,
          event.externalGoalkeeperSlots,
        );
    final int vagasTotaisGoleiroRestantes =
        (event.maxGoalkeepers - goleirosInscritos).clamp(
          0,
          event.maxGoalkeepers,
        );
    final int vagasGoleiroRestantes =
        vagasExternasRestantes < vagasTotaisGoleiroRestantes
        ? vagasExternasRestantes
        : vagasTotaisGoleiroRestantes;
    final int vagasLinhaRestantes = (totalVagasLinha - linhaInscritos).clamp(
      0,
      totalVagasLinha,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusPt,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 13,
                    color: Colors.purple,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      nomeGrupo,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.purple[800],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: mapDestination == null
                          ? null
                          : () => _openEventDirections(context, mapDestination),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 14,
                              color: mapDestination == null
                                  ? Colors.grey[600]
                                  : Colors.green[800],
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                event.location,
                                style: TextStyle(
                                  color: mapDestination == null
                                      ? Colors.grey[700]
                                      : Colors.green[800],
                                  fontSize: 12,
                                  decoration: mapDestination == null
                                      ? null
                                      : TextDecoration.underline,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (mapDestination != null) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.directions_outlined,
                                size: 14,
                                color: Colors.green[800],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (distanceLabel != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.near_me_outlined,
                      size: 13,
                      color: Colors.green[700],
                    ),
                    const SizedBox(width: 3),
                    Text(
                      distanceLabel,
                      style: TextStyle(
                        color: Colors.green[800],
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              if (event.locationNote?.isNotEmpty == true) ...[
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Text(
                    event.locationNote!,
                    style: TextStyle(color: Colors.grey[700], fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$weekday, $formattedDate',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'R\$ ${event.price.toStringAsFixed(2).replaceAll('.', ',')}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(
                    'Início $startTime • Fim $endTime',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _BadgeInfo(
                    texto: '$vagasLinhaRestantes linha',
                    cor: Colors.blue[50]!,
                    textoCor: Colors.blue[800]!,
                  ),
                  if (event.sportHasGoalkeeper) ...[
                    const SizedBox(width: 6),
                    _BadgeInfo(
                      texto: '$vagasGoleiroRestantes goleiro(s)',
                      cor: Colors.orange[50]!,
                      textoCor: Colors.orange[800]!,
                    ),
                  ],
                ],
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800],
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: onPressed,
                child: Text(
                  isUserLoggedIn ? 'Ver Detalhes' : 'Entrar',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? get _eventMapDestination {
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

  Future<void> _openEventDirections(
    BuildContext context,
    String destination,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination,
    });

    try {
      final opened = kIsWeb
          ? await launchUrl(uri, webOnlyWindowName: '_blank')
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o Google Maps.'),
          ),
        );
      }
    } on PlatformException {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o Google Maps.'),
          ),
        );
      }
    }
  }
}

// ---- CARD COMPACTO AUXILIAR PARA O PAINEL PRO ----
class CardRachaCompacto extends StatelessWidget {
  final String nomeRacha;
  final String bairro;
  final String cidade;
  final String dataHora;
  final String? badgeTexto;
  final Color? badgeCor;
  final Color? badgeTextoCor;
  final String botaoTexto;
  final VoidCallback onPressed;

  const CardRachaCompacto({
    super.key,
    required this.nomeRacha,
    required this.bairro,
    required this.cidade,
    required this.dataHora,
    this.badgeTexto,
    this.badgeCor,
    this.badgeTextoCor,
    this.botaoTexto = 'Acessar',
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.06),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  nomeRacha,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (badgeTexto != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeCor ?? Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeTexto!,
                    style: TextStyle(
                      color: badgeTextoCor ?? Colors.blue[800],
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 14,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 3),
              Text(
                '$bairro, $cidade',
                style: TextStyle(color: Colors.grey[700], fontSize: 12),
              ),
              const SizedBox(width: 12),
              Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 3),
              Text(
                dataHora,
                style: TextStyle(color: Colors.grey[700], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: 30,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[800],
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: onPressed,
                  child: Text(
                    botaoTexto,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BadgeInfo extends StatelessWidget {
  final String texto;
  final Color cor;
  final Color textoCor;

  const _BadgeInfo({
    required this.texto,
    required this.cor,
    required this.textoCor,
  });

  @override
  Widget build(BuildContext context) {
    const double fontSize = 10;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: textoCor,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
