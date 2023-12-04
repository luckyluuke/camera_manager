// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:camera_manager/flying_dots_animation.dart';
import 'package:camera_manager/UserManager.dart';
import 'package:square_percent_indicater/square_percent_indicater.dart';
import 'package:video_player/video_player.dart' as vp;
import 'package:path/path.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';

/// Camera example home widget.
class CameraExampleHome extends StatefulWidget {
  /// Default Constructor
  CameraExampleHome(this._cameras, this.isHelper, this.isPicture);
  final List<CameraDescription> _cameras;
  final bool isHelper;
  final bool isPicture;

  @override
  State<CameraExampleHome> createState() {
    return _CameraExampleHomeState(this._cameras,this.isHelper,this.isPicture);
  }
}

/// Returns a suitable camera icon for [direction].
IconData getCameraLensIcon(CameraLensDirection direction) {
  switch (direction) {
    case CameraLensDirection.back:
      return Icons.camera_rear;
    case CameraLensDirection.front:
      return Icons.camera_front;
    case CameraLensDirection.external:
      return Icons.camera;
  }
  // This enum is from a different package, so a new value could be added at
  // any time. The example should keep working if that happens.
  // ignore: dead_code
  return Icons.camera;
}

void _logError(String code, String? message) {
  // ignore: avoid_print
  debugPrint('Error: $code${message == null ? '' : '\nError Message: $message'}');
}

