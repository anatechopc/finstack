/// What a search query is searching over.
///
/// [prefix] is the keyword a user types to force a scope. It is deliberately
/// not the collection name and not the deep-link spelling: `offers` reads
/// `product_views`, and the `/search?scope=` param matches on [name].
enum SearchScope {
  clients('clients', ['clients', 'client', 'borrowers', 'borrower']),
  offers('offers', ['offers', 'offer', 'products', 'product']);

  const SearchScope(this.prefix, this.aliases);

  /// The keyword shown in hints, as in `offers: salary`.
  final String prefix;

  /// Every keyword accepted before the colon. `products:` was the only one
  /// at first, straight from the spec, and the first admin to try it typed
  /// `offer:` — which fell through as literal text and searched clients for
  /// "offer: …". The singular and the domain word are accepted for both.
  final List<String> aliases;
}

/// A raw query resolved into a scope and the term to search for.
class ParsedQuery {
  const ParsedQuery({required this.scope, required this.term});

  final SearchScope scope;
  final String term;
}
