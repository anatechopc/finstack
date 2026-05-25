import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:product_view_repository/product_view_repository.dart';

class LoanOfferItem extends StatefulWidget {
  const LoanOfferItem({
    required this.productView, super.key,
    this.backgroundColor = AppColors.red,
    this.foregroundColor = AppColors.black,
    this.isContent = false,
    this.selected = false,
    this.isProduct = false,
    this.parentMaxWidthConstraint = double.infinity,
    this.onSelected,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final bool isContent;
  final bool selected;
  final double parentMaxWidthConstraint;
  final bool isProduct;
  final ProductView productView;
  final VoidCallback? onSelected;

  @override
  State<LoanOfferItem> createState() => _LoanOfferItemState();
}

class _LoanOfferItemState extends State<LoanOfferItem> {
  bool _selectedState = false;
  bool _listenSelectState = false;

  @override
  void initState() {
    super.initState();

    _selectedState = widget.selected;
  }

  @override
  void didUpdateWidget(covariant LoanOfferItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      _selectedState = widget.selected;
      _listenSelectState = widget.selected;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ProductBloc, ProductState>(
      listener: (context, state) {
        if (_listenSelectState) {
          if (state.status == ProductStatus.unselected) {
            setState(() {
              _selectedState = false;
              _listenSelectState = false;
              // widget.onSelected?.call();
            });
          }
        }
      },
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedState = !_selectedState;
            _listenSelectState = _selectedState;

            widget.onSelected?.call();
          });
        },
        // onTap: widget.onSelected,
        child: Container(
          constraints: const BoxConstraints(
            // maxWidth: maxWidth,
            maxHeight: 270,
          ),
          padding: !widget.isContent
              ? EdgeInsets.all(!_selectedState ? 16 : 12)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            borderRadius: defaultBorderRadius,
            color: widget.backgroundColor,
            border: _selectedState
                ? Border.all(
                    color: AppColors.white,
                    width: 4,
                  )
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context,
                  showCancelButton: widget.isContent &&
                      getScreenSize(context: context).index <
                          ScreenSize.medium.index,),
              const Gap(12),
              _body(),
              if (!widget.isContent && !widget.isProduct) ...[
                const Gap(12),
                _footer(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    bool showCancelButton = false,
  }) {
    // CircleAvatar, if image is provided, set background image
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.white.withValues(alpha: 0.32),
                    ),
                  ),
                  child: CircleAvatar(
                    radius: !widget.isContent ? 16 : 20,
                    backgroundColor: AppColors.white,
                    backgroundImage:
                        widget.productView.companyProfilePhotoUrl == null
                            ? null
                            : CachedNetworkImageProvider(
                                widget.productView.companyProfilePhotoUrl!.url,
                              ),
                    child: widget.productView.companyProfilePhotoUrl == null
                        ? Text(
                            widget.productView.companyName.initials(limit: 2),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
                  ),
                ),
                const Gap(8),
                Text(
                  widget.productView.companyName,
                  style: TextStyle(
                    fontSize: !widget.isContent ? 14 : 24,
                    fontWeight: FontWeight.w600,
                    color: widget.foregroundColor,
                  ),
                ),
              ],
            ),
            if (showCancelButton)
              InkWell(
                borderRadius: BorderRadius.circular(32),
                onTap: () {
                  GoRouter.of(context).goSafe('${Paths.index}?sec=offers');
                },
                child: SvgPicture.asset(
                  'svg/close.svg'.assetSafe,
                  colorFilter: const ColorFilter.mode(
                    AppColors.black,
                    BlendMode.srcIn,
                  ),
                ),
              ),
          ],
        ),
        const Gap(4),
        Text(
          widget.productView.tagLine ?? '',
          style: TextStyle(
            fontSize: 12,
            color: widget.foregroundColor,
          ),
        ),
      ],
    );
  }

  Widget _body() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.productView.loanType,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: widget.foregroundColor,
          ),
        ),
        const Gap(8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _bodyInner(
              isRate: false,
              amount: widget.productView.maxLoanableAmount,
            ),
            _bodyInner(
              isRate: true,
              amount: widget.productView.interestRate,
              term:
                  'per ${widget.productView.completeTerm}${widget.isContent ? ' @ ${widget.productView.completeMaxPeriod}' : ''}',
            ),
          ],
        ),
      ],
    );
  }

  Widget _bodyInner({
    required bool isRate,
    required double amount,
    String term = 'Loanable',
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isRate ? 'Rate' : 'Amount',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: widget.foregroundColor,
          ),
        ),
        const Gap(4),
        if (isRate)
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: amount.toDefaultFormat(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: widget.foregroundColor,
                  ),
                ),
                TextSpan(
                  text: '%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                    color: widget.foregroundColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          )
        else
          AppWidgets.defaultAmountWidget(
            amount.toCurrency(),
            fontSize: 16,
            fontColor: widget.foregroundColor,
          ),
        const Gap(4),
        Text(
          term,
          style: TextStyle(
            fontSize: 12,
            color: widget.foregroundColor,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _footer() {
    final reviewAvg = widget.productView.reviewRatingAvg;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Icon(
              Icons.star_rounded,
              size: 14,
            ),
            Text(
              '${reviewAvg.isNaN ? '0' : reviewAvg}(${widget.productView.reviewCount})',
              style: TextStyle(
                fontSize: 12,
                color: widget.foregroundColor,
              ),
            ),
          ],
        ),
        // const Gap(8),
        AppWidgets.defaultFilledButton(
          child: const Row(
            children: [
              Icon(
                Icons.add,
                size: 14,
                weight: 1,
              ),
              Text(
                'compare',
                style: TextStyle(
                  fontSize: 12,
                ),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(
            vertical: 2,
            horizontal: 6,
          ),
          onPressed: () {
            debugPrint('compare');
          },
        ),
      ],
    );
  }
}
