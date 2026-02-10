import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/screen/loan_offer_item.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/keep_alive_widget.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_view_repository/product_view_repository.dart';

class ChooseLoanSection extends StatelessWidget {
  const ChooseLoanSection({
    required this.selectedIndex,
    required this.onProductSelected,
    required this.onProductUnselected,
    this.allowAddOns,
    super.key,
  });

  final int selectedIndex;
  final void Function(int index, String productId, ProductView productView)
      onProductSelected;
  final VoidCallback onProductUnselected;
  final bool? allowAddOns;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose loan',
            style: TextStyle(
              fontSize: 24,
              color: AppColors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Gap(16),
          Expanded(
            child: KeepAliveWidget(
              child: StreamBuilder(
                key: const PageStorageKey(
                  'products_for_loans',
                ),
                stream: context.read<ProductBloc>().products,
                builder: (context, snapshot) {
                  final data = snapshot.data;

                  if (data == null) {
                    return Container();
                  }

                  return GridView.builder(
                    gridDelegate:
                        SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 258,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      mainAxisExtent: 261.toDouble(),
                    ),
                    itemBuilder: (context, index) {
                      // if it's building the 2nd to the last data
                      if (index == data.length - 3) {
                        context.read<ProductBloc>().loadNext(
                              limit: data.length + defaultDataLimit,
                              allowAddOns: allowAddOns,
                            );
                      }

                      final productView = data[index];
                      const colorList = AppColors.loanItemColorsList;
                      var colorIndex = index;

                      if (colorIndex > colorList.length - 1) {
                        final divisible = index % colorList.length;
                        colorIndex = divisible;
                      }

                      return LoanOfferItem(
                        backgroundColor: colorList[colorIndex],
                        productView: productView,
                        selected: selectedIndex == index,
                        isProduct:
                            AuthenticationService.instance.isAdmin,
                        onSelected: () {
                          if (selectedIndex == index) {
                            onProductUnselected();
                          } else {
                            onProductSelected(
                              index,
                              productView.productId,
                              productView,
                            );
                          }
                        },
                      );
                    },
                    itemCount: data.length,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
