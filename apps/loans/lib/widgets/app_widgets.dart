import 'dart:async';

import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_extra_fields/form_builder_extra_fields.dart';
import 'package:intl/intl.dart';
import 'package:loooans/widgets/button_widgets.dart';
import 'package:loooans/widgets/dialog_widgets.dart';
import 'package:loooans/widgets/display_widgets.dart';
import 'package:loooans/widgets/form_widgets.dart';
import 'package:loooans/widgets/layout_widgets.dart';
import 'package:loooans/widgets/notification_widgets.dart';
import 'package:loooans/widgets/profile_widgets.dart';
import 'package:loooans/app/model/notification_model.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';
import 'package:user_repository/user_repository.dart';

export 'package:loooans/widgets/button_widgets.dart';
export 'package:loooans/widgets/dialog_widgets.dart';
export 'package:loooans/widgets/display_widgets.dart';
export 'package:loooans/widgets/form_widgets.dart';
export 'package:loooans/widgets/layout_widgets.dart';
export 'package:loooans/widgets/notification_widgets.dart';
export 'package:loooans/widgets/profile_widgets.dart';

class ButtonOption {

  ButtonOption({
    required this.label,
    required this.value,
  });
  final String label;
  final String value;
}

class AppWidgets {
  // --- Layout Widgets ---

  static Widget rootConstraints({required Widget child}) =>
      LayoutWidgets.rootConstraints(child: child);

  static SliverAppBar defaultSliverAppBar(
    BuildContext context, {
    bool showLogin = true,
    bool showSignUp = true,
  }) =>
      LayoutWidgets.defaultSliverAppBar(
        context,
        showLogin: showLogin,
        showSignUp: showSignUp,
      );

  static AppBar defaultAppBar(
    BuildContext context, {
    bool showLogin = true,
    bool showSignUp = true,
    bool showMyLoansButton = false,
    bool showAddCapitalButton = false,
    bool showAdvertiseButton = false,
    bool showAddBorrowerButton = false,
    bool showMessagesButton = false,
    bool showSearchField = false,
  }) =>
      LayoutWidgets.defaultAppBar(
        context,
        showLogin: showLogin,
        showSignUp: showSignUp,
        showMyLoansButton: showMyLoansButton,
        showAddCapitalButton: showAddCapitalButton,
        showAdvertiseButton: showAdvertiseButton,
        showAddBorrowerButton: showAddBorrowerButton,
        showMessagesButton: showMessagesButton,
        showSearchField: showSearchField,
      );

  static Widget separatedItem({
    String? name,
    String? description,
    Widget? child,
    int? index,
    bool showIndexPlaceholder = false,
    bool isHeader = false,
  }) =>
      LayoutWidgets.separatedItem(
        name: name,
        description: description,
        child: child,
        index: index,
        showIndexPlaceholder: showIndexPlaceholder,
        isHeader: isHeader,
      );

  static Widget legendItem({
    required String title,
    Widget? icon,
  }) =>
      LayoutWidgets.legendItem(
        title: title,
        icon: icon,
      );

  static Widget iconTextPairWidget({
    required IconData icon,
    required String text,
    double? iconSize,
    double? fontSize,
    FontWeight fontWeight = FontWeight.w500,
  }) =>
      LayoutWidgets.iconTextPairWidget(
        icon: icon,
        text: text,
        iconSize: iconSize,
        fontSize: fontSize,
        fontWeight: fontWeight,
      );

  // --- Form Widgets ---

  static FormBuilderTextField defaultFormBuilderTextField({
    required String name,
    required String label,
    String? helperText,
    Color borderColor = Colors.black,
    FormFieldValidator<String>? validator,
    bool obscureText = false,
    List<TextInputFormatter>? inputFormatters,
    Widget? prefix,
    Widget? suffix,
    TextInputType? keyboardType,
    String? initialValue,
    bool enabled = true,
    ValueTransformer<String?>? valueTransformer,
    void Function(String?)? onChanged,
    int? maxLines = 1,
    String? hintText,
  }) =>
      FormWidgets.defaultFormBuilderTextField(
        name: name,
        label: label,
        helperText: helperText,
        borderColor: borderColor,
        validator: validator,
        obscureText: obscureText,
        inputFormatters: inputFormatters,
        prefix: prefix,
        suffix: suffix,
        keyboardType: keyboardType,
        initialValue: initialValue,
        enabled: enabled,
        valueTransformer: valueTransformer,
        onChanged: onChanged,
        maxLines: maxLines,
        hintText: hintText,
      );

