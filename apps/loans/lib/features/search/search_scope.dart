/// What a search query is searching over.
///
/// [prefix] is the keyword a user types to force a scope. It is deliberately
/// not the collection name and not the deep-link spelling: `offers` reads
/// `product_views`, and the `/search?scope=` param matches on [name].
enum SearchScope {
  clients('clients'),
  offers('products');

  const SearchScope(this.prefix);

  /// The token a user types to force this scope, as in `products: salary`.
  final String prefix;
}

/// A raw query resolved into a scope and the term to search for.
class ParsedQuery {
  const ParsedQuery({required this.scope, required this.term});

  final SearchScope scope;
  final String term;
}
