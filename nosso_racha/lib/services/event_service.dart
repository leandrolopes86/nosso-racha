import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../models/event_model.dart';
import '../models/plan_limits.dart';
import '../models/participant_model.dart';
import '../models/sport_config.dart';
import '../models/user_model.dart';

class EventService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  Future<String?> _getGroupName(String? groupId) async {
    if (groupId == null || groupId.trim().isEmpty) return null;

    final snapshot = await _firestore.collection('groups').doc(groupId).get();
    final name = snapshot.data()?['name'];
    return name is String && name.trim().isNotEmpty ? name.trim() : null;
  }

  // --- LEITURA DE DADOS ---
  Stream<QuerySnapshot> getEventsStream({String? groupId}) {
    Query query = _firestore.collection('events');

    if (groupId != null) {
      query = query.where(
        Filter.or(
          Filter('info.group_id', isEqualTo: groupId),
          Filter('group_id', isEqualTo: groupId),
        ),
      );
    } else {
      query = query.where(
        'info.visibility',
        whereIn: const ['public', 'moderated'],
      ).where(
        'info.status',
        whereIn: const ['published', 'in_progress', 'finished'],
      );
    }

    return query.snapshots();
  }

  Stream<DocumentSnapshot> getEventDetailStream(String eventId) {
    return _firestore.collection('events').doc(eventId).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> getGoaliePaymentStream(
    String eventId,
    String goalkeeperUid,
  ) {
    return _firestore
        .collection('events')
        .doc(eventId)
        .collection('goalie_payments')
        .doc(goalkeeperUid)
        .snapshots();
  }

  Future<void> syncGoaliePixKey(String eventId, UserModel goalkeeper) async {
    final pixKey = goalkeeper.pixKey.trim();
    if (pixKey.isEmpty) return;

    final paymentRef = _firestore
        .collection('events')
        .doc(eventId)
        .collection('goalie_payments')
        .doc(goalkeeper.uid);
    final paymentSnapshot = await paymentRef.get();
    final paymentData = paymentSnapshot.data();
    if (paymentData?['goalie_payment_status'] != null &&
        paymentData?['goalie_payment_status'] != 'none') {
      return;
    }

    if (!paymentSnapshot.exists) {
      await paymentRef.set({
        'uid': goalkeeper.uid,
        'pix_key': pixKey,
        'goalie_payment_status': 'none',
      });
    } else if (paymentData?['pix_key'] != pixKey) {
      await paymentRef.update({'pix_key': pixKey});
    }
  }

  Future<Uri> createPrivateEventInvite(String eventId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      throw StateError('É necessário entrar para criar um convite.');
    }

    final random = Random.secure();
    final token = List<int>.generate(
      32,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final expiresAt = DateTime.now().add(const Duration(days: 7));

    await _firestore
        .collection('events')
        .doc(eventId)
        .collection('invites')
        .doc(token)
        .set({
          'created_by': userId,
          'active': true,
          'expires_at': Timestamp.fromDate(expiresAt),
        });

    final currentUri = Uri.base;
    final baseUri =
        currentUri.hasAuthority &&
            (currentUri.scheme == 'https' || currentUri.scheme == 'http')
        ? currentUri
        : Uri.https('${Firebase.app().options.projectId}.web.app', '/');

    return baseUri.replace(
      queryParameters: {'event': eventId, 'invite': token},
    );
  }

  Future<void> redeemPrivateEventInvite({
    required String eventId,
    required String token,
    required String userId,
  }) async {
    final eventRef = _firestore.collection('events').doc(eventId);
    final inviteRef = eventRef.collection('invites').doc(token);
    final accessRef = eventRef.collection('access').doc(userId);

    await _firestore.runTransaction((transaction) async {
      final accessSnapshot = await transaction.get(accessRef);
      if (accessSnapshot.exists) return;

      final inviteSnapshot = await transaction.get(inviteRef);
      final inviteData = inviteSnapshot.data();
      final expiresAt = inviteData?['expires_at'] as Timestamp?;
      if (!inviteSnapshot.exists ||
          inviteData?['active'] != true ||
          expiresAt == null ||
          !expiresAt.toDate().isAfter(DateTime.now())) {
        throw StateError('Este convite não existe ou expirou.');
      }

      transaction.set(accessRef, {
        'invite_token': token,
        'granted_at': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<int> getFinishedEventsCountStream() {
    return _firestore
        .collection('events')
        .where('info.status', isEqualTo: 'finished')
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  // --- CRIAÇÃO, EDIÇÃO E EXCLUSÃO ---
  Future<void> createEvent(EventModel event) async {
    try {
      _validateEventConfiguration(event);
      _isLoading = true;
      notifyListeners();

      final eventMap = event.toMap();
      final info = eventMap['info'] as Map<String, dynamic>;
      info['group_name'] =
          await _getGroupName(event.groupId) ?? event.groupName;
      final eventRef = _firestore.collection('events').doc();
      await _runTransactionPreservingCallbackErrors((transaction) async {
        if (_isOpenEventStatus(event.status)) {
          await _writeOpenEventCountDelta(
            transaction,
            groupId: event.groupId!,
            eventId: eventRef.id,
            delta: 1,
          );
        }
        transaction.set(eventRef, eventMap);
      });
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateEvent(EventModel event) async {
    try {
      _validateEventConfiguration(event);
      _isLoading = true;
      notifyListeners();
      final docRef = _firestore.collection('events').doc(event.id);

      final snapshot = await docRef.get();
      if (snapshot.exists) {
        final data = snapshot.data();
        final double? oldPrice = (data?['info']?['price'] as num?)?.toDouble();

        if (oldPrice != null && oldPrice != event.price) {
          final List<dynamic> participantsList = data?['participants'] ?? [];
          final Set<String> paidUserIds = {};

          for (var p in participantsList) {
            if (p['payment_status'] == 'paid') {
              paidUserIds.add(p['uid']);
            }
          }

          final pendingColl = docRef.collection('pending_payments');
          final pendingSnapshot = await pendingColl.get();

          if (pendingSnapshot.docs.isNotEmpty) {
            WriteBatch batch = _firestore.batch();
            for (var doc in pendingSnapshot.docs) {
              if (!paidUserIds.contains(doc.id)) {
                batch.delete(doc.reference);
              }
            }
            await batch.commit();
          }
        }
      }

      final groupName = await _getGroupName(event.groupId) ?? event.groupName;
      final updates = {
        'info': {
          'title': event.title,
          'location': event.location,
          'location_note': event.locationNote,
          'price': event.price,
          'number_of_teams': event.numberOfTeams,
          'line_players_per_team': event.linePlayersPerTeam,
          'sport': event.sport,
          'external_goalkeeper_slots': event.externalGoalkeeperSlots,
          'goalkeeper_aid': event.goalkeeperAid,
          'start_date_time': Timestamp.fromDate(event.startDateTime),
          'end_date_time': Timestamp.fromDate(event.endDateTime),
          'cancellation_deadline': Timestamp.fromDate(
            event.cancellationDeadline,
          ),
          'voting_opens_at': Timestamp.fromDate(event.votingOpensAt),
          'status': event.status,
          'group_id': event.groupId, // Garante a manutenção do grupo
          'group_name': groupName,
          'latitude': event.latitude,
          'longitude': event.longitude,
          'street': event.street,
          'address_number': event.addressNumber,
          'address_complement': event.addressComplement,
          'neighborhood': event.neighborhood,
          'city': event.city,
          'state': event.state,
          'postcode': event.postcode,
          'country': event.country,
          'visibility': event.visibility, // ADICIONADO: Salva a visibilidade
          'allow_line_players':
              event.allowLinePlayers, // ADICIONADO: Salva a regra de linha
          'allow_goalkeepers':
              event.allowGoalkeepers, // ADICIONADO: Salva a regra de goleiro
        },
      };
      await _runTransactionPreservingCallbackErrors((transaction) async {
        final currentSnapshot = await transaction.get(docRef);
        final currentData = currentSnapshot.data();
        if (currentData == null) {
          throw StateError('Evento não encontrado.');
        }
        final oldStatus = currentData['info']?['status'] as String? ?? '';
        final wasOpen = _isOpenEventStatus(oldStatus);
        final willBeOpen = _isOpenEventStatus(event.status);
        if (wasOpen != willBeOpen) {
          await _writeOpenEventCountDelta(
            transaction,
            groupId: event.groupId!,
            eventId: event.id!,
            delta: willBeOpen ? 1 : -1,
          );
        }
        transaction.update(docRef, updates);
      });
    } catch (e) {
      throw Exception('Erro ao atualizar evento: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _isOpenEventStatus(String status) =>
      const {'scheduled', 'published', 'in_progress'}.contains(status);

  Future<void> _runTransactionPreservingCallbackErrors(
    Future<void> Function(Transaction transaction) callback,
  ) async {
    Object? callbackError;
    StackTrace? callbackStackTrace;

    try {
      await _firestore.runTransaction<void>((transaction) async {
        try {
          await callback(transaction);
        } catch (error, stackTrace) {
          callbackError = error;
          callbackStackTrace = stackTrace;
          Error.throwWithStackTrace(error, stackTrace);
        }
      });
    } catch (error, stackTrace) {
      if (callbackError != null && callbackStackTrace != null) {
        Error.throwWithStackTrace(callbackError!, callbackStackTrace!);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _writeOpenEventCountDelta(
    Transaction transaction, {
    required String groupId,
    required String eventId,
    required int delta,
  }) async {
    final groupRef = _firestore.collection('groups').doc(groupId);
    final groupSnapshot = await transaction.get(groupRef);
    final groupData = groupSnapshot.data();
    if (groupData == null) {
      throw StateError('Organização não encontrada.');
    }
    final count = groupData['open_events_count'];
    if (count is! int || count < 0) {
      throw StateError(
        'O contador de rachas desta organização não foi inicializado. '
        'Execute a inicialização direcionada para o grupo $groupId.',
      );
    }
    final ownerId = UserModel.groupOwnerId(groupData);
    if (ownerId == null || ownerId.isEmpty) {
      throw StateError('O proprietário da organização não foi encontrado.');
    }
    if (FirebaseAuth.instance.currentUser?.uid == ownerId) {
      final ownerSnapshot = await transaction.get(
        _firestore.collection('users').doc(ownerId),
      );
      final ownerData = ownerSnapshot.data();
      if (ownerData == null) {
        throw StateError('O perfil do organizador não foi encontrado.');
      }
      final ownerPlan = UserModel.effectivePlanForGroupOwner(
        ownerId: ownerId,
        ownerData: ownerData,
        groupData: groupData,
      );
      final ownerVipTier = UserModel.effectiveVipTierForGroupOwner(
        ownerId: ownerId,
        ownerData: ownerData,
        groupData: groupData,
      );
      final ownerLimits = ownerVipTier == null
          ? PlanLimits.forOrganizerPlan(ownerPlan)
          : PlanLimits.forVipTier(ownerVipTier, ownerPlan);
      final maxOpenEvents = ownerLimits.maxOpenEvents;
      if (delta > 0 && maxOpenEvents != null && count + delta > maxOpenEvents) {
        throw StateError(
          'O limite de $maxOpenEvents rachas abertos do plano foi atingido.',
        );
      }
    }
    if (count + delta < 0) {
      throw StateError('O contador de rachas abertos está inconsistente.');
    }

    transaction.update(groupRef, {
      'open_events_count': count + delta,
      'capacity_event_id': eventId,
      'capacity_event_delta': delta,
      'capacity_event_nonce': _firestore.collection('groups').doc().id,
    });
  }

  void _validateEventConfiguration(EventModel event) {
    if (event.groupId == null || event.groupId!.trim().isEmpty) {
      throw ArgumentError(
        'Todo evento deve estar vinculado a uma organização.',
      );
    }
    if (event.numberOfTeams < 2 || event.linePlayersPerTeam < 1) {
      throw ArgumentError('A estrutura de times do evento é inválida.');
    }
    if (!SportConfig.isSupported(event.sport)) {
      throw ArgumentError('A modalidade selecionada não é suportada.');
    }
    if (event.externalGoalkeeperSlots < 0 ||
        event.externalGoalkeeperSlots > event.maxGoalkeepers) {
      throw ArgumentError(
        'As vagas externas de goleiro excedem a capacidade do evento.',
      );
    }
    if (event.goalkeeperAid < 0) {
      throw ArgumentError('A ajuda de custo não pode ser negativa.');
    }
    if (event.externalGoalkeeperSlots == 0 && event.goalkeeperAid > 0) {
      throw ArgumentError(
        'Defina vagas externas antes de configurar ajuda de custo.',
      );
    }
    if (!event.sportHasGoalkeeper &&
        (event.allowGoalkeepers ||
            event.externalGoalkeeperSlots > 0 ||
            event.goalkeeperAid > 0)) {
      throw ArgumentError(
        'Esta modalidade não permite goleiros nem ajuda de custo.',
      );
    }
  }

  Future<void> deleteEvent(String eventId) async {
    try {
      _isLoading = true;
      notifyListeners();
      final eventRef = _firestore.collection('events').doc(eventId);
      await _firestore.runTransaction((transaction) async {
        final eventSnapshot = await transaction.get(eventRef);
        final eventData = eventSnapshot.data();
        if (eventData == null) return;
        final info = eventData['info'] as Map<String, dynamic>? ?? {};
        if (_isOpenEventStatus(info['status'] as String? ?? '')) {
          final groupId = info['group_id'] as String? ?? '';
          if (groupId.isEmpty) {
            throw StateError('O evento não possui organização válida.');
          }
          await _writeOpenEventCountDelta(
            transaction,
            groupId: groupId,
            eventId: eventId,
            delta: -1,
          );
        }
        transaction.delete(eventRef);
      });
    } catch (e) {
      throw Exception(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateEventStatus(String eventId, String newStatus) async {
    try {
      final eventRef = _firestore.collection('events').doc(eventId);
      await _firestore.runTransaction((transaction) async {
        final eventSnapshot = await transaction.get(eventRef);
        final eventData = eventSnapshot.data();
        if (eventData == null) {
          throw StateError('Evento não encontrado.');
        }
        final info = eventData['info'] as Map<String, dynamic>? ?? {};
        final oldStatus = info['status'] as String? ?? '';
        final wasOpen = _isOpenEventStatus(oldStatus);
        final willBeOpen = _isOpenEventStatus(newStatus);
        if (wasOpen != willBeOpen) {
          final groupId = info['group_id'] as String? ?? '';
          if (groupId.isEmpty) {
            throw StateError('O evento não possui organização válida.');
          }
          await _writeOpenEventCountDelta(
            transaction,
            groupId: groupId,
            eventId: eventId,
            delta: willBeOpen ? 1 : -1,
          );
        }
        transaction.update(eventRef, {'info.status': newStatus});
      });
    } catch (e) {
      throw Exception(e);
    }
  }

  // --- GESTÃO DE PARTICIPANTES ---
  bool _isStaff(UserModel user) {
    if (user.role == 'org') return true;
    if (user.role == 'master' && user.positions.isEmpty) return true;
    return false;
  }

  bool _isGuest(UserModel user) => user.status == 'inactive';

  List<ParticipantModel> _sortParticipantsByPriority(
    List<ParticipantModel> participants,
  ) {
    participants.sort((a, b) {
      int getPriority(ParticipantModel p) {
        if (p.isStaff) return 1;
        if (!p.isGuest) return 2;
        return 3;
      }

      int priorityA = getPriority(a);
      int priorityB = getPriority(b);
      if (priorityA != priorityB) return priorityA.compareTo(priorityB);
      return a.registeredAt.compareTo(b.registeredAt);
    });
    return participants;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getJoinRequestsStream(
    String eventId,
  ) => _firestore
      .collection('events')
      .doc(eventId)
      .collection('join_requests')
      .where('status', isEqualTo: 'pending')
      .snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> getJoinRequestStream(
    String eventId,
    String userId,
  ) => _firestore
      .collection('events')
      .doc(eventId)
      .collection('join_requests')
      .doc(userId)
      .snapshots();

  Future<String> joinEvent(
    String eventId,
    UserModel user, {
    String role = 'line',
  }) async {
    try {
      _isLoading = true;
      notifyListeners();
      final docRef = _firestore.collection('events').doc(eventId);
      final requestRef = docRef.collection('join_requests').doc(user.uid);
      final result = await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists || snapshot.data() == null) {
          throw StateError('Evento não encontrado.');
        }
        final event = EventModel.fromMap(
          snapshot.id,
          snapshot.data() as Map<String, dynamic>,
        );
        final requestSnapshot = await transaction.get(requestRef);
        final existingIndex = event.participants.indexWhere(
          (p) => p.uid == user.uid,
        );
        if (existingIndex >= 0 &&
            event.participants[existingIndex].status == 'active') {
          return 'active';
        }
        if (existingIndex >= 0 &&
            event.participants[existingIndex].status == 'queue') {
          return 'queue';
        }
        if (existingIndex >= 0) {
          throw StateError(
            'Você já participou deste evento; solicite ajuda ao organizador para retornar.',
          );
        }
        if (requestSnapshot.exists &&
            requestSnapshot.data()?['status'] == 'pending') {
          throw StateError('Sua solicitação já está aguardando aprovação.');
        }
        if (role != 'line' && role != 'goalkeeper') {
          throw ArgumentError('Função inválida para esta inscrição.');
        }
        if (role == 'goalkeeper' &&
            (!event.sportHasGoalkeeper || !event.allowGoalkeepers)) {
          throw StateError('Este evento não está aceitando goleiros.');
        }
        if (role == 'line' && !event.allowLinePlayers) {
          throw StateError(
            'Este evento não está aceitando jogadores de linha.',
          );
        }
        final canPlayRole =
            user.canPlayMultiplePositions ||
            (role == 'goalkeeper'
                ? user.positions.contains('Goleiro')
                : user.positions.any((position) => position != 'Goleiro'));
        if (!canPlayRole) {
          throw StateError(
            'Sua posição cadastrada não permite jogar nesta função.',
          );
        }
        var isExternal = true;
        if (event.groupId != null) {
          final membershipRef = _firestore
              .collection('groups')
              .doc(event.groupId)
              .collection('members')
              .doc(user.uid);
          final groupRef = _firestore.collection('groups').doc(event.groupId);
          final membershipSnapshot = await transaction.get(membershipRef);
          final groupSnapshot = await transaction.get(groupRef);
          isExternal =
              !membershipSnapshot.exists &&
              UserModel.groupOwnerId(groupSnapshot.data() ?? const {}) !=
                  user.uid;
        }

        if (role == 'goalkeeper' &&
            isExternal &&
            event.participants
                    .where(
                      (participant) =>
                          participant.status == 'active' &&
                          participant.isExternal &&
                          participant.roleInMatch == 'goalkeeper',
                    )
                    .length >=
                event.externalGoalkeeperSlots) {
          throw StateError(
            'As vagas externas para goleiros deste evento já foram preenchidas.',
          );
        }

        bool isStaff = _isStaff(user);
        bool isGuest = _isGuest(user);

        if (isExternal) {
          if (role == 'goalkeeper') {
            final activeExternalGoalkeepers = event.participants.where(
              (participant) =>
                  participant.status == 'active' &&
                  participant.isExternal &&
                  participant.roleInMatch == 'goalkeeper',
            );
            if (activeExternalGoalkeepers.length >=
                event.externalGoalkeeperSlots) {
              throw StateError(
                'As vagas externas para goleiros deste evento já foram preenchidas.',
              );
            }
          }
          transaction.set(requestRef, {
            'uid': user.uid,
            'name': user.name,
            'nickname': user.nickname,
            'role_in_match': role,
            'status': 'pending',
            'requested_at': FieldValue.serverTimestamp(),
            'profile': {
              'name': user.name,
              'nickname': user.nickname,
              'phone': user.phone,
              'positions': user.positions,
              'rating': user.rating,
              'pix_key': user.pixKey,
              'can_play_multiple_positions': user.canPlayMultiplePositions,
            },
          });
          return 'requested';
        }

        final participantStatus =
            _activeRoleCount(event.participants, role) <
                (role == 'goalkeeper'
                    ? event.maxGoalkeepers
                    : event.maxLinePlayers)
            ? 'active'
            : 'queue';
        final participant = ParticipantModel(
          uid: user.uid,
          name: user.name,
          nickname: user.nickname,
          pixKey: user.pixKey,
          status: participantStatus,
          registeredAt: DateTime.now(),
          roleInMatch: role,
          paymentStatus: 'pending',
          isStaff: isStaff,
          isGuest: isGuest,
          isExternal: isExternal,
          paymentGatewayId: null,
          isAvulso: false,
        );
        transaction.update(docRef, {
          'participants': FieldValue.arrayUnion([participant.toMap()]),
        });
        if (role == 'goalkeeper') {
          transaction.set(docRef.collection('goalie_payments').doc(user.uid), {
            'uid': user.uid,
            'pix_key': user.pixKey.trim(),
            'goalie_payment_status': 'none',
          });
        }
        return participantStatus;
      });
      return result;
    } catch (e) {
      throw Exception(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> approveJoinRequest(String eventId, String userId) async {
    final eventRef = _firestore.collection('events').doc(eventId);
    final requestRef = eventRef.collection('join_requests').doc(userId);

    await _firestore.runTransaction((transaction) async {
      final eventSnapshot = await transaction.get(eventRef);
      final requestSnapshot = await transaction.get(requestRef);
      if (!eventSnapshot.exists || eventSnapshot.data() == null) {
        throw StateError('Evento não encontrado.');
      }
      final request = requestSnapshot.data();
      if (request == null || request['status'] != 'pending') {
        throw StateError('A solicitação não está mais pendente.');
      }
      final event = EventModel.fromMap(eventSnapshot.id, eventSnapshot.data()!);
      final role = request['role_in_match'] as String? ?? '';
      final profile = request['profile'] as Map<String, dynamic>?;
      if (profile == null) {
        throw StateError(
          'Esta solicitação não contém o perfil atualizado do atleta. '
          'Peça que ele envie uma nova solicitação.',
        );
      }
      final positions = profile['positions'] as List<dynamic>? ?? const [];
      final canPlayMultiple = profile['can_play_multiple_positions'] == true;
      final canPlayRequestedRole =
          canPlayMultiple ||
          (role == 'goalkeeper'
              ? positions.contains('Goleiro')
              : positions.any((position) => position != 'Goleiro'));
      if (!canPlayRequestedRole) {
        throw StateError(
          'O atleta não possui mais uma posição compatível com esta vaga.',
        );
      }
      if (role != 'line' && role != 'goalkeeper') {
        throw StateError('A função solicitada é inválida.');
      }
      if (role == 'goalkeeper' &&
          (!event.sportHasGoalkeeper || !event.allowGoalkeepers)) {
        throw StateError('Este evento não está aceitando goleiros.');
      }
      if (role == 'line' && !event.allowLinePlayers) {
        throw StateError('Este evento não está aceitando jogadores de linha.');
      }
      if (role == 'goalkeeper' &&
          event.participants
                  .where(
                    (participant) =>
                        participant.status == 'active' &&
                        participant.isExternal &&
                        participant.roleInMatch == 'goalkeeper',
                  )
                  .length >=
              event.externalGoalkeeperSlots) {
        throw StateError(
          'As vagas externas para goleiros já foram preenchidas.',
        );
      }

      final participants = List<ParticipantModel>.from(event.participants);
      participants.removeWhere((participant) => participant.uid == userId);
      final isActive =
          _activeRoleCount(event.participants, role) <
          (role == 'goalkeeper' ? event.maxGoalkeepers : event.maxLinePlayers);
      participants.add(
        ParticipantModel(
          uid: userId,
          name: request['name'] as String? ?? '',
          nickname: request['nickname'] as String? ?? '',
          pixKey: profile['pix_key'] as String? ?? '',
          status: isActive ? 'active' : 'queue',
          registeredAt:
              (request['requested_at'] as Timestamp?)?.toDate() ??
              DateTime.now(),
          roleInMatch: role,
          isExternal: true,
        ),
      );
      if (role == 'goalkeeper') {
        transaction.set(eventRef.collection('goalie_payments').doc(userId), {
          'uid': userId,
          'pix_key': (profile['pix_key'] as String? ?? '').trim(),
          'goalie_payment_status': 'none',
        });
      }
      transaction.update(eventRef, {
        'participants': participants
            .map((participant) => participant.toMap())
            .toList(),
      });
      transaction.update(requestRef, {
        'status': 'approved',
        'reviewed_at': FieldValue.serverTimestamp(),
        'reviewed_by': FirebaseAuth.instance.currentUser?.uid,
      });
    });
  }

  Future<void> rejectJoinRequest(String eventId, String userId) async {
    final requestRef = _firestore
        .collection('events')
        .doc(eventId)
        .collection('join_requests')
        .doc(userId);
    await _firestore.runTransaction((transaction) async {
      final request = await transaction.get(requestRef);
      if (!request.exists || request.data()?['status'] != 'pending') {
        throw StateError('A solicitação não está mais pendente.');
      }
      transaction.update(requestRef, {
        'status': 'rejected',
        'reviewed_at': FieldValue.serverTimestamp(),
        'reviewed_by': FirebaseAuth.instance.currentUser?.uid,
      });
    });
  }

  Future<void> cancelJoinRequest(String eventId, String userId) async {
    final requestRef = _firestore
        .collection('events')
        .doc(eventId)
        .collection('join_requests')
        .doc(userId);
    await _firestore.runTransaction((transaction) async {
      final request = await transaction.get(requestRef);
      if (!request.exists || request.data()?['status'] != 'pending') {
        throw StateError('A solicitação não está mais pendente.');
      }
      transaction.delete(requestRef);
    });
  }

  int _activeRoleCount(List<ParticipantModel> participants, String role) =>
      participants
          .where(
            (participant) =>
                participant.status == 'active' &&
                participant.roleInMatch == role,
          )
          .length;

  Future<void> addPlayerToEvent(
    String eventId,
    UserModel user,
    String role,
  ) async {
    try {
      _isLoading = true;
      notifyListeners();
      final docRef = _firestore.collection('events').doc(eventId);
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        final eventData = snapshot.data() as Map<String, dynamic>;
        final event = EventModel.fromMap(snapshot.id, eventData);
        final existingIndex = event.participants.indexWhere(
          (p) => p.uid == user.uid,
        );
        List<ParticipantModel> updatedList = List.from(event.participants);

        bool isStaff = _isStaff(user);
        bool isGuest = _isGuest(user);

        if (existingIndex >= 0) {
          updatedList.removeAt(existingIndex);
        }

        updatedList.add(
          ParticipantModel(
            uid: user.uid,
            name: user.name,
            nickname: user.nickname,
            status: 'active',
            registeredAt: DateTime.now(),
            roleInMatch: role,
            paymentStatus: 'pending',
            isStaff: isStaff,
            isGuest: isGuest,
            paymentGatewayId: null,
            isAvulso: false,
          ),
        );

        if (event.status != 'published')
          updatedList = _sortParticipantsByPriority(updatedList);
        transaction.update(docRef, {
          'participants': updatedList.map((p) => p.toMap()).toList(),
        });
      });
    } catch (e) {
      throw Exception(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> leaveEvent(String eventId, String userId) async {
    try {
      _isLoading = true;
      notifyListeners();

      final docRef = _firestore.collection('events').doc(eventId);
      String? paymentIdToCancel;

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        final pendingPixRef = docRef.collection('pending_payments').doc(userId);
        final pendingSnap = await transaction.get(pendingPixRef);

        final event = EventModel.fromMap(
          snapshot.id,
          snapshot.data() as Map<String, dynamic>,
        );

        final index = event.participants.indexWhere((p) => p.uid == userId);
        if (index == -1) return;

        final p = event.participants[index];
        if (p.paymentStatus == 'paid') {
          throw Exception(
            "Ação bloqueada: O atleta já realizou o pagamento. É necessário estornar o valor antes de removê-lo.",
          );
        }

        List<ParticipantModel> updatedList = List.from(event.participants);

        if (p.isAvulso) {
          updatedList.removeAt(index);
        } else {
          updatedList[index] = p.copyWith(
            status: 'dropout',
            paymentStatus: 'pending',
            paymentGatewayId: null,
          );
        }

        transaction.update(docRef, {
          'participants': updatedList.map((p) => p.toMap()).toList(),
        });

        if (pendingSnap.exists) {
          final data = pendingSnap.data();
          if (data != null && data['payment_id'] != null) {
            paymentIdToCancel = data['payment_id'];
          }
          transaction.delete(pendingPixRef);
        }
      });

      if (paymentIdToCancel != null) {
        try {
          print("Cancelando PIX ID: $paymentIdToCancel");
        } catch (e) {
          print("Erro ao cancelar PIX (não crítico): $e");
        }
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> togglePaymentStatus(
    String eventId,
    String userId,
    UserModel adminUser,
  ) async {
    try {
      final docRef = _firestore.collection('events').doc(eventId);
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        final event = EventModel.fromMap(
          snapshot.id,
          snapshot.data() as Map<String, dynamic>,
        );
        final index = event.participants.indexWhere((p) => p.uid == userId);
        if (index == -1) return;
        List<ParticipantModel> updatedList = List.from(event.participants);
        final p = updatedList[index];
        final newStatus = p.paymentStatus == 'paid' ? 'pending' : 'paid';

        updatedList[index] = p.copyWith(
          paymentStatus: newStatus,
          paymentGatewayId: newStatus == 'pending' ? null : p.paymentGatewayId,
        );

        transaction.update(docRef, {
          'participants': updatedList.map((p) => p.toMap()).toList(),
        });

        final transactionRef = _firestore.collection('transactions').doc();
        if (newStatus == 'paid') {
          transaction.set(transactionRef, {
            'description': 'Pagamento: ${p.name} - ${event.title}',
            'amount': event.price,
            'type': 'credit',
            'date': FieldValue.serverTimestamp(),
            'category': 'player_payment',
            'related_event_id': eventId,
            'related_user_id': userId,
            'group_id': event.groupId,
            'registered_by_uid': adminUser.uid,
            'registered_by_name': adminUser.name,
          });
        } else {
          transaction.set(transactionRef, {
            'description': 'Estorno: ${p.name} - ${event.title}',
            'amount': event.price,
            'type': 'debit',
            'date': FieldValue.serverTimestamp(),
            'category': 'refund',
            'related_event_id': eventId,
            'related_user_id': userId,
            'group_id': event.groupId,
            'registered_by_uid': adminUser.uid,
            'registered_by_name': adminUser.name,
          });
        }
      });
    } catch (e) {
      throw Exception('Erro ao atualizar pagamento: $e');
    }
  }

  Future<void> markGoalkeeperPaymentPending({
    required String eventId,
    required String goalkeeperUid,
    required UserModel organizer,
    required double amount,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Informe o valor acordado antes de registrar o pagamento.',
      );
    }

    final eventRef = _firestore.collection('events').doc(eventId);
    final paymentRef = eventRef
        .collection('goalie_payments')
        .doc(goalkeeperUid);
    final expenseRef = _firestore.collection('transactions').doc();

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(eventRef);
      final paymentSnapshot = await transaction.get(paymentRef);
      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('Evento não encontrado.');
      }

      final event = EventModel.fromMap(snapshot.id, snapshot.data()!);
      if (event.groupId == null || event.groupId!.isEmpty) {
        throw StateError(
          'Vincule este racha a um grupo para lançar o pagamento no caixa.',
        );
      }
      final index = event.participants.indexWhere(
        (participant) => participant.uid == goalkeeperUid,
      );
      if (index < 0) {
        throw StateError('Goleiro não encontrado na lista do racha.');
      }

      final goalkeeper = event.participants[index];
      if (goalkeeper.roleInMatch != 'goalkeeper' ||
          goalkeeper.status != 'active') {
        throw StateError('O participante não é um goleiro confirmado.');
      }
      final paymentData = paymentSnapshot.data();
      if ((paymentData?['goalie_payment_status'] ?? 'none') != 'none') {
        throw StateError('Este pagamento já foi iniciado.');
      }

      final now = DateTime.now();
      final updatedParticipants = List<ParticipantModel>.from(
        event.participants,
      );
      updatedParticipants[index] = goalkeeper.copyWith(
        goaliePaymentStatus: 'pending_confirmation',
      );

      transaction.update(eventRef, {
        'participants': updatedParticipants
            .map((participant) => participant.toMap())
            .toList(),
      });
      final paymentUpdate = {
        'goalie_payment_status': 'pending_confirmation',
        'amount': amount,
        'marked_at': Timestamp.fromDate(now),
        'marked_by_uid': organizer.uid,
        'marked_by_name': organizer.name,
        'transaction_id': expenseRef.id,
      };
      if (paymentSnapshot.exists) {
        transaction.update(paymentRef, paymentUpdate);
      } else {
        transaction.set(paymentRef, {
          'uid': goalkeeperUid,
          'pix_key': '',
          ...paymentUpdate,
        });
      }
      transaction.set(expenseRef, {
        'description': 'Pagamento Goleiro - ${event.title}',
        'amount': amount,
        'type': 'debit',
        'date': FieldValue.serverTimestamp(),
        'category': 'goalkeeper_payment',
        'related_event_id': eventId,
        'related_user_id': goalkeeper.uid,
        'goalkeeper_name': goalkeeper.name,
        'group_id': event.groupId,
        'registered_by_uid': organizer.uid,
        'registered_by_name': organizer.name,
        'payment_status': 'pending_confirmation',
        'created_at': Timestamp.fromDate(now),
      });
    });
  }

  Future<void> confirmGoalkeeperPaymentReceived({
    required String eventId,
    required String goalkeeperUid,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != goalkeeperUid) {
      throw StateError('Somente o goleiro beneficiado pode confirmar o Pix.');
    }

    final eventRef = _firestore.collection('events').doc(eventId);
    final paymentRef = eventRef
        .collection('goalie_payments')
        .doc(goalkeeperUid);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(eventRef);
      final paymentSnapshot = await transaction.get(paymentRef);
      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('Evento não encontrado.');
      }

      final event = EventModel.fromMap(snapshot.id, snapshot.data()!);
      final index = event.participants.indexWhere(
        (participant) => participant.uid == goalkeeperUid,
      );
      if (index < 0) {
        throw StateError('Goleiro não encontrado na lista do racha.');
      }

      final goalkeeper = event.participants[index];
      if (goalkeeper.roleInMatch != 'goalkeeper' ||
          paymentSnapshot.data()?['goalie_payment_status'] !=
              'pending_confirmation') {
        throw StateError('Não há pagamento pendente para confirmar.');
      }

      transaction.update(paymentRef, {
        'goalie_payment_status': 'confirmed',
        'confirmed_at': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> updateParticipantsOrder(
    String eventId,
    List<ParticipantModel> newOrder,
  ) async {
    try {
      final docRef = _firestore.collection('events').doc(eventId);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        final event = EventModel.fromMap(
          snapshot.id,
          snapshot.data() as Map<String, dynamic>,
        );

        // 1. Defina os limites baseados no seu EventModel
        final int maxGk = event.maxGoalkeepers;
        final int maxLine = event.maxLinePlayers;

        // 2. Separa a lista atualizada por função
        final gks = newOrder
            .where((p) => p.roleInMatch == 'goalkeeper' && p.status == 'active')
            .toList();
        final externalGks = gks.where((p) => p.isExternal).length;
        if (externalGks > event.externalGoalkeeperSlots) {
          throw StateError(
            'A lista excede as vagas externas reservadas para goleiros.',
          );
        }
        final lines = newOrder
            .where((p) => p.roleInMatch == 'line' && p.status == 'active')
            .toList();

        // 3. Validação de Goleiros Pagos
        for (int i = 0; i < gks.length; i++) {
          if (i >= maxGk && gks[i].paymentStatus == 'paid') {
            throw Exception(
              "Ação bloqueada: O goleiro ${gks[i].nickname} já pagou e não pode ser movido para a reserva.",
            );
          }
        }

        // 4. Validação de Jogadores de Linha Pagos
        for (int i = 0; i < lines.length; i++) {
          if (i >= maxLine && lines[i].paymentStatus == 'paid') {
            throw Exception(
              "Ação bloqueada: O jogador ${lines[i].nickname} já pagou e não pode ser movido para a reserva.",
            );
          }
        }

        transaction.update(docRef, {
          'participants': newOrder.map((p) => p.toMap()).toList(),
        });
      });
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> removeUnpaidParticipants(String eventId) async {
    try {
      _isLoading = true;
      notifyListeners();
      WriteBatch batch = _firestore.batch();
      DocumentReference eventRef = _firestore.collection('events').doc(eventId);
      DocumentSnapshot snapshot = await eventRef.get();
      final event = EventModel.fromMap(
        snapshot.id,
        snapshot.data() as Map<String, dynamic>,
      );
      List<ParticipantModel> updatedList = List.from(event.participants);
      int currentGk = 0;
      int currentLine = 0;
      int maxGk = event.maxGoalkeepers;
      int maxLine = event.maxLinePlayers;
      bool changed = false;

      for (int i = 0; i < updatedList.length; i++) {
        final p = updatedList[i];
        if (p.status == 'active') {
          bool isTitular = false;
          if (p.roleInMatch == 'goalkeeper') {
            currentGk++;
            if (currentGk <= maxGk) isTitular = true;
          } else {
            currentLine++;
            if (currentLine <= maxLine) isTitular = true;
          }

          if (isTitular &&
              p.paymentStatus != 'paid' &&
              p.roleInMatch != 'goalkeeper') {
            updatedList[i] = p.copyWith(
              status: 'dropout',
              paymentStatus: 'pending',
              paymentGatewayId: null,
            );
            changed = true;
            DocumentReference userRef = _firestore
                .collection('users')
                .doc(p.uid);
            batch.update(userRef, {
              'stats.unpaid_removals': FieldValue.increment(1),
            });
            DocumentReference pendingRef = eventRef
                .collection('pending_payments')
                .doc(p.uid);
            batch.delete(pendingRef);
          }
        }
      }

      if (changed) {
        batch.update(eventRef, {
          'participants': updatedList.map((p) => p.toMap()).toList(),
        });
        await batch.commit();
      }
    } catch (e) {
      throw Exception(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- FINALIZAR EVENTO (AUTO-CURA DE DADOS) ---
  Future<void> finalizeEvent(
    String eventId,
    List<ParticipantModel> participantsWithAttendance,
  ) async {
    try {
      _isLoading = true;
      notifyListeners();

      final eventDoc = await _firestore.collection('events').doc(eventId).get();
      final eventDate =
          (eventDoc.data()?['info']['start_date_time'] as Timestamp).toDate();

      WriteBatch batch = _firestore.batch();
      DocumentReference eventRef = _firestore.collection('events').doc(eventId);

      // AUTO-CURA (CLEANUP): Se o bug antigo salvou algum 'isAvulso' na lista original, limpamos agora.
      final rawParticipants =
          eventDoc.data()?['participants'] as List<dynamic>? ?? [];
      final cleanParticipants = rawParticipants
          .where((p) => p['is_avulso'] != true)
          .toList();

      batch.update(eventRef, {
        'info.status': 'finished',
        'closing_list': participantsWithAttendance
            .map((p) => p.toMap())
            .toList(),
        'participants':
            cleanParticipants, // Sobrescreve a lista principal com a versão limpa
      });

      for (var p in participantsWithAttendance) {
        if (p.status == 'active') {
          DocumentReference userRef = _firestore.collection('users').doc(p.uid);

          if (p.attendance == 'present') {
            batch.update(userRef, {
              'stats.matches_played': FieldValue.increment(1),
              'stats.last_match_date': Timestamp.fromDate(eventDate),
            });
          } else if (p.attendance == 'absent') {
            batch.update(userRef, {'stats.no_shows': FieldValue.increment(1)});
          }
        }
      }
      await batch.commit();
    } catch (e) {
      throw Exception(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- REABRIR EVENTO ---
  Future<void> reopenEvent(String eventId) async {
    try {
      _isLoading = true;
      notifyListeners();
      final docRef = _firestore.collection('events').doc(eventId);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        final eventData = snapshot.data();
        if (eventData == null) {
          throw StateError('Evento não encontrado.');
        }
        final info = eventData['info'] as Map<String, dynamic>? ?? {};
        if (info['status'] != 'finished') return;
        final groupId = info['group_id'] as String? ?? '';
        if (groupId.isEmpty) {
          throw StateError('O evento não possui organização válida.');
        }
        final eventDate = (info['start_date_time'] as Timestamp).toDate();
        final closingList = (eventData['closing_list'] as List<dynamic>? ?? [])
            .map(
              (item) => ParticipantModel.fromMap(item as Map<String, dynamic>),
            )
            .toList();
        final usersToUpdate = <String, DocumentReference>{};
        for (final participant in closingList) {
          if (participant.status == 'active' &&
              (participant.attendance == 'present' ||
                  participant.attendance == 'absent')) {
            usersToUpdate[participant.uid] = _firestore
                .collection('users')
                .doc(participant.uid);
          }
        }

        final userSnapshots = <String, DocumentSnapshot>{};
        for (final entry in usersToUpdate.entries) {
          userSnapshots[entry.key] = await transaction.get(entry.value);
        }

        await _writeOpenEventCountDelta(
          transaction,
          groupId: groupId,
          eventId: eventId,
          delta: 1,
        );

        for (final participant in closingList) {
          if (participant.status != 'active') continue;
          final userSnapshot = userSnapshots[participant.uid];
          if (userSnapshot == null || !userSnapshot.exists) continue;
          if (participant.attendance == 'present') {
            final userData = userSnapshot.data() as Map<String, dynamic>;
            final stats = userData['stats'] as Map<String, dynamic>? ?? {};
            final lastDate = stats['last_match_date'] as Timestamp?;
            final updates = <String, dynamic>{
              'stats.matches_played': FieldValue.increment(-1),
            };
            if (lastDate != null &&
                lastDate.toDate().isAtSameMomentAs(eventDate)) {
              updates['stats.last_match_date'] = FieldValue.delete();
            }
            transaction.update(usersToUpdate[participant.uid]!, updates);
          } else if (participant.attendance == 'absent') {
            transaction.update(usersToUpdate[participant.uid]!, {
              'stats.no_shows': FieldValue.increment(-1),
            });
          }
        }
        transaction.update(docRef, {
          'info.status': 'published',
          'closing_list': FieldValue.delete(),
        });
      });
    } catch (e) {
      throw Exception(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- REPARAR ESTATÍSTICAS ---
  Future<void> recalculateAllStats() async {
    try {
      _isLoading = true;
      notifyListeners();

      final closingSnap = await _firestore
          .collection('closings')
          .orderBy('closed_at', descending: true)
          .limit(1)
          .get();

      DateTime? startDate;
      if (closingSnap.docs.isNotEmpty) {
        startDate = (closingSnap.docs.first.data()['closed_at'] as Timestamp)
            .toDate();
      }

      Query query = _firestore
          .collection('events')
          .where('info.status', isEqualTo: 'finished')
          .orderBy('info.start_date_time', descending: false);

      if (startDate != null) {
        query = query.where(
          'info.start_date_time',
          isGreaterThan: Timestamp.fromDate(startDate),
        );
      }

      final eventsSnap = await query.get();

      Map<String, int> matchesCountMap = {};
      Map<String, int> noShowsMap = {};
      Map<String, DateTime> lastDateMap = {};

      for (var doc in eventsSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final eventDate = (data['info']['start_date_time'] as Timestamp)
            .toDate();

        // CORREÇÃO: No recálculo, deve ler a closing_list se existir
        List<dynamic> rawList =
            data['closing_list'] != null &&
                (data['closing_list'] as List).isNotEmpty
            ? data['closing_list']
            : data['participants'] ?? [];

        final participants = List.from(rawList);

        for (var pData in participants) {
          if (pData['status'] == 'active') {
            String uid = pData['uid'];
            String attendance = pData['attendance'] ?? 'pending';

            if (attendance == 'present') {
              matchesCountMap[uid] = (matchesCountMap[uid] ?? 0) + 1;
              lastDateMap[uid] = eventDate;
            } else if (attendance == 'absent') {
              noShowsMap[uid] = (noShowsMap[uid] ?? 0) + 1;
            }
          }
        }
      }

      WriteBatch batch = _firestore.batch();
      int operationCount = 0;
      Set<String> allUserIds = {...matchesCountMap.keys, ...noShowsMap.keys};

      for (String uid in allUserIds) {
        DocumentReference userRef = _firestore.collection('users').doc(uid);

        Map<String, dynamic> updateData = {
          'stats.matches_played': matchesCountMap[uid] ?? 0,
          'stats.no_shows': noShowsMap[uid] ?? 0,
        };

        if (lastDateMap.containsKey(uid)) {
          updateData['stats.last_match_date'] = Timestamp.fromDate(
            lastDateMap[uid]!,
          );
        }

        batch.update(userRef, updateData);
        operationCount++;

        if (operationCount >= 450) {
          await batch.commit();
          batch = _firestore.batch();
          operationCount = 0;
        }
      }

      if (operationCount > 0) {
        await batch.commit();
      }
    } catch (e) {
      throw Exception("Erro ao recalcular estatísticas: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
