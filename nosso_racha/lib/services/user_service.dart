import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

class UserService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  // --- LEITURA DE DADOS ---

  Stream<QuerySnapshot> getAllAthletesStream({String? groupId}) {
    if (groupId != null) {
      return _firestore
          .collection('users')
          .where(
            Filter.or(
              Filter('group_ids', arrayContains: groupId),
              Filter('group_id', isEqualTo: groupId),
            ),
          )
          .snapshots();
    }
    return _firestore
        .collection('users')
        .orderBy('personal_info.full_name')
        .snapshots();
  }

  // --- FECHAMENTO E HISTÓRICO ---

  Stream<QuerySnapshot> getClosingsStream({String? groupId}) {
    Query<Map<String, dynamic>> query = _firestore.collection('closings');
    if (groupId != null) {
      query = query.where('group_id', isEqualTo: groupId);
    }
    return query.orderBy('closed_at', descending: true).snapshots();
  }

  Future<List<UserModel>> getClosedPeriodData(String closingId) async {
    final doc = await _firestore.collection('closings').doc(closingId).get();
    if (!doc.exists) return [];

    final data = doc.data() as Map<String, dynamic>;
    final List<dynamic> historyList = data['ranking_snapshot'] ?? [];

    return historyList.map((item) {
      return UserModel(
        uid: item['uid'] ?? '',
        email: '',
        name: item['name'] ?? 'Histórico',
        status: 'inactive',
        role: 'athlete',
        nickname: item['nickname'] ?? '',
        matchesPlayed: item['matches_played'] ?? 0,
        noShows: item['no_shows'] ?? 0,
        unpaidRemovals: item['unpaid_removals'] ?? 0,
      );
    }).toList();
  }

  Future<List<UserModel>> getGroupReportData(String groupId) async {
    final closingSnapshot = await _firestore
        .collection('closings')
        .where('group_id', isEqualTo: groupId)
        .orderBy('closed_at', descending: true)
        .limit(1)
        .get();
    final cutoff = closingSnapshot.docs.isEmpty
        ? null
        : (closingSnapshot.docs.first.data()['closed_at'] as Timestamp?)
              ?.toDate();

    final usersSnapshot = await _firestore
        .collection('users')
        .where(
          Filter.or(
            Filter('group_ids', arrayContains: groupId),
            Filter('group_id', isEqualTo: groupId),
          ),
        )
        .get();
    final users = {for (final doc in usersSnapshot.docs) doc.id: doc.data()};
    final statsByUser = <String, Map<String, dynamic>>{};

    final eventsSnapshot = await _firestore
        .collection('events')
        .where(
          Filter.or(
            Filter('info.group_id', isEqualTo: groupId),
            Filter('group_id', isEqualTo: groupId),
          ),
        )
        .get();
    for (final eventDoc in eventsSnapshot.docs) {
      final event = eventDoc.data();
      final info = event['info'] as Map<String, dynamic>? ?? {};
      if ((info['status'] ?? event['status']) != 'finished') continue;
      final startDate = info['start_date_time'];
      final eventDate = startDate is Timestamp ? startDate.toDate() : null;
      if (cutoff != null && (eventDate == null || !eventDate.isAfter(cutoff))) {
        continue;
      }

      final closingList = event['closing_list'] as List<dynamic>? ?? [];
      final participants = closingList.isNotEmpty
          ? closingList
          : event['participants'] as List<dynamic>? ?? [];
      for (final value in participants) {
        if (value is! Map<String, dynamic>) continue;
        final uid = value['uid'] as String?;
        if (uid == null || !users.containsKey(uid)) continue;
        final userStats = statsByUser.putIfAbsent(
          uid,
          () => {
            'matches_played': 0,
            'no_shows': 0,
            'unpaid_removals': 0,
            'last_match_date': null,
          },
        );
        if (value['status'] == 'active' && value['attendance'] == 'present') {
          userStats['matches_played'] = userStats['matches_played'] + 1;
          if (eventDate != null &&
              (userStats['last_match_date'] == null ||
                  eventDate.isAfter(
                    userStats['last_match_date'] as DateTime,
                  ))) {
            userStats['last_match_date'] = eventDate;
          }
        } else if (value['status'] == 'active' &&
            value['attendance'] == 'absent') {
          userStats['no_shows'] = userStats['no_shows'] + 1;
        }
        if (value['status'] == 'dropout') {
          userStats['unpaid_removals'] = userStats['unpaid_removals'] + 1;
        }
      }
    }

    return users.entries.map((entry) {
      final groupStats =
          statsByUser[entry.key] ??
          {
            'matches_played': 0,
            'no_shows': 0,
            'unpaid_removals': 0,
            'last_match_date': null,
          };
      final lastMatchDate = groupStats['last_match_date'] as DateTime?;
      return UserModel.fromMap(entry.key, {
        ...entry.value,
        'stats': {
          'matches_played': groupStats['matches_played'],
          'no_shows': groupStats['no_shows'],
          'unpaid_removals': groupStats['unpaid_removals'],
          'last_match_date': lastMatchDate == null
              ? null
              : Timestamp.fromDate(lastMatchDate),
        },
      });
    }).toList();
  }

  Future<void> closePeriod(String title, {required String groupId}) async {
    try {
      _isLoading = true;
      notifyListeners();

      final rankingSnapshot = (await getGroupReportData(groupId))
          .where(
            (user) =>
                user.matchesPlayed > 0 ||
                user.noShows > 0 ||
                user.unpaidRemovals > 0,
          )
          .map(
            (user) => {
              'uid': user.uid,
              'name': user.name,
              'nickname': user.nickname,
              'matches_played': user.matchesPlayed,
              'no_shows': user.noShows,
              'unpaid_removals': user.unpaidRemovals,
            },
          )
          .toList();

      await _firestore.collection('closings').add({
        'title': title,
        'group_id': groupId,
        'closed_at': FieldValue.serverTimestamp(),
        'ranking_snapshot': rankingSnapshot,
        'total_athletes': rankingSnapshot.length,
      });
    } catch (e) {
      throw Exception('Erro ao fechar período: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- ZERAR ESTATÍSTICAS (NOVO) ---
  Future<void> resetAllUserStats() async {
    try {
      _isLoading = true;
      notifyListeners();

      // 1. Busca todos os usuários
      final snapshot = await _firestore.collection('users').get();

      // Firestore permite max 500 operações por batch.
      // Se tiver mais que isso, idealmente faria em chunks, mas aqui simplificamos.
      WriteBatch batch = _firestore.batch();

      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'stats.matches_played': 0,
          'stats.no_shows': 0,
          'stats.unpaid_removals': 0,
        });
      }

      // 2. Executa
      await batch.commit();
    } catch (e) {
      throw Exception('Erro ao zerar estatísticas: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- GESTÃO DE USUÁRIOS (CRUD) ---

  Future<void> updateUser(
    UserModel user, {
    required String name,
    required String nickname,
    required String phone,
    required String pixKey,
    required List<String> positions,
    required double rating,
    required String status,
    required String role,
    required String email,
    required String birthDate,
    required Map<String, bool> permissions,
    String? groupId,
  }) async {
    _validatePositions(
      positions: positions,
      canPlayMultiplePositions:
          user.canPlayMultiplePositions || role == 'org' || role == 'master',
    );

    try {
      _isLoading = true;
      notifyListeners();

      await _firestore.collection('users').doc(user.uid).update({
        'status': status,
        'role': role,
        'email': email,
        'permissions': permissions,
        'name': name,
        'phone': phone,
        'birthDate': birthDate,
        'personal_info.full_name': name,
        'personal_info.phone_raw': phone,
        'personal_info.birth_date': birthDate,
        'football_stats.nickname': nickname,
        'football_stats.positions': positions,
        'football_stats.rating': rating,
        'payment_info.pix_key': pixKey,
        if (groupId != null) 'group_ids': FieldValue.arrayUnion([groupId]),
      });
    } catch (e) {
      throw Exception('Erro ao atualizar: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> registerUser({
    required String name,
    required String nickname,
    required String phone,
    required String pixKey,
    required List<String> positions,
    required double rating,
    required String status,
    required String role,
    required String email,
    required String birthDate,
    required Map<String, bool> permissions,
    String? groupId,
  }) async {
    _validatePositions(
      positions: positions,
      canPlayMultiplePositions: role == 'org' || role == 'master',
    );

    try {
      _isLoading = true;
      notifyListeners();

      String? authUid;

      // CORREÇÃO: Cria login apenas se for Ativo. Suspensos criados do zero não ganham Auth.
      if (status == 'active') {
        if (email.isEmpty || birthDate.isEmpty) {
          throw Exception("Email e Data de Nascimento são obrigatórios.");
        }
        // Senha inicial = Data Nasc sem barras
        String password = birthDate.replaceAll('/', '').replaceAll('-', '');
        authUid = await _createAuthUser(email, password);
      }

      final userData = {
        'status': status,
        'role': role,
        'is_owner': false,
        'email': email,
        'permissions': permissions,
        'requires_personal_data': authUid != null,
        'personal_info': {
          'full_name': name,
          'phone_raw': phone,
          'birth_date': birthDate,
        },
        'football_stats': {
          'nickname': nickname,
          'positions': positions,
          'rating': rating,
        },
        'payment_info': {'pix_key': pixKey},
        'plan': 'free',
        if (groupId != null) 'group_ids': [groupId],
        'stats': {'matches_played': 0, 'no_shows': 0, 'unpaid_removals': 0},
        'created_at': FieldValue.serverTimestamp(),
      };

      if (authUid != null) {
        await _firestore.collection('users').doc(authUid).set(userData);
      } else {
        await _firestore.collection('users').add(userData);
      }
    } catch (e) {
      throw Exception('Erro ao cadastrar: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _validatePositions({
    required List<String> positions,
    required bool canPlayMultiplePositions,
  }) {
    if (positions.isEmpty) {
      throw ArgumentError('Selecione pelo menos uma posição.');
    }
    if (!canPlayMultiplePositions && positions.length > 1) {
      throw ArgumentError('Atletas do plano Free podem escolher uma posição.');
    }
  }

  // --- AUXILIARES ---

  Future<String> _createAuthUser(String email, String password) async {
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp',
        options: Firebase.app().options,
      );

      final auth = FirebaseAuth.instanceFor(app: secondaryApp);

      UserCredential cred = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      return cred.user!.uid;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw Exception('Este email já está cadastrado.');
      } else if (e.code == 'weak-password') {
        throw Exception('A senha (data nascimento) é muito fraca.');
      }
      throw Exception('Erro no Auth: ${e.message}');
    } finally {
      await secondaryApp?.delete();
    }
  }
}
