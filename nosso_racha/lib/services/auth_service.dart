import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  UserModel? _currentUser;
  bool _isLoading = true; // Começa true para verificar sessão inicial
  Object? _profileError;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _profileSubscription;
  String? _creatingProfileFor;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  Object? get profileError => _profileError;

  // CONSTRUTOR: Inicia a escuta da sessão imediatamente
  AuthService() {
    _authSubscription = _auth.authStateChanges().listen(
      (firebaseUser) => unawaited(_onAuthStateChanged(firebaseUser)),
      onError: (Object error, StackTrace stackTrace) =>
          _handleProfileError(error, stackTrace),
    );
  }

  // --- RECUPERAÇÃO AUTOMÁTICA DE SESSÃO ---
  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    await _profileSubscription?.cancel();
    if (_auth.currentUser?.uid != firebaseUser?.uid) return;
    _profileSubscription = null;
    _creatingProfileFor = null;
    if (_currentUser?.uid != firebaseUser?.uid) _currentUser = null;

    if (firebaseUser == null) {
      _currentUser = null;
      _profileError = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      _profileError = null;
      _isLoading = true;
      notifyListeners();
      _profileSubscription = _firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .snapshots()
          .listen(
            (snapshot) => unawaited(_applyUserSnapshot(snapshot, firebaseUser)),
            onError: (Object error, StackTrace stackTrace) =>
                _handleProfileError(error, stackTrace, firebaseUser.uid),
          );
    } catch (error, stackTrace) {
      _handleProfileError(error, stackTrace, firebaseUser.uid);
    }
  }

  Future<void> _applyUserSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    User firebaseUser,
  ) async {
    if (_auth.currentUser?.uid != firebaseUser.uid) return;

    if (!snapshot.exists) {
      if (_creatingProfileFor == firebaseUser.uid) return;
      _creatingProfileFor = firebaseUser.uid;
      try {
        final newUser = UserModel(
          uid: firebaseUser.uid,
          name: firebaseUser.displayName ?? 'Usuário',
          email: firebaseUser.email ?? '',
          status: 'active',
        );
        await snapshot.reference.set(newUser.toMap());
      } catch (error, stackTrace) {
        _handleProfileError(error, stackTrace, firebaseUser.uid);
      } finally {
        if (_creatingProfileFor == firebaseUser.uid) {
          _creatingProfileFor = null;
        }
      }
      return;
    }

    final data = snapshot.data();
    if (data == null) {
      _handleProfileError(
        StateError('O documento do perfil não contém dados.'),
        StackTrace.current,
      );
      return;
    }

    final user = UserModel.fromMap(snapshot.id, data);
    if (user.status == 'inactive' || user.status == 'suspended') {
      _currentUser = null;
      _isLoading = false;
      notifyListeners();
      await _auth.signOut();
      return;
    }

    _currentUser = user;
    _profileError = null;
    _isLoading = false;
    notifyListeners();
  }

  void _handleProfileError(
    Object error, [
    StackTrace? stackTrace,
    String? userId,
  ]) {
    if (userId != null && _auth.currentUser?.uid != userId) return;
    _profileError = error;
    _isLoading = false;
    debugPrint('Erro ao sincronizar perfil do usuário: $error');
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace);
    }
    notifyListeners();
  }

  // --- RECARREGAR USUÁRIO (ATUALIZAR PERMISSÕES SEM LOGOUT) ---
  Future<void> reloadUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return;

    try {
      _setLoading(true);
      _profileError = null;
      final doc = await _firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .get(const GetOptions(source: Source.server));
      await _applyUserSnapshot(doc, firebaseUser);
    } catch (error, stackTrace) {
      _handleProfileError(error, stackTrace, firebaseUser.uid);
      rethrow;
    } finally {
      if (_auth.currentUser?.uid == firebaseUser.uid && _isLoading) {
        _setLoading(false);
      }
    }
  }

  // --- LOGIN MANUAL ---
  Future<void> signIn(String email, String password) async {
    try {
      _setLoading(true);
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      await reloadUser();
    } on FirebaseAuthException catch (e) {
      String message = 'Erro ao fazer login';
      if (e.code == 'user-not-found') message = 'Usuário não encontrado.';
      if (e.code == 'wrong-password') message = 'Senha incorreta.';
      if (e.code == 'invalid-email') message = 'Email inválido.';
      _setLoading(false); // Só para loading se der erro, senão o listener trata
      throw Exception(message);
    } catch (e) {
      _setLoading(false);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    // O listener vai setar _currentUser = null automaticamente
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    unawaited(_profileSubscription?.cancel());
    super.dispose();
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    try {
      _setLoading(true);
      AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') throw Exception('Senha atual incorreta.');
      throw Exception('Erro ao trocar senha: ${e.message}');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') throw Exception('Email não cadastrado.');
      if (e.code == 'invalid-email') throw Exception('Email inválido.');
      throw Exception('Erro ao enviar email: ${e.message}');
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // Exemplo de método para login com o Google no AuthService
  Future<void> signInWithGoogle() async {
    try {
      _isLoading = true;
      notifyListeners();

      // Cria o provedor do Google
      GoogleAuthProvider googleProvider = GoogleAuthProvider();

      // Se estiver rodando na Web, o Firebase abre um pop-up automático
      // Se for mobile, ele usa o fluxo nativo integrado
      await FirebaseAuth.instance.signInWithPopup(googleProvider);
      await reloadUser();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }
}
