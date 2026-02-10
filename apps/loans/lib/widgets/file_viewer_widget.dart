import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans/features/products/requirement_temp_container.dart';
import 'package:loooans/utils/pdf_generator.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';

class FileViewerWidget extends StatefulWidget {
  FileViewerWidget({
    super.key,
    this.items = const [],
    this.tempItems = const [],
    this.photosUrls = const [],
  }) : assert(
          items.isNotEmpty || tempItems.isNotEmpty || photosUrls.isNotEmpty,
          'items, tempItems and photosUrls should not both be empty',
        );

  final List<RequirementSubmission> items;
  final List<RequirementTempContainer> tempItems;
  final List<ImageUrl> photosUrls;

  @override
  State<FileViewerWidget> createState() => _FileViewerWidgetState();
}

class _FileViewerWidgetState extends State<FileViewerWidget>
    with TickerProviderStateMixin {
  late PageController _pageViewController;
  late TabController _tabController;
  int _currentPageIndex = 0;
  late List<_SimpleItem> items;

  bool get _isOnDesktopAndWeb {
    if (kIsWeb) {
      return true;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  @override
  void initState() {
    super.initState();
    items = _transformItems();
    _pageViewController = PageController();
    _tabController = TabController(
      length: items.length,
      vsync: this,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _body(context);
  }

  Widget _body(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppWidgets.defaultOutlinedButton(
              child: AppWidgets.iconTextPairWidget(
                icon: Icons.download,
                text: 'Download',
              ),
              onPressed: () async {
                if (items.isNotEmpty) {
                  final item = items[_tabController.index];
                  final url = item.url;
                  if (url == null) {
                    return;
                  }
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                }
              },
            ),
            const Gap(16),
            AppWidgets.defaultOutlinedButton(
              child: AppWidgets.iconTextPairWidget(
                icon: Icons.visibility,
                text: 'View as PDF',
              ),
              onPressed: () async {
                final item = widget.items[_tabController.index].url;
                await PdfGenerator.printRemoteFile(
                  url: item.url,
                  fileName: item.name,
                );
              },
            ),
          ],
        ),
        const Gap(16),
        Expanded(
          child: PageView(
            /// [PageView.scrollDirection] defaults to [Axis.horizontal].
            /// Use [Axis.vertical] to scroll vertically.
            controller: _pageViewController,
            onPageChanged: _handlePageViewChanged,
            children: items.map((item) {
              final requirementName = item.name;

              if (requirementName.contains('.pdf')) {
                final controller = PdfViewerController();
                final params = PdfViewerParams(
                  loadingBannerBuilder: (
                    context,
                    bytesDownloaded,
                    totalBytes,
                  ) {
                    return Center(
                      child: CircularProgressIndicator(
                        // totalBytes may not be available on certain case
                        value: totalBytes != null
                            ? bytesDownloaded / totalBytes
                            : null,
                        backgroundColor: Colors.black,
                      ),
                    );
                  },
                  errorBannerBuilder: (context, err, stackTrace, pdfRef) {
                    var errMessage = 'Something went wrong. Cannot open pdf';

                    if (err is PdfPasswordException) {
                      errMessage += ' with password';
                    }

                    return Center(
                      child: Text(
                        errMessage,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  },
                  viewerOverlayBuilder: (context, size, handleLinkTap) => [
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      // Your code here:
                      onDoubleTap: () {
                        controller.zoomUp(loop: true);
                      },
                      // If you use GestureDetector on viewerOverlayBuilder, it breaks link-tap handling
                      // and you should manually handle it using onTapUp callback
                      onTapUp: (details) {
                        handleLinkTap(details.localPosition);
                      },
                      // Make the GestureDetector covers all the viewer widget's area
                      // but also make the event go through to the viewer.
                      child: IgnorePointer(
                        child: SizedBox(width: size.width, height: size.height),
                      ),
                    ),
                    PdfViewerScrollThumb(
                      controller: controller,
                      thumbSize: const Size(40, 25),
                      thumbBuilder:
                          (context, thumbSize, pageNumber, controller) =>
                              ColoredBox(
                        color: Colors.black,
                        // Show page number on the thumb
                        child: Center(
                          child: Text(
                            pageNumber.toString(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    // Add horizontal scroll thumb on viewer's bottom
                    PdfViewerScrollThumb(
                      controller: controller,
                      orientation: ScrollbarOrientation.bottom,
                      thumbSize: const Size(80, 30),
                      thumbBuilder:
                          (context, thumbSize, pageNumber, controller) =>
                              const ColoredBox(
                        color: Colors.red,
                      ),
                    ),
                  ],
                );

                if (item.url != null) {
                  return PdfViewer.uri(
                    Uri.parse(item.url!),
                    params: params,
                  );
                }

                return PdfViewer.data(
                  item.bytes!,
                  sourceName: requirementName,
                  params: params,
                );
              } else if (requirementName.contains('.jpg') ||
                  requirementName.contains('.jpeg') ||
                  requirementName.contains('.png')) {
                if (item.url != null) {
                  return PhotoView(
                    imageProvider: CachedNetworkImageProvider(
                      item.url!,
                    ),
                  );
                }

                return Image.memory(item.bytes!);
              }

              return Text('$requirementName file not supported');
            }).toList(),
          ),
        ),
        PageIndicator(
          tabController: _tabController,
          currentPageIndex: _currentPageIndex,
          onUpdateCurrentPageIndex: _updateCurrentPageIndex,
          isOnDesktopAndWeb: _isOnDesktopAndWeb,
        ),
      ],
    );
  }

  void _handlePageViewChanged(int currentPageIndex) {
    if (!_isOnDesktopAndWeb) {
      return;
    }
  }

  void _updateCurrentPageIndex(int index) {
    _tabController.index = index;
    _currentPageIndex = index;
    setState(() {});
    _pageViewController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  List<_SimpleItem> _transformItems() {
    final allItems = <_SimpleItem>[];
    if (widget.items.isNotEmpty) {
      allItems.addAll(
        widget.items.map((item) {
          return _SimpleItem(
            item.url.name,
            item.url.url,
            null,
          );
        }).toList(),
      );
    }

    if (widget.tempItems.isNotEmpty) {
      allItems.addAll(
        widget.tempItems
            .map((item) {
              return item.fileData.map((file) {
                return _SimpleItem(
                  file.name,
                  null,
                  Uint8List.fromList(file.data.toList()),
                );
              });
            })
            .flattened
            .toList(),
      );
    }

    if (widget.photosUrls.isNotEmpty) {
      allItems.addAll(
        widget.photosUrls.map((photo) {
          return _SimpleItem(
            photo.name,
            photo.url,
            null,
          );
        }),
      );
    }

    return allItems;
  }
}

/// Page indicator for desktop and web platforms.
///
/// On Desktop and Web, drag gesture for horizontal scrolling in a PageView is disabled by default.
/// You can defined a custom scroll behavior to activate drag gestures,
/// see https://docs.flutter.dev/release/breaking-changes/default-scroll-behavior-drag.
///
/// In this sample, we use a TabPageSelector to navigate between pages,
/// in order to build natural behavior similar to other desktop applications.
class PageIndicator extends StatelessWidget {
  const PageIndicator({
    required this.tabController, required this.currentPageIndex, required this.onUpdateCurrentPageIndex, required this.isOnDesktopAndWeb, super.key,
  });

  final int currentPageIndex;
  final TabController tabController;
  final void Function(int) onUpdateCurrentPageIndex;
  final bool isOnDesktopAndWeb;

  @override
  Widget build(BuildContext context) {
    if (!isOnDesktopAndWeb) {
      return const SizedBox.shrink();
    }
    // final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          IconButton(
            splashRadius: 16,
            padding: EdgeInsets.zero,
            onPressed: () {
              if (currentPageIndex == 0) {
                return;
              }
              onUpdateCurrentPageIndex(currentPageIndex - 1);
            },
            icon: const Icon(
              Icons.arrow_left_rounded,
              size: 32,
            ),
          ),
          TabPageSelector(
            controller: tabController,
            color: Colors.black12,
            selectedColor: Colors.black54,
          ),
          IconButton(
            splashRadius: 16,
            padding: EdgeInsets.zero,
            onPressed: () {
              if (currentPageIndex >= tabController.length - 1) {
                return;
              }
              onUpdateCurrentPageIndex(currentPageIndex + 1);
            },
            icon: const Icon(
              Icons.arrow_right_rounded,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleItem {

  const _SimpleItem(this.name, this.url, this.bytes)
      : assert(
          url != null || bytes != null,
          'url and bytes cannot be null at the same time.',
        );
  final String name;
  final String? url;
  final Uint8List? bytes;
}
