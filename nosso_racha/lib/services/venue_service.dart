import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/venue_model.dart';

class VenueService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  VenueService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  Future<List<Venue>> getApprovedVenues() async {
    final snapshot = await _firestore
        .collection('venues')
        .where('status', isEqualTo: 'approved')
        .get();
    return snapshot.docs
        .map((document) => Venue.fromMap(document.id, document.data()))
        .toList();
  }

  Future<void> requestVenue({
    required String name,
    required String address,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Entre na sua conta para solicitar um novo local.');
    }

    await _firestore.collection('pending_venues').add({
      'name': name.trim(),
      'address': address.trim(),
      'created_by': user.uid,
      'requester_name': user.displayName,
      'requester_email': user.email,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    });
  }
}
