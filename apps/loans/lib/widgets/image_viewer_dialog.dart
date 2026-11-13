import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:photo_view/photo_view.dart';

/// Full-size viewer for a proof image: sized to 80% of the window (at least
/// 320x320, never larger than the window minus 32px), with pinch/trackpad
/// zoom from [PhotoView] plus explicit zoom in / zoom out / reset buttons.
Future<void> showImageViewerDialog(
  BuildContext context, {
  required String url,
  ImageProvider? imageProvider,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: AppColors.white,
        child: _ImageViewer(
          imageProvider: imageProvider ?? CachedNetworkImageProvider(url),
        ),
      );
    },
  );
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.imageProvider});

  final ImageProvider imageProvider;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  final _controller = PhotoViewController();
  final _scaleState = PhotoViewScaleStateController();

  @override
  void dispose() {
    _controller.dispose();
    _scaleState.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final current = _controller.scale ?? 1.0;
    _controller.scale = (current * factor).clamp(0.05, 20.0);
  }

  void _reset() {
    _scaleState.scaleState = PhotoViewScaleState.initial;
  }

  void _close() {
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width =
        math.max<double>(320, size.width * 0.8).clamp(0.0, size.width - 32);
    final height =
        math.max<double>(320, size.height * 0.8).clamp(0.0, size.height - 32);

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: PhotoView(
                imageProvider: widget.imageProvider,
                controller: _controller,
                scaleStateController: _scaleState,
                backgroundDecoration: const BoxDecoration(
                  color: AppColors.white,
                ),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
                enablePanAlways: true,
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _ViewerButton(
              icon: Icons.close,
              tooltip: 'Close',
              onPressed: _close,
            ),
          ),
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ViewerButton(
                      icon: Icons.zoom_out,
                      tooltip: 'Zoom out',
                      onPressed: () => _zoom(1 / 1.25),
                    ),
                    const SizedBox(width: 4),
                    _ViewerButton(
                      icon: Icons.zoom_in,
                      tooltip: 'Zoom in',
                      onPressed: () => _zoom(1.25),
                    ),
                    const SizedBox(width: 4),
                    _ViewerButton(
                      icon: Icons.restart_alt,
                      tooltip: 'Reset zoom',
                      onPressed: _reset,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerButton extends StatelessWidget {
  const _ViewerButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: AppColors.black),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.white.withValues(alpha: 0.85),
      ),
      onPressed: onPressed,
    );
  }
}
