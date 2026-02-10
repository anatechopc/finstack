package utils

import "os"

func GetCollectionPrefix() string {
	env := os.Getenv("ENVIRONMENT")
	collectionPrefix := ""

	switch env {
	case "development":
		collectionPrefix = "dev_"
		break
	case "staging":
		collectionPrefix = "stg_"
		break
	}

	return collectionPrefix
}

func GetSubdomain() string {
	env := os.Getenv("ENVIRONMENT")
	subdomain := ""

	switch env {
	case "development":
		subdomain = "dev."
		break
	case "staging":
		subdomain = "stg."
		break
	}

	return subdomain
}

func GetMinifiedEnv() string {
	env := os.Getenv("ENVIRONMENT")
	pathEnv := ""

	switch env {
	case "development":
		pathEnv = "dev"
		break
	case "staging":
		pathEnv = "stg"
		break
	}

	return pathEnv
}
