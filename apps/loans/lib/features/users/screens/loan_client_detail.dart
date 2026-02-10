import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/features/loans/bloc/additional_loan_bloc.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/loans/bloc/payment_bloc.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_action_buttons.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_loan_body.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_loan_selector.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';

class LoanClientDetail extends StatefulWidget {
  const LoanClientDetail({
    required this.userId,
    super.key,
    this.userLoanView,
    this.productId,
    this.loanId,
  });

  final UserLoanView? userLoanView;
  final String? productId;
  final String? loanId;
  final String userId;

  @override
  State<LoanClientDetail> createState() => _LoanClientDetailState();
}

class _LoanClientDetailState extends State<LoanClientDetail> {
  @override
  void initState() {
    super.initState();
    context.read<UserBloc>().selectUser(widget.userId);
    context.read<LoansBloc>().getLoansByUser(userId: widget.userId);
  }

  @override
  void dispose() {
    context.read<ProductBloc>().unselectProduct();
    context.read<LoansBloc>().unselectLoan();
    context.read<UserBloc>().unselectUser();
    super.dispose();
  }

  void _selectLoanParameters({
    required String loanId,
    required String productId,
  }) {
    context.read<ProductBloc>().selectProduct(
          productId,
          forLoans: true,
        );
    context.read<LoansBloc>().selectLoan(
          loanId,
          userLoanView: widget.userLoanView,
        );
  }

  @override
  Widget build(BuildContext context) {
    final isCompactOrMedium =
        getScreenSize(context: context).index <= ScreenSize.medium.index;

    return MultiBlocListener(
      listeners: [
        BlocListener<LoansBloc, LoansState>(
          listener: (context, state) {
            if (state.status == LoansStatus.loading) {
              if (state.isLoading) {
                AppWidgets.showDefaultLoadingDialog(context);
              } else {
                Navigator.of(context, rootNavigator: true).pop();
              }
            } else if (state.status == LoansStatus.success) {
              if (state.message != null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(state.message!)));
              }

              if (!isCompactOrMedium) {
                Navigator.of(context, rootNavigator: true).pop();
              } else {
                GoRouter.of(context).pop();
              }
            } else if (state.status == LoansStatus.allUserLoansRetrieved) {
              final userLoans = context.read<LoansBloc>().userLoans;
              debugPrint('all loans retrieved: ${userLoans.length}');

              if (userLoans.isNotEmpty) {
                var loan = userLoans.first;

                if (widget.loanId != null) {
                  loan = userLoans
                      .singleWhere((loan) => loan.loanId == widget.loanId);
                }

                _selectLoanParameters(
                  loanId: loan.loanId,
                  productId: loan.productId,
                );
              }
            }
          },
        ),
        BlocListener<PaymentBloc, PaymentState>(
          listener: (context, state) {
            if (state.status == PaymentStatus.loading) {
              if (state.isLoading) {
                AppWidgets.showDefaultLoadingDialog(context);
              } else {
                Navigator.of(context, rootNavigator: true).pop();
              }
            } else if (state.status == PaymentStatus.success) {
              if (state.message != null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(state.message!)));
              }

              if (!isCompactOrMedium) {
                Navigator.of(context, rootNavigator: true).pop();
              } else {
                GoRouter.of(context).pop();
              }
            } else if (state.status == PaymentStatus.error) {
              if (state.message != null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(state.message!)));
              }
            }
          },
        ),
        BlocListener<AdditionalLoanBloc, AdditionalLoanState>(
          listener: (context, state) {
            if (state.status == AdditionalLoanStatus.loading) {
              if (state.isLoading) {
                AppWidgets.showDefaultLoadingDialog(context);
              } else {
                Navigator.of(context, rootNavigator: true).pop();
              }
            } else if (state.status == AdditionalLoanStatus.success) {
              if (state.message != null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(state.message!)));
              }

              if (!isCompactOrMedium) {
                Navigator.of(context, rootNavigator: true).pop();
              } else {
                GoRouter.of(context).pop();
              }
            } else if (state.status == AdditionalLoanStatus.error) {
              if (state.message != null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(state.message!)));
              }
            }
          },
        ),
        BlocListener<ProductBloc, ProductState>(
          listener: (context, state) {
            if (state.status == ProductStatus.loading) {
              if (state.isLoading) {
                AppWidgets.showDefaultLoadingDialog(context);
              } else {
                Navigator.of(context, rootNavigator: true).pop();
              }
            }
          },
        ),
      ],
      child: !isCompactOrMedium
          ? _body(context)
          : BlocBuilder<UserBloc, UserState>(
              buildWhen: (prev, next) {
                return next.status == UserStatus.selected;
              },
              builder: (context, state) {
                if (state.status != UserStatus.selected) {
                  return Container();
                }

                final user = context.read<UserBloc>().user;

                return Scaffold(
                  appBar: AppBar(
                    leading: InkWell(
                      onTap: isMobilePlatform
                          ? () {
                              GoRouter.of(context).pop();
                            }
                          : null,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: isMobilePlatform ? 0 : 16,
                          top: 16,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isMobilePlatform)
                              const Icon(Icons.arrow_back_ios_new_rounded),
                            AppWidgets.profileIcon(
                              context,
                              avatarOnly: true,
                              avatarDimension: 32,
                              user: user,
                            ),
                          ],
                        ),
                      ),
                    ),
                    title: Padding(
                      padding: const EdgeInsets.only(
                        top: 16,
                      ),
                      child: Text(
                        user.completeNameEasternOrder,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    centerTitle: false,
                  ),
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _body(context),
                  ),
                );
              },
            ),
    );
  }

  Widget _body(BuildContext context) {
    final isCompactOrMedium =
        getScreenSize(context: context).index <= ScreenSize.medium.index;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClientDetailLoanSelector(
          loanId: widget.loanId,
          onLoanSelected: ({
            required String loanId,
            required String productId,
          }) {
            _selectLoanParameters(
              loanId: loanId,
              productId: productId,
            );
          },
        ),
        const Gap(16),
        Expanded(
          child: ClientDetailLoanBody(
            isCompactOrMedium: isCompactOrMedium,
            userId: widget.userId,
          ),
        ),
        const Gap(16),
        ClientDetailActionButtons(
          userId: widget.userId,
        ),
      ],
    );
  }
}