  static FormBuilderTypeAhead<T> defaultFormBuilderTextFieldDropdown<T>({
    required String name,
    required String label,
    required FutureOr<List<T>?> Function(String) suggestionsCallback, required Widget Function(BuildContext, T) itemBuilder, String? helperText,
    Color borderColor = Colors.black,
    FormFieldValidator<dynamic>? validator,
    bool obscureText = false,
    List<TextInputFormatter>? inputFormatters,
    Widget? prefix,
    Widget? suffix,
    TextInputType? keyboardType,
    T? initialValue,
    bool enabled = true,
    ValueTransformer<String?>? valueTransformer,
    void Function(String?)? onChanged,
    int? maxLines = 1,
    String? hintText,
    void Function(T)? onSelected,
    SelectionToTextTransformer<T>? selectionToTextTransformer,
  }) =>
      FormWidgets.defaultFormBuilderTextFieldDropdown<T>(
        name: name,
        label: label,
        suggestionsCallback: suggestionsCallback,
        itemBuilder: itemBuilder,
        helperText: helperText,
        borderColor: borderColor,
        validator: validator,
        obscureText: obscureText,
        inputFormatters: inputFormatters,
        prefix: prefix,
        suffix: suffix,
        keyboardType: keyboardType,
        initialValue: initialValue,
        enabled: enabled,
        valueTransformer: valueTransformer,
        onChanged: onChanged,
        maxLines: maxLines,
        hintText: hintText,
        onSelected: onSelected,
        selectionToTextTransformer: selectionToTextTransformer,
      );

  static FormBuilderDropdown<T> defaultFormBuilderDropdown<T>(
      {required String name,
      required String label,
      required List<DropdownMenuItem<T>> items,
      dynamic initialValue,
      FormFieldValidator<dynamic>? validator,
      Color borderColor = Colors.black,
      ValueChanged<T?>? onChanged,
      Color? dropdownColor,
      bool enabled = true,
      }) =>
      FormWidgets.defaultFormBuilderDropdown<T>(
        name: name,
        label: label,
        items: items,
        initialValue: initialValue,
        validator: validator,
        borderColor: borderColor,
        onChanged: onChanged,
        dropdownColor: dropdownColor,
        enabled: enabled,
      );

  static FormBuilderDateTimePicker defaultFormBuilderDatePicker({
    required String name,
    required String label,
    String? helperText,
    Color borderColor = Colors.black,
    FormFieldValidator<dynamic>? validator,
    DateFormat? format,
    DateTime? lastDate,
    DateTime? initialDate,
    bool enabled = true,
  }) =>
      FormWidgets.defaultFormBuilderDatePicker(
        name: name,
        label: label,
        helperText: helperText,
        borderColor: borderColor,
        validator: validator,
        format: format,
        lastDate: lastDate,
        initialDate: initialDate,
        enabled: enabled,
      );

  static Future<Map<String, dynamic>?> defaultMediaChooserDialog(
    BuildContext context, {
    bool allowCamera = true,
    bool allowGallery = true,
  }) =>
      FormWidgets.defaultMediaChooserDialog(
        context,
        allowCamera: allowCamera,
        allowGallery: allowGallery,
      );

  static FormBuilderField defaultIconButtonMediaChooser(
    BuildContext context, {
    required String name,
    required String label,
    required String svgLogoPath,
    FormFieldValidator<dynamic>? validator,
    Color color = Colors.black,
    bool allowCamera = true,
    bool allowGallery = true,
  }) =>
      FormWidgets.defaultIconButtonMediaChooser(
        context,
        name: name,
        label: label,
        svgLogoPath: svgLogoPath,
        validator: validator,
        color: color,
        allowCamera: allowCamera,
        allowGallery: allowGallery,
      );

  static FormBuilderField defaultButtonMediaChooser(
    BuildContext context, {
    required String name,
    required String label,
    FormFieldValidator<dynamic>? validator,
    Color color = Colors.black,
    bool allowCamera = true,
    bool allowGallery = true,
  }) =>
      FormWidgets.defaultButtonMediaChooser(
        context,
        name: name,
        label: label,
        validator: validator,
        color: color,
        allowCamera: allowCamera,
        allowGallery: allowGallery,
      );

  static FilteringTextInputFormatter defaultCurrencyInputFormatter() =>
      FormWidgets.defaultCurrencyInputFormatter();

  static TextInputFormatter rangeInputFormatter(
      {double max = double.infinity,}) =>
      FormWidgets.rangeInputFormatter(max: max);

  // --- Button Widgets ---

  static OutlinedButton defaultOutlinedButton({
    required Widget child,
    required VoidCallback? onPressed,
    EdgeInsets padding = const EdgeInsets.symmetric(
      vertical: 24,
      horizontal: 20,
    ),
    Color foregroundColor = Colors.black,
  }) =>
      ButtonWidgets.defaultOutlinedButton(
        child: child,
        onPressed: onPressed,
        padding: padding,
        foregroundColor: foregroundColor,
      );

