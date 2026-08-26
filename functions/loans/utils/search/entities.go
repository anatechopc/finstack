package search

// UserTokens builds the search_tokens array for a users document.
// Email needs no special handling: Tokenize already splits on runs of
// non-alphanumeric characters, which covers "@", ".", "_", "-" and "+".
//
// mobile goes through PhoneTokens, NOT Tokenize: only PhoneTokens
// canonicalizes the three spellings of a Philippine number to one form, so
// routing it through Tokenize would index "0917…" and "+63917…" as different
// clients. golden_tokens.json pins this via the user_tokens path.
func UserTokens(firstName, middleName, lastName, mobile, email string) []string {
	return merge(
		Tokenize(firstName, middleName, lastName, email),
		PhoneTokens(mobile),
	)
}

// ProductViewTokens builds the search_tokens array for a product_views
// document. product_views has no name field; loan_type carries that meaning,
// because the add-product flow offers presets plus an "Others" branch where
// the lender types their own value.
func ProductViewTokens(companyName, loanType, tagLine string) []string {
	return Tokenize(companyName, loanType, tagLine)
}

// merge unions already-capped groups and re-applies the count cap, so the
// merged array a composition writes obeys MaxTokens too — the sum of two
// capped groups is not itself capped.
func merge(groups ...[]string) []string {
	set := map[string]struct{}{}
	for _, group := range groups {
		for _, token := range group {
			set[token] = struct{}{}
		}
	}

	return sortedCapped(set)
}
