// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:gap/gap.dart';
import 'package:loooans/utils/screen_helpers.dart';

/// Camera example home widget.
class LoooansCamera extends StatefulWidget {
  /// Default Constructor
  const LoooansCamera({required this.cameras, super.key});

  final List<CameraDescription> cameras;

  @override
  State<LoooansCamera> createState() {
    return _LoooansCameraState();
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
  debugPrint(
    'Error: $code${message == null ? '' : '\nError Message: $message'}',
  );
}

class _LoooansCameraState extends State<LoooansCamera>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? controller;
  XFile? imageFile;
  late AnimationController _flashModeControlRowAnimationController;
  late Animation<double> _flashModeControlRowAnimation;
  late AnimationController _focusModeControlRowAnimationController;
  late Animation<double> _focusModeControlRowAnimation;
  double _minAvailableZoom = 1;
  double _maxAvailableZoom = 1;
  double _currentScale = 1;
  double _baseScale = 1;

  // Counting pointers (number of user fingers on screen)
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _flashModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _flashModeControlRowAnimation = CurvedAnimation(
      parent: _flashModeControlRowAnimationController,
      curve: Curves.easeInCubic,
    );
    _focusModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _focusModeControlRowAnimation = CurvedAnimation(
      parent: _focusModeControlRowAnimationController,
      curve: Curves.easeInCubic,
    );
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _flashModeControlRowAnimationController.dispose();
    await controller?.dispose();
    super.dispose();
  }

  // #docregion AppLifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cameraController = controller;

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
    final screenSize = MediaQuery.sizeOf(context);
    var viewFinderContainerSize = screenSize.shortestSide;

    if (viewFinderContainerSize > 500) {
      viewFinderContainerSize = 500;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: viewFinderContainerSize,
          height: viewFinderContainerSize,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(
              color: controller != null && controller!.value.isRecordingVideo
                  ? Colors.redAccent
                  : Colors.grey,
              width: 3,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: Center(
              child: imageFile == null ? _cameraPreviewWidget() : _image(),
            ),
          ),
        ),
        const Gap(16),
        if (imageFile == null) ...[
          _captureControlRowWidget(),
          // _modeControlRowWidget(),
          const Gap(8),
          Padding(
            padding: const EdgeInsets.all(5),
            child: Row(
              children: <Widget>[
                _cameraTogglesRowWidget(),
                // _thumbnailWidget(),
              ],
            ),
          ),
        ] else
          _showUseRetakeButtons(),
      ],
    );
  }

  /// Display the preview from the camera (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    final cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return const Text(
        'Choose a camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
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
            },
          ),
        ),
      );
    }
  }

  Widget _image() {
    if (imageFile == null) {
      return Container();
    }

    return FutureBuilder(
      future: imageFile!.readAsBytes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container();
        }

        return Image.memory(snapshot.data!);
      },
    );
  }

  Widget _showUseRetakeButtons() {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              padding: const EdgeInsets.symmetric(
                vertical: 16,
              ),
            ),
            onPressed: () {
              setState(() {
                imageFile = null;
              });
            },
            child: const Icon(
              Icons.refresh_rounded,
              size: 32,
            ),
          ),
        ),
        const Gap(16),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.green1,
              padding: const EdgeInsets.symmetric(
                vertical: 16,
              ),
            ),
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pop(imageFile);
            },
            child: const Icon(
              Icons.check_rounded,
              size: 32,
            ),
          ),
        ),
      ],
    );
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
    return Expanded(
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 64,
              height: 64,
              child: // The captured image on the web contains a network-accessible URL
                  // pointing to a location within the browser. It may be displayed
                  // either with Image.network or Image.memory after loading the image
                  // bytes to memory.
                  kIsWeb
                      ? Image.network(imageFile!.path)
                      : Image.file(File(imageFile!.path)),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.flash_on),
              color: Colors.blue,
              onPressed: controller != null ? onFlashModeButtonPressed : null,
            ),
            // The exposure and focus mode are currently not supported on the web.
            ...!kIsWeb
                ? <Widget>[
                    IconButton(
                      icon: const Icon(Icons.filter_center_focus),
                      color: Colors.blue,
                      onPressed:
                          controller != null ? onFocusModeButtonPressed : null,
                    ),
                  ]
                : <Widget>[],

            IconButton(
              icon: Icon(
                controller?.value.isCaptureOrientationLocked ?? false
                    ? Icons.screen_lock_rotation
                    : Icons.screen_rotation,
              ),
              color: Colors.blue,
              onPressed: controller != null
                  ? onCaptureOrientationLockButtonPressed
                  : null,
            ),
          ],
        ),
        _flashModeControlRowWidget(),
        _focusModeControlRowWidget(),
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

  Widget _focusModeControlRowWidget() {
    final styleAuto = TextButton.styleFrom(
      foregroundColor: controller?.value.focusMode == FocusMode.auto
          ? Colors.orange
          : Colors.blue,
    );
    final styleLocked = TextButton.styleFrom(
      foregroundColor: controller?.value.focusMode == FocusMode.locked
          ? Colors.orange
          : Colors.blue,
    );

    return SizeTransition(
      sizeFactor: _focusModeControlRowAnimation,
      child: ClipRect(
        child: ColoredBox(
          color: Colors.grey.shade50,
          child: Column(
            children: <Widget>[
              const Center(
                child: Text('Focus Mode'),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  TextButton(
                    style: styleAuto,
                    onPressed: controller != null
                        ? () => onSetFocusModeButtonPressed(FocusMode.auto)
                        : null,
                    onLongPress: () {
                      if (controller != null) {
                        controller!.setFocusPoint(null);
                      }
                      showInSnackBar('Resetting focus point');
                    },
                    child: const Text('AUTO'),
                  ),
                  TextButton(
                    style: styleLocked,
                    onPressed: controller != null
                        ? () => onSetFocusModeButtonPressed(FocusMode.locked)
                        : null,
                    child: const Text('LOCKED'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Display the control bar with buttons to take pictures and record videos.
  Widget _captureControlRowWidget() {
    final cameraController = controller;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                vertical: 16,
              ),
              backgroundColor: AppColors.green1,
            ),
            onPressed: cameraController != null &&
                    cameraController.value.isInitialized &&
                    !cameraController.value.isRecordingVideo
                ? onTakePictureButtonPressed
                : null,
            child: Icon(
              Icons.camera_alt,
              size: 32,
              color: cameraController != null &&
                      cameraController.value.isInitialized &&
                      !cameraController.value.isRecordingVideo
                  ? AppColors.black
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  /// Display a row of toggle to select the camera (or a message if no camera is available).
  Widget _cameraTogglesRowWidget() {
    // final toggles = <Widget>[];

    void onChanged(CameraDescription? description) {
      if (description == null) {
        return;
      }

      onNewCameraSelected(description);
    }

    if (widget.cameras.isEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        showInSnackBar('No camera found.');
      });
      return const Text('None');
    } else {
      // for (final (i, cameraDescription) in widget.cameras.indexed) {
      //   toggles.add(
      //     Container(
      //       width: 200,
      //       child: RadioListTile<CameraDescription>(
      //         title: Row(
      //           mainAxisSize: MainAxisSize.min,
      //           children: [
      //             Icon(
      //               getCameraLensIcon(cameraDescription.lensDirection),
      //             ),
      //             Text('Camera ${i + 1}'),
      //           ],
      //         ),
      //         groupValue: controller?.description,
      //         value: cameraDescription,
      //         onChanged: onChanged,
      //       ),
      //     ),
      //   );
      // }
    }

    return Row(
      children: [
        const Text('Camera:'),
        const Gap(16),
        DropdownMenu(
          dropdownMenuEntries:
              widget.cameras.mapIndexed((i, cameraDescription) {
            return DropdownMenuEntry(
              value: cameraDescription,
              label: 'Camera ${i + 1}',
              leadingIcon:
                  Icon(getCameraLensIcon(cameraDescription.lensDirection)),
            );
          }).toList(),
          onSelected: onChanged,
        ),
      ],
    );
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (controller == null) {
      return;
    }

    final cameraController = controller!;

    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setFocusPoint(offset);
  }

  Future<void> onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      return controller!.setDescription(cameraDescription);
    } else {
      return _initializeCameraController(cameraDescription);
    }
  }

  Future<void> _initializeCameraController(
    CameraDescription cameraDescription,
  ) async {
    final cameraController = CameraController(
      cameraDescription,
      kIsWeb ? ResolutionPreset.max : ResolutionPreset.medium,
      imageFormatGroup: ImageFormatGroup.jpeg,
      enableAudio:
          false, // We are not recording videos at the moment so, disable audio.
    );

    controller = cameraController;

    // If the controller is updated then update the UI.
    cameraController.addListener(() {
      if (mounted) {
        setState(() {});
      }
      if (cameraController.value.hasError) {
        showInSnackBar(
          'Camera error ${cameraController.value.errorDescription}',
        );
      }
    });

    try {
      await cameraController.initialize();
      await Future.wait(<Future<Object?>>[
        // The exposure mode is currently not supported on the web.
        ...!kIsWeb ? <Future<Object?>>[] : <Future<Object?>>[],
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
          showInSnackBar('You have denied camera access.');
        case 'CameraAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable camera access.');
        case 'CameraAccessRestricted':
          // iOS only
          showInSnackBar('Camera access is restricted.');
        case 'AudioAccessDenied':
          showInSnackBar('You have denied audio access.');
        case 'AudioAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable audio access.');
        case 'AudioAccessRestricted':
          // iOS only
          showInSnackBar('Audio access is restricted.');
        default:
          _showCameraException(e);
      }
    }

    if (mounted) {
      if (widget.cameras.isNotEmpty) {
        final camera = widget.cameras.first;

        unawaited(
          onNewCameraSelected(camera),
        );
      }
      setState(() {});
    }
  }

  void onTakePictureButtonPressed() {
    takePicture().then((XFile? file) {
      if (mounted) {
        setState(() {
          imageFile = file;
        });
        if (file == null) {
          showInSnackBar('Please take picture again');
        }
      }
    });
  }

  void onFlashModeButtonPressed() {
    if (_flashModeControlRowAnimationController.value == 1) {
      _flashModeControlRowAnimationController.reverse();
    } else {
      _flashModeControlRowAnimationController.forward();
      _focusModeControlRowAnimationController.reverse();
    }
  }

  void onFocusModeButtonPressed() {
    if (_focusModeControlRowAnimationController.value == 1) {
      _focusModeControlRowAnimationController.reverse();
    } else {
      _focusModeControlRowAnimationController.forward();
      _flashModeControlRowAnimationController.reverse();
    }
  }

  Future<void> onCaptureOrientationLockButtonPressed() async {
    try {
      if (controller != null) {
        final cameraController = controller!;
        if (cameraController.value.isCaptureOrientationLocked) {
          await cameraController.unlockCaptureOrientation();
          showInSnackBar('Capture orientation unlocked');
        } else {
          await cameraController.lockCaptureOrientation();
          showInSnackBar(
            'Capture orientation locked to ${cameraController.value.lockedCaptureOrientation.toString().split('.').last}',
          );
        }
      }
    } on CameraException catch (e) {
      _showCameraException(e);
    }
  }

  void onSetFlashModeButtonPressed(FlashMode mode) {
    setFlashMode(mode).then((_) {
      if (mounted) {
        setState(() {});
      }
      showInSnackBar('Flash mode set to ${mode.toString().split('.').last}');
    });
  }

  void onSetFocusModeButtonPressed(FocusMode mode) {
    setFocusMode(mode).then((_) {
      if (mounted) {
        setState(() {});
      }
      showInSnackBar('Focus mode set to ${mode.toString().split('.').last}');
    });
  }

  Future<void> onPausePreviewButtonPressed() async {
    final cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return;
    }

    if (cameraController.value.isPreviewPaused) {
      await cameraController.resumePreview();
    } else {
      await cameraController.pausePreview();
    }

    if (mounted) {
      setState(() {});
    }
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

  Future<void> setFocusMode(FocusMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setFocusMode(mode);
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<XFile?> takePicture() async {
    final cameraController = controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      final file = await cameraController.takePicture();
      return file;
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  void _showCameraException(CameraException e) {
    _logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }
}