  static Widget defaultFilledButton({
    required VoidCallback? onPressed, Widget? child,
    EdgeInsets padding = const EdgeInsets.symmetric(
      vertical: 24,
      horizontal: 20,
    ),
    Color foregroundColor = Colors.white,
    Color backgroundColor = Colors.black,
    List<ButtonOption> options = const [],
    void Function(ButtonOption)? onOptionSelected,
    String? childText,
  }) =>
      ButtonWidgets.defaultFilledButton(
        onPressed: onPressed,
        child: child,
        padding: padding,
        foregroundColor: foregroundColor,
        backgroundColor: backgroundColor,
        options: options,
        onOptionSelected: onOptionSelected,
        childText: childText,
      );

  // --- Dialog Widgets ---

  static void showDefaultLoadingDialog(BuildContext context) =>
      DialogWidgets.showDefaultLoadingDialog(context);

  static void showDefaultSimpleDialog(
    BuildContext context, {
    required String content,
    String title = 'Attention!',
    List<Widget> actions = const [],
  }) =>
      DialogWidgets.showDefaultSimpleDialog(
        context,
        content: content,
        title: title,
        actions: actions,
      );

  static void showPdfDialog(
    BuildContext context, {
    String? pdfUri,
    Map<String, Uint8List>? tempPdfBytes,
  }) =>
      DialogWidgets.showPdfDialog(
        context,
        pdfUri: pdfUri,
        tempPdfBytes: tempPdfBytes,
      );

  static Future<void> showLoanClientDetailsDialog(
    BuildContext context, {
    required String userId,
    UserLoanView? userLoanView,
    String? loanId,
    String? productId,
  }) =>
      DialogWidgets.showLoanClientDetailsDialog(
        context,
        userId: userId,
        userLoanView: userLoanView,
        loanId: loanId,
        productId: productId,
      );

  static Future<void> showBorrowerDetailsDialog(
    BuildContext context,
    String userId, {
    VoidCallback? onClosed,
  }) =>
      DialogWidgets.showBorrowerDetailsDialog(
        context,
        userId,
        onClosed: onClosed,
      );

  static Future<void> showAdditionalLoanDetailDialog(
    BuildContext context, {
    required String additionalLoanId,
  }) =>
      DialogWidgets.showAdditionalLoanDetailDialog(
        context,
        additionalLoanId: additionalLoanId,
      );

  static Future<void> showAddUserWidget(
    BuildContext context, {
    Color backgroundColor = const Color(0xFF38DC93),
    bool withLoanApplication = false,
    bool withExtendedUserDetailInputs = false,
    bool? allowAddOns,
    bool scrollable = false,
    bool isTeamMember = false,
  }) =>
      DialogWidgets.showAddUserWidget(
        context,
        backgroundColor: backgroundColor,
        withLoanApplication: withLoanApplication,
        withExtendedUserDetailInputs: withExtendedUserDetailInputs,
        allowAddOns: allowAddOns,
        scrollable: scrollable,
        isTeamMember: isTeamMember,
      );

  // --- Profile Widgets ---

  static Widget profileIcon(
    BuildContext context, {
    bool avatarOnly = false,
    double? avatarDimension,
    User? user,
    Company? company,
    bool removeExtraPadding = false,
    bool triggerIconClick = false,
  }) =>
      ProfileWidgets.profileIcon(
        context,
        avatarOnly: avatarOnly,
        avatarDimension: avatarDimension,
        user: user,
        company: company,
        removeExtraPadding: removeExtraPadding,
        triggerIconClick: triggerIconClick,
      );

  // --- Notification Widgets ---

  static Widget notificationItem(
    BuildContext context, {
    required NotificationModel model,
    bool isFirst = false,
  }) =>
      NotificationWidgets.notificationItem(
        context,
        model: model,
        isFirst: isFirst,
      );

  // --- Display Widgets ---

  /// it is expected that the amount is in currency form.
  static RichText defaultAmountWidget(
    String amount, {
    int fontSize = 20,
    int subFontSize = 12,
    Color fontColor = Colors.black,
    bool fontThick = true,
  }) =>
      DisplayWidgets.defaultAmountWidget(
        amount,
        fontSize: fontSize,
        subFontSize: subFontSize,
        fontColor: fontColor,
        fontThick: fontThick,
      );

  static RatingBar defaultRatingBar({
    required ValueChanged<double> onRatingUpdate,
    double initialRating = 5,
    double itemSize = 32,
  }) =>
      DisplayWidgets.defaultRatingBar(
        onRatingUpdate: onRatingUpdate,
        initialRating: initialRating,
        itemSize: itemSize,
      );

  /// Read-only star rating that fills continuously by [rating] (half/quarter
  /// stars). For displaying an average rating.
  static RatingBarIndicator ratingIndicator({
    required double rating,
    double itemSize = 24,
  }) =>
      DisplayWidgets.ratingIndicator(rating: rating, itemSize: itemSize);
}