class _CameraExampleHomeState extends State<CameraExampleHome>
    with WidgetsBindingObserver, TickerProviderStateMixin {

  _CameraExampleHomeState(this._cameras,this.isHelper,this.isPicture);

  double _progress = 0.0;
  Timer? progressTimer;
  CameraController? controller;
  XFile? imageFile;
  XFile? videoFile;
  vp.VideoPlayerController? videoController;
  VoidCallback? videoPlayerListener;
  bool enableAudio = true;
  late AnimationController _flashModeControlRowAnimationController;
  late Animation<double> _flashModeControlRowAnimation;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentScale = 1.0;
  double _baseScale = 1.0;
  List<CameraDescription> _cameras;
  bool cameraSwitched = true;
  UserManager _userManager = UserManager();
  final bool isHelper;
  bool imageIsLoading = false;
  bool isPicture = true;
  Timer? _recordingTimer;
  XFile? mediaFile;
  VideoPlayerController? _controller;


  // Counting pointers (number of user fingers on screen)
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    initializeCamera();

    _flashModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _flashModeControlRowAnimation = CurvedAnimation(
      parent: _flashModeControlRowAnimationController,
      curve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashModeControlRowAnimationController.dispose();
    controller!.dispose();

    if(videoController != null){
      videoController!.dispose();
      videoController = null;
    }

    if(_recordingTimer != null){
      _recordingTimer!.cancel();
      _recordingTimer = null;
    }

    if(_controller != null){
      _controller!.dispose();
      _controller = null;
    }

    if(controller != null){
      controller!.dispose();
      controller = null;
    }

    if(progressTimer != null){
      progressTimer?.cancel();
      progressTimer = null;
    }

    super.dispose();
  }

  // #docregion AppLifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCameraController(cameraController.description);
    }
  }
  // #enddocregion AppLifecycle

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isPicture ? 'Photo de profil' : "Vidéo de présentation",
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.yellow,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded ,
            color: Colors.black,
            size: 30,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              width: MediaQuery.of(context).size.width,
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(
                  color:
                  controller != null && controller!.value.isRecordingVideo
                      ? Colors.redAccent
                      : Colors.grey,
                  width: 5.0,
                ),
              ),
              child: SquarePercentIndicator(
                width: MediaQuery.of(context).size.width,
                //height: MediaQuery.of(context).size.height/4,
                startAngle: StartAngle.topLeft,
                //reverse: true,
                borderRadius: 0,
                shadowWidth: 1.5,
                progressWidth: 15,
                shadowColor: Colors.grey,
                progressColor: Colors.greenAccent,
                progress: _progress,
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Center(
                    child: _cameraPreviewWidget(),
                  ),
                ),
              ),
            ),
          ),
          //_captureControlRowWidget(),
          _modeControlRowWidget(),
          Padding(
            padding: const EdgeInsets.all(5.0),
            child: Row(
              children: <Widget>[
                _thumbnailWidget(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Display the preview from the camera (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return const Text(
        'Préparation...',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      return Listener(
        onPointerDown: (_) => _pointers++,
        onPointerUp: (_) => _pointers--,
        child: CameraPreview(
          controller!,
          child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _handleScaleStart,
                  onScaleUpdate: _handleScaleUpdate,
                  onTapDown: (TapDownDetails details) =>
                      onViewFinderTap(details, constraints),
                );
              }),
        ),
      );
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    // When there are not exactly two fingers on screen don't scale
    if (controller == null || _pointers != 2) {
      return;
    }

    _currentScale = (_baseScale * details.scale)
        .clamp(_minAvailableZoom, _maxAvailableZoom);

    await controller!.setZoomLevel(_currentScale);
  }

  /// Display the thumbnail of the captured image or video.
  Widget _thumbnailWidget() {
    final vp.VideoPlayerController? localVideoController = videoController;



    return Expanded(
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (localVideoController == null && imageFile == null)
              Container()
            else
              SizedBox(
                width: 64.0,
                height: 64.0,
                child: (localVideoController == null)
                    ? (
                    // The captured image on the web contains a network-accessible URL
                    // pointing to a location within the browser. It may be displayed
                    // either with Image.network or Image.memory after loading the image
                    // bytes to memory.
                    kIsWeb
                        ? Image.network(imageFile!.path)
                        : Image.file(File(imageFile!.path)))
                    : Container(
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.pink)),
                  child: Center(
                    child: AspectRatio(
                        aspectRatio:
                        localVideoController.value.aspectRatio,
                        child: vp.VideoPlayer(localVideoController)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Display a bar with buttons to change the flash and exposure modes
  Widget _modeControlRowWidget() {

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              RawMaterialButton(
                onPressed: controller != null ? onFlashModeButtonPressed : null,
                child: Icon(Icons.flash_on, color: Colors.white),
                shape: CircleBorder(),
                //elevation: 2.0,
                fillColor:Colors.blueAccent,
                padding: const EdgeInsets.all(10),
              ),
              /*IconButton(
                icon: const Icon(Icons.flash_on),
                color: Colors.blue,
                onPressed: controller != null ? onFlashModeButtonPressed : null,
              ),*/
              // The exposure and focus mode are currently not supported on the web.
              ...!kIsWeb
                  ? <Widget>[
                RawMaterialButton(
                onPressed: controller != null &&
                    controller!.value.isInitialized &&
                    !controller!.value.isRecordingVideo &&
                    !imageIsLoading
                    ? onTakePictureButtonPressed
                    : null,
                child: isPicture ?
                (!imageIsLoading ? Icon(Icons.camera_alt , color: Colors.white) : TwoFlyingDots(dotsSize: 15, firstColor: Colors.blue, secondColor: Colors.red))
                :
                Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: !imageIsLoading ? Colors.red : Colors.black,
                      borderRadius: !imageIsLoading ? BorderRadius.all(Radius.circular(30)) : null,
                    )
                ),
                //!imageIsLoading ? Icon(isPicture ? Icons.camera_alt : Icons.fiber_manual_record, color: isPicture ? Colors.white : Colors.red) : TwoFlyingDots(dotsSize: 15, firstColor: Colors.blue, secondColor: Colors.red),
                shape: CircleBorder(
                  side: isPicture ? BorderSide.none : BorderSide(width: 5,color: Colors.red)
                ),
                elevation: 2.0,
                fillColor: isPicture ? Colors.green : Colors.white,
                padding: EdgeInsets.all(20),
                ),
              ]
                  : <Widget>[],
              _cameraTogglesRowWidget(),
            ],
          ),
        ),
        _flashModeControlRowWidget(),
        //_exposureModeControlRowWidget(),
        //_focusModeControlRowWidget(),
      ],
    );
  }

  Widget _flashModeControlRowWidget() {
    return SizeTransition(
      sizeFactor: _flashModeControlRowAnimation,
      child: ClipRect(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.flash_off),
              color: controller?.value.flashMode == FlashMode.off
                  ? Colors.orange
                  : Colors.blue,
              onPressed: controller != null
                  ? () => onSetFlashModeButtonPressed(FlashMode.off)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.flash_auto),
              color: controller?.value.flashMode == FlashMode.auto
                  ? Colors.orange
                  : Colors.blue,
              onPressed: controller != null
                  ? () => onSetFlashModeButtonPressed(FlashMode.auto)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.flash_on),
              color: controller?.value.flashMode == FlashMode.always
                  ? Colors.orange
                  : Colors.blue,
              onPressed: controller != null
                  ? () => onSetFlashModeButtonPressed(FlashMode.always)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.highlight),
              color: controller?.value.flashMode == FlashMode.torch
                  ? Colors.orange
                  : Colors.blue,
              onPressed: controller != null
                  ? () => onSetFlashModeButtonPressed(FlashMode.torch)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Display a row of toggle to select the camera (or a message if no camera is available).
  Widget _cameraTogglesRowWidget() {

    void onChanged() {

      if(_cameras.length > 1){

        cameraSwitched = !cameraSwitched;
        CameraDescription cameraDescriptionUpdate;

        if (cameraSwitched){
          cameraDescriptionUpdate = _cameras[1];
        }else {
          cameraDescriptionUpdate = _cameras[0];
        }

        onNewCameraSelected(cameraDescriptionUpdate);
      }

    }

    if (_cameras.isEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        showInSnackBar('Aucune caméra trouvée.');
      });

      return const Text('Vide');
    }

    return RawMaterialButton(
      onPressed: onChanged,
      child: Icon(Icons.loop, color: Colors.white),
      shape: CircleBorder(),
      elevation: 2.0,
      fillColor:Colors.purple,
      padding: const EdgeInsets.all(10),
    );

  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(this.context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (controller == null) {
      return;
    }

    final CameraController cameraController = controller!;

    final Offset offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  Future<void> onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      return controller!.setDescription(cameraDescription);
    } else {
      return _initializeCameraController(cameraDescription);
    }
  }

  initializeCamera(){
    CameraDescription frontCam;
    if (_cameras.length > 1){
      frontCam = _cameras[1];
    }else {
      frontCam = _cameras[0];
    }

    _initializeCameraController(frontCam);
  }

  Future<void> _initializeCameraController(
      CameraDescription cameraDescription) async {

    final CameraController cameraController = CameraController(
      cameraDescription,
      kIsWeb ? ResolutionPreset.max : ResolutionPreset.high,
      enableAudio: isPicture ? false : true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    controller = cameraController;

    // If the controller is updated then update the UI.
    cameraController.addListener(() {
      if (mounted) {
        setState(() {});
      }
      if (cameraController.value.hasError) {
        showInSnackBar(
            "Il y'a un problème avec la caméra");
        /*showInSnackBar(
            'Camera error ${cameraController.value.errorDescription}');*/
      }
    });

    try {
      await cameraController.initialize();
      await Future.wait(<Future<Object?>>[
        // The exposure mode is currently not supported on the web.
        cameraController
            .getMaxZoomLevel()
            .then((double value) => _maxAvailableZoom = value),
        cameraController
            .getMinZoomLevel()
            .then((double value) => _minAvailableZoom = value),
      ]);
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          showInSnackBar('Tu as rejeté l\'accès à la caméra.');
          break;
        case 'CameraAccessDeniedWithoutPrompt':
        // iOS only
          showInSnackBar("Allez dans les réglages de votre appareil pour donner l\'autorisation à l'application d'accéder à la caméra.");
          break;
        case 'CameraAccessRestricted':
        // iOS only
          showInSnackBar("L\'accès à la caméra est restreint.");
          break;
        case 'AudioAccessDenied':
          showInSnackBar("Tu as rejeté l'accès audio.");
          break;
        case 'AudioAccessDeniedWithoutPrompt':
        // iOS only
          showInSnackBar("Allez dans les réglages de votre appareil pour donner l\'autorisation à l'application d'accéder à l'audio'.");
          break;
        case 'AudioAccessRestricted':
        // iOS only
          showInSnackBar("L\'accès à l'audio est restreint.");
          break;
        default:
          _showCameraException(e);
          break;
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  initProgressTimer(){
    if(progressTimer != null){
      progressTimer?.cancel();
      progressTimer = null;
    }

    progressTimer = Timer.periodic(Duration(milliseconds: 14), (timer) {

      if((progressTimer != null) && (_progress == 1.0)){
        progressTimer!.cancel();
        progressTimer = null;
      }else{
        double updatedValue = _progress + 0.001;//0.0000055;
        setState(() {
          _progress = (updatedValue < 1.0) ? updatedValue : 1.0;
        });
      }
    });
  }

  Future<void> onTakePictureButtonPressed() async {

    setState(() {
      _progress = 0.0;
      imageIsLoading = true;
    });

    await takePicture();
  }

  Future<void> saveFile() async {
    if (mounted) {

      if (mediaFile != null) {

        setState(() {
          imageIsLoading = false;
          _progress = 0.0;
        });

        bool result = await saveMediaAndQuit(mediaFile);
        if (result){
          Navigator.pop(this.context);
        }

      }else{
        setState(() {
          imageIsLoading = false;
        });
      }
    }else{
      setState(() {
        imageIsLoading = false;
      });
    }
  }

  Future<String?> uploadVideo(File file) async {
    var videoUrl = "";
    var accessToken = "82d36644e61d274c8536bc836d97f41c";
    var baseUrl = "https://api.vimeo.com/me/videos/";

    final response = await http.post(
      Uri.parse(baseUrl),
      headers: {
        'Authorization': 'bearer $accessToken',
        'Content-Type': 'application/json',
        'Accept': 'application/vnd.vimeo.*+json;version=3.4',
      },

      body: jsonEncode({
        "upload": {
          "approach": "tus",
          "size": file.lengthSync(),
        },
        "name": _userManager.userId,
      }),
    );

    final responseJson = jsonDecode(response.body);
    // final responseJson = jsonDecode(response.data);
    String uploadLink = responseJson['upload']['upload_link'];

    // 2. Upload the video file
    final tusResponse = await http.patch(
      Uri.parse(uploadLink),
      headers: {
        'Tus-Resumable': '1.0.0',
        'Upload-Offset': '0',
        'Content-Type': 'application/offset+octet-stream',
      },
      body: file.readAsBytesSync(),
    );

    // 3. Check the upload status
    final statusResponse = await http.get(
      Uri.parse(uploadLink),
      headers: {
        'Tus-Resumable': '1.0.0',
      },
    );

    if (response.statusCode == 200) {
      videoUrl = responseJson['link'].toString();
    }

    return videoUrl;
  }

  Future<void> deleteVideo(String videoId) async {
    var accessToken = "82d36644e61d274c8536bc836d97f41c";
    var baseUrl = "https://api.vimeo.com/videos/" + videoId;
    await http.delete(
      Uri.parse(baseUrl),
      headers: {
        'Authorization': 'bearer $accessToken',
        'Content-Type': 'application/json',
        'Accept': 'application/vnd.vimeo.*+json;version=3.4',
      },
    );

  }

  Future<bool> showValidationMediaDialog(BuildContext currentContext, File? file) async {

    bool result = false;
    bool uploading = false;

    if(!isPicture){
      VolumeController().setVolume(0.5,showSystemUI: false);
    }

    _controller = VideoPlayerController.file(file!);
    _controller!.addListener(() async {
      if(!_controller!.value.isPlaying && (_controller!.value.position < _controller!.value.duration) && (_controller!.value.position > Duration.zero)){
        await _controller!.play();
      }else if (_controller!.value.position == _controller!.value.duration){
        await _controller!.seekTo(Duration.zero);
      }
    });

    await _controller!.initialize();


    await showDialog(
        barrierDismissible: true,
        context: currentContext,
        builder: (context) {

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _controller!.play();
          });

          return StatefulBuilder(
            builder: (context,refresher) {
              return AlertDialog(
                title: Text(
                    "Valider cette vidéo ?",
                    style: GoogleFonts.inter(
                      color: Colors.grey,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign:TextAlign.center
                ),
                content: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                    VideoProgressIndicator(_controller!, allowScrubbing: true),
                    if(uploading)
                      AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: Container(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                child: Text(
                                  "Sauvegarde\nen cours",
                                    style: GoogleFonts.inter(
                                      color: Colors.black,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign:TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TwoFlyingDots(dotsSize: 30, firstColor: Colors.yellow, secondColor: Colors.red)
                            ],
                          ),
                        ),
                      )
                  ],
                ),
                actions: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      ElevatedButton(
                          onPressed:()async {
                            if(!uploading){
                              refresher((){
                                uploading = true;
                              });

                              await processFile(file);
                              result = true;
                              uploading = false;
                              Navigator.pop(context);
                            }
                          },
                          child: Text(
                            "Oui",
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                      ),
                      ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                          },
                          child: Text("Non",
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),)
                      ),
                    ],
                  ),
                ],
              );
            }
          );
        }
    );

    if (_controller != null){
      _controller!.dispose();
      _controller = null;
    }

    return result;
  }

  Future<void> processFile(File file) async {
    if(isPicture){
      final filename = basename(file.path);
      Reference ref = FirebaseStorage.instance.ref();
      String? uid = _userManager.userId;
      TaskSnapshot addImg = await ref.child("users_avatars/$uid/$filename").putFile(file);
      String m_returnURL = await addImg.ref.getDownloadURL();
      String oldAvatarImg = await _userManager.getValue("allUsers", "avatar_url");
      bool isInDefaultDirectory = oldAvatarImg.contains("default_images") && oldAvatarImg.contains("default_avatar.png");

      if (!isInDefaultDirectory) FirebaseStorage.instance.refFromURL(oldAvatarImg).delete();

      await _userManager.updateValue("allUsers", "avatar_url", m_returnURL);

      if (isHelper){
        await _userManager.updateValue("allHelpers", "avatar_url", m_returnURL);
      }
    }else{

      var videoUrl = await uploadVideo(file);

      if(videoUrl!.isNotEmpty){

        String oldVideo = await _userManager.getValue("allHelpers", "video_url");

        if(oldVideo.isNotEmpty){
          String? videoId = oldVideo.split("/").last;
          await deleteVideo(videoId);
        };

        await _userManager.updateValue("allHelpers", "video_url", videoUrl);
        await _userManager.updateValue("allUsers", "video_url", videoUrl);
      }
    }
  }

  Future<bool> saveMediaAndQuit(XFile? imageFile) async {

    bool result = false;

    var imageFilePath = imageFile!.path;

    var createdTime = DateTime.now().microsecondsSinceEpoch.toString();
    var targetPath = dirname(imageFilePath) + createdTime.toString() + extension(imageFilePath);

    XFile? imageWithCompression = isPicture ? await FlutterImageCompress.compressAndGetFile(
      imageFilePath,
      targetPath,
      quality: (controller!.resolutionPreset == ResolutionPreset.high) ? 60 : 90,
      rotate: 0,
    ) : null;

    File? image = File(isPicture ? imageWithCompression!.path : imageFilePath);

    result = await showValidationMediaDialog(this.context, image);

    return result;
  }

  void onFlashModeButtonPressed() {
    if (_flashModeControlRowAnimationController.value == 1) {
      _flashModeControlRowAnimationController.reverse();
    } else {
      _flashModeControlRowAnimationController.forward();
    }
  }

  void onSetFlashModeButtonPressed(FlashMode mode) {
    setFlashMode(mode).then((_) {
      if (mounted) {
        setState(() {});
      }

      showInSnackBar("Le mode flash a été mis à jour.");

      //showInSnackBar('Flash mode set to ${mode.toString().split('.').last}');
    });
  }


  Future<void> setFlashMode(FlashMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setFlashMode(mode);
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<XFile?> takePicture() async {
    final CameraController? cameraController = controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Sélectionnes une caméra d\'abord !');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    if (cameraController.value.isRecordingVideo) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {

      if(isPicture){
        mediaFile = await cameraController.takePicture();
        await saveFile();
      }else{

        await cameraController.startVideoRecording();
        initProgressTimer();
        _recordingTimer = Timer(Duration(seconds: 15), () async {

          if(progressTimer != null){
            progressTimer?.cancel();
            progressTimer = null;
          }
          mediaFile  = await cameraController.stopVideoRecording();
          await saveFile();
        });

      }

      /*final XFile file = await cameraController.takePicture();
      return file;*/
    } on CameraException catch (e) {
      _showCameraException(e);
      //return null;
    }
  }

  void _showCameraException(CameraException e) {
    _logError(e.code, e.description);
    showInSnackBar(
        "Problème non identifié.");
    //showInSnackBar('Error: ${e.code}\n${e.description}');
  }
}