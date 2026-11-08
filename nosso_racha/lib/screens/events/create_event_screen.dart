import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/event_model.dart';
import '../../models/sport_config.dart';
import '../../services/event_service.dart';
import '../../services/auth_service.dart';
import '../../models/venue_model.dart';
import '../../widgets/venue_location_field.dart';

class CreateEventScreen extends StatefulWidget {
  final EventModel? eventToEdit; // Parâmetro opcional para edição
  final String? groupId;

  const CreateEventScreen({super.key, this.eventToEdit, this.groupId});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores
  final _titleController = TextEditingController(text: "Racha LCS");
  final _locationController = TextEditingController();
  final _locationNoteController = TextEditingController();
  final _priceController = TextEditingController(text: "15.00");
  final _goalkeeperAidController = TextEditingController(text: '0.00');
  double? _latitude;
  double? _longitude;
  String? _street;
  String? _addressNumber;
  String? _addressComplement;
  String? _neighborhood;
  String? _city;
  String? _state;
  String? _postcode;
  String? _country;

  // Datas e Horários
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 21, minute: 0);

  // Agendamento da Votação
  DateTime _votingOpenDate = DateTime.now();
  TimeOfDay _votingOpenTime = const TimeOfDay(hour: 21, minute: 0);
  bool _scheduleVoting = false;

  // Configuração dos Times
  int _numberOfTeams = 5;
  int _linePlayersPerTeam = 6;
  String _sport = 'football';
  int _externalGoalkeeperSlots = 0;

  // --- NOVAS OPÇÕES DE ACESSO / VISIBILIDADE INTELIGENTE ---
  String _visibility = 'public'; // 'public', 'moderated', 'private'
  bool _allowLinePlayers = true;
  bool _allowGoalkeepers = true;

  String? _userGroupId;
  Map<String, String> _availableGroups = {};
  String? _groupLoadError;
  bool _isLoadingGroup = true;

  final _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    if (widget.eventToEdit != null) {
      _loadEventData(widget.eventToEdit!);
    }
    _userGroupId = widget.groupId ?? widget.eventToEdit?.groupId;
    _fetchOrganizerGroups();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _locationNoteController.dispose();
    _priceController.dispose();
    _goalkeeperAidController.dispose();
    super.dispose();
  }

  Future<void> _editAddressDetails() async {
    final controllers = <String, TextEditingController>{
      'street': TextEditingController(text: _street ?? ''),
      'number': TextEditingController(text: _addressNumber ?? ''),
      'complement': TextEditingController(text: _addressComplement ?? ''),
      'neighborhood': TextEditingController(text: _neighborhood ?? ''),
      'city': TextEditingController(text: _city ?? ''),
      'state': TextEditingController(text: _state ?? ''),
      'postcode': TextEditingController(text: _postcode ?? ''),
      'country': TextEditingController(text: _country ?? ''),
    };

    Map<String, String?>? address;
    try {
      address = await showDialog<Map<String, String?>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Endereço do local'),
          content: SizedBox(
            width: MediaQuery.sizeOf(context).width < 520
                ? MediaQuery.sizeOf(context).width - 80
                : 440,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _addressInput(controllers['street']!, 'Rua / avenida'),
                    _addressInput(controllers['number']!, 'Número'),
                    _addressInput(controllers['complement']!, 'Complemento'),
                    _addressInput(controllers['neighborhood']!, 'Bairro'),
                    _addressInput(controllers['city']!, 'Cidade'),
                    _addressInput(controllers['state']!, 'Estado'),
                    _addressInput(controllers['postcode']!, 'CEP'),
                    _addressInput(controllers['country']!, 'País'),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                for (final entry in controllers.entries)
                  entry.key: entry.value.text.trim().isEmpty
                      ? null
                      : entry.value.text.trim(),
              }),
              child: const Text('Salvar endereço'),
            ),
          ],
        ),
      );
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }

    final savedAddress = address;
    if (savedAddress == null || !mounted) return;
    setState(() {
      _street = savedAddress['street'];
      _addressNumber = savedAddress['number'];
      _addressComplement = savedAddress['complement'];
      _neighborhood = savedAddress['neighborhood'];
      _city = savedAddress['city'];
      _state = savedAddress['state'];
      _postcode = savedAddress['postcode'];
      _country = savedAddress['country'];
    });
  }

  Widget _addressInput(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        textCapitalization: TextCapitalization.words,
      ),
    );
  }

  Future<void> _fetchOrganizerGroups() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;
      if (user == null) {
        throw StateError('Usuário não autenticado.');
      }

      final firestore = FirebaseFirestore.instance;
      final groupIds = user.groupIds.toSet();
      if (_userGroupId != null) groupIds.add(_userGroupId!);

      final ownedGroups = await Future.wait([
        firestore
            .collection('groups')
            .where('owner_id', isEqualTo: user.uid)
            .get(),
        firestore
            .collection('groups')
            .where('ownerId', isEqualTo: user.uid)
            .get(),
        firestore
            .collection('groups')
            .where('organizer_id', isEqualTo: user.uid)
            .get(),
        firestore
            .collection('groups')
            .where('organizer_uid', isEqualTo: user.uid)
            .get(),
        firestore
            .collection('groups')
            .where('organizerId', isEqualTo: user.uid)
            .get(),
      ]);
      final ownedGroupDocs = ownedGroups
          .expand((snapshot) => snapshot.docs)
          .toList();
      groupIds.addAll(ownedGroupDocs.map((doc) => doc.id));

      final groups = <String, String>{};
      for (final groupId in groupIds) {
        final matchingGroups = ownedGroupDocs.where((doc) => doc.id == groupId);
        final groupDoc = matchingGroups.isEmpty ? null : matchingGroups.first;
        final snapshot =
            groupDoc ?? await firestore.collection('groups').doc(groupId).get();
        if (snapshot.exists) {
          groups[groupId] =
              snapshot.data()?['name'] as String? ?? 'Organização';
        }
      }

      if (mounted) {
        setState(() {
          _availableGroups = groups;
          if (_userGroupId == null && groups.length == 1) {
            _userGroupId = groups.keys.single;
          }
          if (_userGroupId != null && !groups.containsKey(_userGroupId)) {
            _userGroupId = null;
          }
          _isLoadingGroup = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _groupLoadError = e.toString();
          _isLoadingGroup = false;
        });
      }
    }
  }

  void _loadEventData(EventModel e) {
    _titleController.text = e.title;
    _locationController.text = e.location;
    _locationNoteController.text = e.locationNote ?? '';
    _priceController.text = e.price.toStringAsFixed(2);

    _selectedDate = e.startDateTime;
    _startTime = TimeOfDay.fromDateTime(e.startDateTime);
    _endTime = TimeOfDay.fromDateTime(e.endDateTime);

    _numberOfTeams = e.numberOfTeams;
    _linePlayersPerTeam = e.linePlayersPerTeam;
    _sport = SportConfig.fromId(e.sport).id;
    _externalGoalkeeperSlots = e.externalGoalkeeperSlots;
    _goalkeeperAidController.text = e.goalkeeperAid.toStringAsFixed(2);
    _latitude = e.latitude;
    _longitude = e.longitude;
    _street = e.street;
    _addressNumber = e.addressNumber;
    _addressComplement = e.addressComplement;
    _neighborhood = e.neighborhood;
    _city = e.city;
    _state = e.state;
    _postcode = e.postcode;
    _country = e.country;

    // Carrega os valores salvos do evento ao editar
    _visibility = e.visibility;
    _allowLinePlayers = e.allowLinePlayers;
    _allowGoalkeepers =
        SportConfig.fromId(_sport).hasGoalkeeper && e.allowGoalkeepers;

    _scheduleVoting = true;
    _votingOpenDate = e.votingOpensAt;
    _votingOpenTime = TimeOfDay.fromDateTime(e.votingOpensAt);
  }

  void _applyVenue(Venue venue) {
    setState(() {
      _locationController.text = venue.name;
      _latitude = venue.latitude;
      _longitude = venue.longitude;
      _street = venue.street ?? venue.address;
      _addressNumber = venue.number;
      _addressComplement = venue.complement;
      _neighborhood = venue.neighborhood;
      _city = venue.city;
      _state = venue.state;
      _postcode = venue.postcode;
      _country = venue.country;
    });
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _selectTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null)
      setState(() => isStart ? _startTime = picked : _endTime = picked);
  }

  Future<void> _selectVotingOpenTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _votingOpenDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: _selectedDate,
    );
    if (date != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: _votingOpenTime,
      );
      if (time != null) {
        setState(() {
          _votingOpenDate = date;
          _votingOpenTime = time;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final eventService = Provider.of<EventService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    if (user == null) return;
    if (_userGroupId == null || !_availableGroups.containsKey(_userGroupId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione uma organização para criar o evento.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final startDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _startTime.hour,
      _startTime.minute,
    );
    final endDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _endTime.hour,
      _endTime.minute,
    );
    final adjustedEndDateTime = endDateTime.isAfter(startDateTime)
        ? endDateTime
        : endDateTime.add(const Duration(days: 1));
    final deadline = startDateTime.subtract(const Duration(hours: 4));

    DateTime votingOpensAt;
    if (_scheduleVoting) {
      votingOpensAt = DateTime(
        _votingOpenDate.year,
        _votingOpenDate.month,
        _votingOpenDate.day,
        _votingOpenTime.hour,
        _votingOpenTime.minute,
      );
    } else {
      votingOpensAt = DateTime.now().subtract(const Duration(minutes: 1));
    }

    final eventData = EventModel(
      id: widget.eventToEdit?.id,
      title: _titleController.text,
      location: _locationController.text,
      locationNote: _locationNoteController.text.trim().isEmpty
          ? null
          : _locationNoteController.text.trim(),
      price: double.parse(_priceController.text.replaceAll(',', '.')),
      startDateTime: startDateTime,
      endDateTime: adjustedEndDateTime,
      cancellationDeadline: deadline,
      votingOpensAt: votingOpensAt,
      numberOfTeams: _numberOfTeams,
      linePlayersPerTeam: _linePlayersPerTeam,
      sport: _sport,
      externalGoalkeeperSlots: _externalGoalkeeperSlots,
      goalkeeperAid: double.parse(
        _goalkeeperAidController.text.replaceAll(',', '.'),
      ),
      status: widget.eventToEdit?.status ?? 'scheduled',
      createdBy: widget.eventToEdit?.createdBy ?? user.uid,
      groupId: _userGroupId,
      latitude: _latitude,
      longitude: _longitude,
      street: _street,
      addressNumber: _addressNumber,
      addressComplement: _addressComplement,
      neighborhood: _neighborhood,
      city: _city,
      state: _state,
      postcode: _postcode,
      country: _country,
      visibility: _visibility, // Passando a visibilidade selecionada
      allowLinePlayers: _allowLinePlayers, // Passando o switch de linha
      allowGoalkeepers:
          SportConfig.fromId(_sport).hasGoalkeeper &&
          _allowGoalkeepers, // Passando o switch de goleiro
    );

    try {
      if (widget.eventToEdit != null) {
        // MODO EDIÇÃO
        await eventService.updateEvent(eventData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Evento atualizado!"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        // MODO CRIAÇÃO
        await eventService.createEvent(eventData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Evento criado e vinculado ao seu grupo!"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      }
    } on FirebaseException catch (error) {
      if (!mounted) return;
      final message = error.code == 'permission-denied'
          ? 'O Firestore recusou a gravação. Confirme se sua conta tem '
                'permissão de organizador nesta organização e se o limite '
                'de eventos abertos do plano não foi atingido. '
                '(${error.code})'
          : 'Erro no Firestore (${error.code}): ${error.message ?? error}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar evento: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteEvent() async {
    bool hasPaidAthletes = widget.eventToEdit!.participants.any(
      (p) => p.paymentStatus == 'paid',
    );

    if (hasPaidAthletes) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Exclusão Bloqueada"),
          content: const Text(
            "Existem atletas com pagamento CONFIRMADO neste racha.\n\nPara excluir o evento, você deve primeiro estornar os pagamentos na lista de presença para garantir a integridade do caixa.",
            style: TextStyle(color: Colors.red),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("ENTENDI"),
            ),
          ],
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cancelar Racha?"),
        content: const Text(
          "Tem certeza que deseja excluir este evento? Isso apagará a lista de inscritos e não pode ser desfeito.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("NÃO"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("SIM, EXCLUIR"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final eventService = Provider.of<EventService>(context, listen: false);
      try {
        await eventService.deleteEvent(widget.eventToEdit!.id!);
        if (mounted) {
          Navigator.pop(context);
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Evento excluído."),
              backgroundColor: Colors.grey,
            ),
          );
        }
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Erro ao excluir: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalGoleiros = _numberOfTeams;
    final totalLinha = _numberOfTeams * _linePlayersPerTeam;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = widget.eventToEdit != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? "Editar Racha" : "Novo Jogo"),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(LucideIcons.trash2),
              tooltip: "Excluir Evento",
              onPressed: _deleteEvent,
            ),
        ],
      ),
      body: _isLoadingGroup
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_groupLoadError != null)
                        Card(
                          color: Colors.red[50],
                          child: ListTile(
                            leading: const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                            ),
                            title: const Text(
                              'Não foi possível carregar as organizações.',
                            ),
                            subtitle: Text(_groupLoadError!),
                            trailing: IconButton(
                              tooltip: 'Tentar novamente',
                              icon: const Icon(Icons.refresh),
                              onPressed: () {
                                setState(() {
                                  _isLoadingGroup = true;
                                  _groupLoadError = null;
                                });
                                _fetchOrganizerGroups();
                              },
                            ),
                          ),
                        ),

                      // O vínculo é obrigatório para todos os eventos.
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.purple[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.purple[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _userGroupId == null
                                  ? Icons.warning_amber
                                  : LucideIcons.info,
                              size: 18,
                              color: _userGroupId == null
                                  ? Colors.orange[800]
                                  : Colors.purple[800],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _availableGroups.isEmpty
                                  ? Text(
                                      'Eventos precisam pertencer a uma organização. Crie uma ou peça acesso a uma existente antes de continuar.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange[900],
                                      ),
                                    )
                                  : DropdownButtonFormField<String>(
                                      value: _userGroupId,
                                      decoration: const InputDecoration(
                                        labelText: 'Organização do evento',
                                        isDense: true,
                                        border: InputBorder.none,
                                      ),
                                      items: _availableGroups.entries
                                          .map(
                                            (group) => DropdownMenuItem(
                                              value: group.key,
                                              child: Text(group.value),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: isEditing
                                          ? null
                                          : (groupId) => setState(
                                              () => _userGroupId = groupId,
                                            ),
                                      validator: (value) => value == null
                                          ? 'Selecione uma organização'
                                          : null,
                                    ),
                            ),
                          ],
                        ),
                      ),

                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: "Nome do Evento",
                          prefixIcon: Icon(LucideIcons.type),
                        ),
                        validator: (v) => v!.isEmpty ? "Obrigatório" : null,
                      ),
                      const SizedBox(height: 16),
                      VenueLocationField(
                        controller: _locationController,
                        onVenueSelected: _applyVenue,
                        validator: (value) => value == null || value.isEmpty
                            ? 'Selecione um local'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _locationNoteController,
                        maxLength: 200,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Observação do local',
                          hintText: 'Ex.: Quadra A, campo dos fundos',
                          prefixIcon: Icon(Icons.speaker_notes_outlined),
                          alignLabelWithHint: true,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _editAddressDetails,
                          icon: const Icon(Icons.edit_location_alt_outlined),
                          label: const Text('Completar endereço manualmente'),
                        ),
                      ),
                      if ([
                        _street,
                        _addressNumber,
                        _addressComplement,
                        _neighborhood,
                        _city,
                        _state,
                        _postcode,
                        _country,
                      ].any((value) => value != null && value.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(left: 12, bottom: 8),
                          child: Text(
                            [
                              if (_street != null) _street,
                              if (_addressNumber != null) _addressNumber,
                              if (_addressComplement != null)
                                _addressComplement,
                              if (_neighborhood != null) _neighborhood,
                              if (_city != null) _city,
                              if (_state != null) _state,
                              if (_postcode != null) _postcode,
                              if (_country != null) _country,
                            ].join(', '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (_latitude != null && _longitude != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Coordenadas: ${_latitude!.toStringAsFixed(5)}, '
                            '${_longitude!.toStringAsFixed(5)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),

                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _sport,
                        decoration: const InputDecoration(
                          labelText: 'Modalidade',
                          prefixIcon: Icon(Icons.sports),
                        ),
                        items: SportConfig.all
                            .map(
                              (sport) => DropdownMenuItem(
                                value: sport.id,
                                child: Text(sport.label),
                              ),
                            )
                            .toList(),
                        onChanged: isEditing
                            ? null
                            : (sportId) {
                                if (sportId == null) return;
                                final sport = SportConfig.fromId(sportId);
                                setState(() {
                                  _sport = sport.id;
                                  _linePlayersPerTeam =
                                      sport.defaultLinePlayersPerTeam;
                                  if (!sport.hasGoalkeeper) {
                                    _allowGoalkeepers = false;
                                    _externalGoalkeeperSlots = 0;
                                    _goalkeeperAidController.text = '0.00';
                                  } else {
                                    _allowGoalkeepers = true;
                                  }
                                });
                              },
                      ),

                      const SizedBox(height: 24),
                      const Text(
                        "Data e Horário do Jogo",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _selectDate,
                              icon: const Icon(LucideIcons.calendar),
                              label: Text(_dateFormat.format(_selectedDate)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _selectTime(true),
                              icon: const Icon(LucideIcons.clock),
                              label: Text(
                                "Início: ${_startTime.format(context)}",
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _selectTime(false),
                              icon: const Icon(LucideIcons.clock),
                              label: Text("Fim: ${_endTime.format(context)}"),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // --- PERMISSÕES E VISIBILIDADE INTELIGENTE ---
                      const Text(
                        "Visibilidade e Regras do Racha",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        elevation: 0,
                        color: Theme.of(context).cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isDark
                                ? Colors.white24
                                : Colors.grey.withOpacity(0.2),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Onde o evento será exibido?",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              DropdownButtonFormField<String>(
                                value: _visibility,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'public',
                                    child: Text(
                                      "🌐 Público (Aparece na Home p/ todos)",
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'moderated',
                                    child: Text(
                                      "🛡️ Moderado (Filtra vagas específicas)",
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'private',
                                    child: Text(
                                      "🔒 Privado (Oculto na Home, só p/ membros)",
                                    ),
                                  ),
                                ],
                                onChanged: (val) =>
                                    setState(() => _visibility = val!),
                              ),
                              const Divider(),
                              SwitchListTile(
                                title: const Text(
                                  "Habilitar Vagas de Linha",
                                  style: TextStyle(fontSize: 14),
                                ),
                                subtitle: const Text(
                                  "Permite que atletas de linha solicitem vaga",
                                  style: TextStyle(fontSize: 11),
                                ),
                                value: _allowLinePlayers,
                                onChanged: (val) =>
                                    setState(() => _allowLinePlayers = val),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              if (SportConfig.fromId(_sport).hasGoalkeeper)
                                SwitchListTile(
                                  title: const Text(
                                    "Habilitar Vagas de Goleiro",
                                    style: TextStyle(fontSize: 14),
                                  ),
                                  subtitle: const Text(
                                    "Permite que goleiros solicitem vaga",
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  value: _allowGoalkeepers,
                                  onChanged: (val) => setState(() {
                                    _allowGoalkeepers = val;
                                    if (!val) {
                                      _externalGoalkeeperSlots = 0;
                                      _goalkeeperAidController.text = '0.00';
                                    }
                                  }),
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              if (SportConfig.fromId(_sport).hasGoalkeeper &&
                                  _allowGoalkeepers) ...[
                                DropdownButtonFormField<int>(
                                  value: _externalGoalkeeperSlots,
                                  decoration: const InputDecoration(
                                    labelText: 'Vagas externas para goleiros',
                                    isDense: true,
                                  ),
                                  items: List.generate(
                                    _numberOfTeams + 1,
                                    (count) => DropdownMenuItem(
                                      value: count,
                                      child: Text('$count vaga(s) externa(s)'),
                                    ),
                                  ),
                                  onChanged: (count) => setState(() {
                                    _externalGoalkeeperSlots = count ?? 0;
                                    if (_externalGoalkeeperSlots == 0) {
                                      _goalkeeperAidController.text = '0.00';
                                    }
                                  }),
                                ),
                                if (_externalGoalkeeperSlots > 0) ...[
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _goalkeeperAidController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Ajuda de custo por goleiro (R\$)',
                                      prefixIcon: Icon(LucideIcons.banknote),
                                    ),
                                    validator: (value) {
                                      final amount = double.tryParse(
                                        (value ?? '').replaceAll(',', '.'),
                                      );
                                      if (amount == null || amount < 0) {
                                        return 'Informe um valor válido';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ],
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.verified_user_outlined,
                                      size: 14,
                                      color: Colors.green,
                                    ),
                                    SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        "ℹ️ Membros do grupo entram instantaneamente. Atletas de fora exigem aprovação do organizador.",
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // --- AGENDAMENTO ---
                      Card(
                        color: Theme.of(context).cardColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Colors.orange.withOpacity(0.5),
                          ),
                        ),
                        child: SwitchListTile(
                          title: const Text(
                            "Agendar Abertura da Lista?",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            _scheduleVoting
                                ? "Abre em: ${_dateFormat.format(_votingOpenDate)} às ${_votingOpenTime.format(context)}"
                                : "A lista abre imediatamente após criar.",
                          ),
                          value: _scheduleVoting,
                          activeThumbColor: Colors.orange,
                          secondary: const Icon(
                            LucideIcons.timer,
                            color: Colors.orange,
                          ),
                          onChanged: (val) =>
                              setState(() => _scheduleVoting = val),
                        ),
                      ),
                      if (_scheduleVoting)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: OutlinedButton.icon(
                            onPressed: _selectVotingOpenTime,
                            icon: const Icon(LucideIcons.clock, size: 16),
                            label: const Text("Definir Data/Hora da Abertura"),
                          ),
                        ),

                      const SizedBox(height: 24),
                      const Text(
                        "Estrutura dos Times",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),

                      // --- ESTRUTURA DE TIMES ---
                      Card(
                        elevation: 0,
                        color: Theme.of(context).cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isDark
                                ? Colors.white24
                                : Colors.grey.withOpacity(0.2),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Flexible(child: Text("Qtd. Times")),
                                  DropdownButton<int>(
                                    value: _numberOfTeams,
                                    items: [2, 3, 4, 5, 6, 7, 8]
                                        .map(
                                          (e) => DropdownMenuItem(
                                            value: e,
                                            child: Text("$e Times"),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setState(() {
                                      _numberOfTeams = v!;
                                      if (_externalGoalkeeperSlots >
                                          _numberOfTeams) {
                                        _externalGoalkeeperSlots =
                                            _numberOfTeams;
                                      }
                                    }),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Flexible(
                                    child: Text("Jogadores Linha (por time)"),
                                  ),
                                  DropdownButton<int>(
                                    value: _linePlayersPerTeam,
                                    items: SportConfig.linePlayersPerTeamOptions
                                        .map(
                                          (e) => DropdownMenuItem(
                                            value: e,
                                            child: Text("$e Jogadores"),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setState(
                                      () => _linePlayersPerTeam = v!,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    if (SportConfig.fromId(
                                      _sport,
                                    ).hasGoalkeeper) ...[
                                      Column(
                                        children: [
                                          const Text(
                                            "Goleiros",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(
                                                LucideIcons.shield,
                                                size: 18,
                                                color: Colors.purple,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                "$totalGoleiros",
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.purple,
                                                  fontSize: 18,
                                                ),
                                              ),
                                              const Text(
                                                " vagas",
                                                style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      Container(
                                        width: 1,
                                        height: 30,
                                        color: Colors.grey[300],
                                      ),
                                    ],
                                    Column(
                                      children: [
                                        const Text(
                                          "Jogadores de Linha",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(
                                              LucideIcons.users,
                                              size: 18,
                                              color: Colors.green,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              "$totalLinha",
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green,
                                                fontSize: 18,
                                              ),
                                            ),
                                            const Text(
                                              " vagas",
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: "Valor (R\$)",
                          prefixIcon: Icon(LucideIcons.banknote),
                        ),
                        validator: (v) {
                          final amount = double.tryParse(
                            (v ?? '').replaceAll(',', '.'),
                          );
                          return amount == null || amount < 0
                              ? 'Informe um valor válido'
                              : null;
                        },
                      ),

                      const SizedBox(height: 32),

                      Consumer<EventService>(
                        builder: (context, service, _) {
                          return ElevatedButton(
                            onPressed:
                                service.isLoading ||
                                    _userGroupId == null ||
                                    _availableGroups.isEmpty
                                ? null
                                : _submit,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(16),
                            ),
                            child: service.isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : Text(
                                    isEditing
                                        ? "SALVAR ALTERAÇÕES"
                                        : "CRIAR EVENTO",
                                  ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
