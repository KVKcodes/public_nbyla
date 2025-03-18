import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Sign up with email and password
  Future<UserCredential> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      if (password.isEmpty) {
        throw 'Password cannot be empty';
      }
      
      final trimmedEmail = email.trim().toLowerCase();
      
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );

      await userCredential.user!.updateDisplayName(name);

      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'name': name,
        'email': trimmedEmail,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });

      await userCredential.user!.reload();
      
      return userCredential;
    } on FirebaseAuthException catch (e) {
      print('FirebaseAuthException: ${e.code} - ${e.message}');
      if (e.code == 'weak-password') {
        throw 'Password is too weak';
      } else if (e.code == 'email-already-in-use') {
        throw 'An account already exists for this email';
      }
      throw e.message ?? 'An error occurred during sign up';
    }
  }

  // Sign in with email and password
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      print('Auth Service - Email: $email');
      print('Auth Service - Password length: ${password.length}');
      
      final cleanEmail = email.trim().toLowerCase();
      
      if (password.isEmpty) {
        throw 'Password cannot be empty';
      }

      print('Attempting Firebase sign in...');
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      print('Firebase sign in successful');

      // Check if user document exists
      final userDoc = await _firestore.collection('users').doc(userCredential.user!.uid).get();
      
      if (userDoc.exists) {
        // Update last login for existing user
        await _firestore.collection('users').doc(userCredential.user!.uid).update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new user document if it doesn't exist
        await _firestore.collection('users').doc(userCredential.user!.uid).set({
          'name': userCredential.user!.displayName ?? 'User',
          'email': cleanEmail,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
        });
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      print('FirebaseAuthException: ${e.code} - ${e.message}');
      if (e.code == 'wrong-password') {
        throw 'Incorrect password';
      } else if (e.code == 'user-not-found') {
        throw 'No user found with this email';
      } else if (e.code == 'invalid-email') {
        throw 'Please enter a valid email address';
      } else if (e.code == 'missing-password') {
        throw 'Please enter your password';
      }
      throw e.message ?? 'An error occurred during sign in';
    } catch (e) {
      print('Other error: $e');
      throw e.toString();
    }
  }

  // Sign in with Google
  Future<UserCredential> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw 'Google Sign In was cancelled';

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await _auth.signInWithCredential(credential);

      // Create/Update user document in Firestore
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'name': userCredential.user!.displayName,
        'email': userCredential.user!.email,
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return userCredential;
    } catch (e) {
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();
} 