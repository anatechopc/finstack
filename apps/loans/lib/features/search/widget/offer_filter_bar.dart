import 'package:flutter/material.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/utils/screen_helpers.dart';

/// The offer facets, as chips.
///
/// v1 ships exactly **two**: company and term, in all four combinations
/// (`firestore.indexes.{dev,stg,prod}.json`). There is deliberately no
/// interest-rate control — it is a range filter and
/// `product_view_firestore_service.dart:119-121` hardcodes
/// `orderBy('updated_at')` first, so Firestore rejects the query outright, and
/// no `interest_rate` field appears in any index in any environment. Deferred
/// to finstack#103; the `?interest=` route param is not parsed either, or the
/// crash would stay reachable by deep link.
class OfferFilterBar extends StatelessWidget {
  const OfferFilterBar({
    required this.filters,
    required this.onChanged,
    this.showCompanyChip = true,
    super.key,
  });

  /// The term vocabulary a product can actually be created with
  /// (`loan_term_section.dart:40-50`). Two values, so a chip pair is the whole
  /// picker — `product_views.term` is a String ('1m', '15d'), not a number.
  static const termOptions = <String, String>{
    '1m': 'Monthly',
    '15d': 'Twice a month',
  };

  final OfferFilters filters;
  final ValueChanged<OfferFilters> onChanged;

  /// False for `UserRole.companyManagedRoles`. `FirestoreSearchIndex` injects
  /// their own company on the offers scope (spec `:164`/`:167-168`) and that
  /// value wins over the facet, so the chip could not change what they see.
  /// A deep-linked `?company=` is inert for them for the same reason.
  final bool showCompanyChip;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (showCompanyChip && filters.companyId != null)
          InputChip(
            key: const Key('filter_chip_company'),
            // The deep link carries a company *id*, and the display name lives
            // in `company_name` on a result — which a zero-result link does not
            // have. Rendering the raw document id is worse than a generic
            // label, so v1 renders neither and ships no company picker;
            // resolving the name via `CompanyRepository.get` is finstack#103's
            // neighbour, not this task.
            label: const Text('Selected lender'),
            deleteIcon: const Icon(
              Icons.close_rounded,
              key: Key('filter_chip_company_remove'),
              size: defaultIconSize,
            ),
            onDeleted: () => onChanged(OfferFilters(term: filters.term)),
          ),
        for (final option in termOptions.entries)
          FilterChip(
            key: Key('filter_chip_term_${option.key}'),
            label: Text(option.value),
            selected: filters.term == option.key,
            // Toggling the selected chip off IS the remove affordance — a
            // second delete icon on a two-state chip is a second way to do one
            // thing.
            onSelected: (selected) => onChanged(
              OfferFilters(
                companyId: filters.companyId,
                term: selected ? option.key : null,
              ),
            ),
          ),
      ],
    );
  }
}
