package middleware

import (
	"fmt"
	"net/http"
)

// CORSEnabledFunction is an example of setting CORS headers.
// For more information about CORS and CORS preflight requests, see
// https://developer.mozilla.org/en-US/docs/Glossary/Preflight_request.
func CORSEnabledFunction(w http.ResponseWriter, r *http.Request) {
	// Set CORS headers for the preflight request
	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "POST")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.Header().Set("Access-Control-Max-Age", "3600")
		w.WriteHeader(http.StatusNoContent)
		return
	}
	// Set CORS headers for the main request.
	w.Header().Set("Access-Control-Allow-Origin", "*")
	fmt.Fprint(w, "Hello, World!")
}
