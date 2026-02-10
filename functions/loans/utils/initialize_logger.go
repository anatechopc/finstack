package utils

import (
	"go.uber.org/zap"
	defaultLog "log"
	"os"
)

func InitializeLogger(name string) (*zap.Logger, error) {
	env := os.Getenv("environment")
	var logger *zap.Logger
	var err error

	if env == "production" {
		logger, err = zap.NewProduction()
	} else {
		logger, err = zap.NewDevelopment()
	}

	if err != nil {
		defaultLog.Fatal(err.Error())
		return nil, err
	}

	log := logger.Named(name)
	// ignore sync errors as per comment: https://github.com/uber-go/zap/issues/328#issuecomment-284337436
	log.Sync()

	return log, nil
}
