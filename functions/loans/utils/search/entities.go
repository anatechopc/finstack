package search

import "sort"

// UserTokens builds the search_tokens array for a users document.
// Email needs no special handling: Tokenize already splits on runs of
// non-alphanumeric characters, which covers "@", ".", "_", "-" and "+".
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

func merge(groups ...[]string) []string {
	set := map[string]struct{}{}
	for _, group := range groups {
		for _, token := range group {
			set[token] = struct{}{}
		}
	}

	tokens := make([]string, 0, len(set))
	for token := range set {
		tokens = append(tokens, token)
	}
	sort.Strings(tokens)
	return tokens
}
