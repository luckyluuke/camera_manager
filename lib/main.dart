import 'package:camera/camera.dart';
import 'package:camera_manager/CameraManager.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  final List<CameraDescription> _cameras = await availableCameras();
  runApp(MyApp(_cameras));
}

class MyApp extends StatelessWidget {

  final List<CameraDescription> _cameras;
  const MyApp(this._cameras,{super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {


    return MaterialApp(
      title: 'Camera Feature',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: CameraExampleHome(_cameras,true,false)
    );
  }
}
