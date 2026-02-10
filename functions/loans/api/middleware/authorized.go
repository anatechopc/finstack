package middleware

import (
	"go.uber.org/zap"
	defaultLog "log"
	"net/http"
)

func init() {
	logger, err := zap.NewDevelopment()

	if err != nil {
		defaultLog.Fatalf(err.Error())
		return
	}

	log = logger.Named("authorized")
	log.Sync()
}

func ValidateRequest(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Info("validate request here!")
		// Do stuff here
		log.Info(r.RequestURI)
		// Call the next handler, which can be another middleware in the chain, or the final handler.
		next.ServeHTTP(w, r)
	})
}
