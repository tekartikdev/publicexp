import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_exp/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:tekartik_test_menu_flutter/test_menu_flutter.dart';

var counterDocPath = 'test/JeEfTtXFNMXru4T1CXDU_cloud_firestore_exp/test/doc';
var counterCollectionPath =
    'test/JeEfTtXFNMXru4T1CXDU_cloud_firestore_exp/test';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var app = await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  var firestore = FirebaseFirestore.instanceFor(app: app);

  /// Important to reproduce the issue. create 2 distinct references to the same document and collection
  /// This is typically the case in a flutter app when you have multiple screen
  /// listening to the same document or collection
  var ref1 = firestore.doc(counterDocPath);
  var ref2 = firestore.doc(counterDocPath);
  var collRef1 = firestore.collection(counterCollectionPath);
  var collRef2 = firestore.collection(counterCollectionPath);
  StreamSubscription? subscriptionDoc1;
  StreamSubscription? subscriptionDoc2;
  StreamSubscription? subscriptionColl1;
  StreamSubscription? subscriptionColl2;

  mainMenuFlutter(() {
    enter(() {
      write('Entering menu');
    });
    item('Cancel all listeners', () {
      subscriptionDoc1?.cancel();
      subscriptionDoc2?.cancel();
      subscriptionColl1?.cancel();
      subscriptionColl2?.cancel();
    });

    item('Setup listener 1 on doc/ref1', () {
      subscriptionDoc1?.cancel();
      subscriptionDoc1 = ref1.snapshots().listen((event) {
        write('listener 1: ${event.data()}');
      });
    });
    item('Setup listener 2 on doc/ref2', () {
      subscriptionDoc2?.cancel();
      subscriptionDoc2 = ref2.snapshots().listen((event) {
        write('listener 2: ${event.data()}');
      });
    });
    item('Setup listener 3 on coll/ref1', () {
      subscriptionColl1?.cancel();
      subscriptionColl1 = collRef1.snapshots().listen((event) {
        write('listener 3: ${event.docs.map((e) => e.id)}');
      });
    });
    item('Setup listener 4 on coll/ref2', () {
      subscriptionColl2?.cancel();
      subscriptionColl2 = collRef2.snapshots().listen((event) {
        write('listener 4: ${event.docs.map((e) => e.id)}');
      });
    });
    Future<void> incrementRef(DocumentReference<Map> ref) async {
      var snapshot = await ref.get();
      Object? rawValue;
      if (snapshot.exists) {
        rawValue = snapshot.data()?['value'];
      }
      var existingValue = rawValue is int ? rawValue : 0;

      var newData = {'value': existingValue + 1};
      write('newdData: $newData');
      await ref.set(newData);
    }

    item('Increment doc', () async {
      await incrementRef(ref1);
    });
  }, showConsole: true);
}
