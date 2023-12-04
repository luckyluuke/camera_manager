import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';


class UserManager{

  User? _user;
  String? _userId;
  String? _phoneNumber;

  CollectionReference? collection;
  Future<DocumentSnapshot<Object?>>? querySnapshot;

  UserManager(){
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null){
      _userId = _user!.uid;
      _phoneNumber = _user!.phoneNumber;
    }
  }

  String? get userId => _userId;
  String? get phoneNumber => _phoneNumber;
  User? get details => _user;



  Future<dynamic> getValue(String fromCollection, String fromField, {String docId = ""}) async {
    dynamic value;

    collection = FirebaseFirestore.instance.collection(fromCollection);
    querySnapshot = collection!.doc(docId.isEmpty ? _userId : docId).get();

    //await collection!.doc(docId.isEmpty ? _userId : docId).get();

    await querySnapshot!.then((snapshot) {

      Map<String, dynamic>? data = snapshot.data() as Map<String, dynamic>?;
      if (data != null) value = snapshot.get(fromField); //data[fromField];
    });

    return value;
  }

  Future<Map> getMultipleValues(String fromCollection, List fromFields, {String docId = ""}) async {
    Map resultValues = {};

    collection = FirebaseFirestore.instance.collection(fromCollection);
    querySnapshot = collection!.doc(docId.isEmpty ? _userId : docId).get();

    await querySnapshot!.then((snapshot) {
      Map<String, dynamic>? data = snapshot.data() as Map<String, dynamic>?;
      if (data != null){
        fromFields.forEach((element) {
          resultValues[element] = data[element];
        });
      }

    });

    return resultValues;
  }

  Future<void> updateValue(String collectionName, String fieldName, dynamic withValue, {String docId = ""}) async {

    collection = FirebaseFirestore.instance.collection(collectionName);
    await collection!.doc(docId.isEmpty ? _userId : docId).update(
        {
          fieldName:withValue
        }
    );
  }

  Future<void> updateMultipleValues(String collectionName, Map<String, Object?> newValues, {String docId = "", bool fullPath = false}) async {
    collection = FirebaseFirestore.instance.collection(collectionName);

    if (!fullPath){
      await collection!.doc(docId.isEmpty ? _userId : docId).set(
          newValues
          ,
          SetOptions(merge: true)
      );
    }
    else
    {
      await collection!.doc(docId.isEmpty ? _userId : docId).update(
          newValues
          ,
      );
    }


  }

  Future<void> deleteElement(String collectionName, String docId) async {
    /*collection = FirebaseFirestore.instance.collection(collectionName);
    await collection!.doc(docId).delete();*/

    HttpsCallable callable = await FirebaseFunctions.instanceFor(app: FirebaseFunctions.instance.app, region: "europe-west1").httpsCallable("deleteElement");
    var result = await callable.call(
        {
          'collectionName':collectionName,
          'docId':docId,
          'userId':_userId
        }
    );

    if ("success" == result.data["status"]){
      if ("allStripeConnectAccounts" == collectionName){
        updateValue("allUsers", "accountId", "");
      }
    }
    else{
      debugPrint("ERROR: Failed to delete current element !");
    }

  }

  Future<dynamic> checkIfDocExists(String table, String docID, {String specificField = "", bool retrieveDoc = false}) async {

    /*bool exist=false;
    try {
      await FirebaseFirestore.instance.doc("$table/$docID").get().then((doc) {
        exist = doc.exists;
      });
      return exist;
    } catch (e) {
      // If any error
      return exist;
    }*/

    HttpsCallable callable = await FirebaseFunctions.instanceFor(app: FirebaseFunctions.instance.app, region: "europe-west1").httpsCallable("getResultWhere");
    var result = await callable.call(
        {
          'limit':1,
          'collectionName':table,
          'comparedField': specificField.isEmpty ? '__name__' : specificField,
          'comparisonSign': '==',
          'toValue':docID
        }
    );

    //final listOfPseudos = result.data!;
    if(retrieveDoc){
      return result.data;
    }else{
      final exist = (result.data == null ? false : true);
      return exist;
    }


  }

  Future<HttpsCallableResult> callCloudFunction(String cloudFunctionName, Map parameters) async {
    HttpsCallable callable = await FirebaseFunctions.instanceFor(app: FirebaseFunctions.instance.app, region: "europe-west1").httpsCallable(cloudFunctionName);
    HttpsCallableResult result = await callable.call(parameters);
    return result;
  }

  Future<dynamic> getResult(String fromCollection, String singleDocument) async {

    HttpsCallable callable = await FirebaseFunctions.instanceFor(app: FirebaseFunctions.instance.app, region: "europe-west1").httpsCallable("getResult");
    var tmpResult = await callable.call(
        {
          'singleDocument': singleDocument,
          'collectionName':fromCollection,
        }
    );
    /*DocumentSnapshot test = tmpResult.data;*/
    //print(tmpResult.data);

    //debugPrint("DEBUG_LOG getResult tmpResult.data=" + tmpResult.data.toString());
    return (tmpResult.data != null) ? tmpResult.data : null;
  }

  /*Future<dynamic> getAllowedResult(String fromCollection, String singleDocument) async {
    var result = null;

    CollectionReference allScheduledLives = FirebaseFirestore.instance.collection(fromCollection);
    var querySnapshot = await allScheduledLives.doc().get();

    if (tmpResult.data != null){
      result = tmpResult.data;
    }

    return result;
  }*/

}