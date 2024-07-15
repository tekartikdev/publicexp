import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_exp/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:tekartik_test_menu_flutter/test_menu_flutter.dart';

var counterDocPath = 'test/JeEfTtXFNMXru4T1CXDU_cloud_firestore_exp';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var app = await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  var firestore = FirebaseFirestore.instanceFor(app: app);
  var ref = firestore.doc(counterDocPath);
  StreamSubscription? subscription1;
  StreamSubscription? subscription2;
  mainMenuFlutter(() {
    item('Setup listener 1', () {
      subscription1?.cancel();
      subscription1 = ref.snapshots().listen((event) {
        write('listener 1: ${event.data()}');
      });
    });
    item('Setup listener 2', () {
      subscription2?.cancel();
      subscription2 = ref.snapshots().listen((event) {
        write('listener 2: ${event.data()}');
      });
    });
    item('Cancel listener 1', () {
      subscription1?.cancel();
    });
    item('Cancel listener 2', () {
      subscription2?.cancel();
    });
    item('Increment', () async {
      var snapshot = await ref.get();
      Object? rawValue;
      if (snapshot.exists) {
        rawValue = snapshot.data()?['value'];
      }
      var existingValue = rawValue is int ? rawValue : 0;

      var newData = {'value': existingValue + 1};
      write('newData: $newData');
      await ref.set(newData);
    });
  }, showConsole: true);
}
