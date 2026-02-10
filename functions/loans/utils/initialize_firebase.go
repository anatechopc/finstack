package utils

import (
	"com.loooans.app/types"
	"context"
	"encoding/json"
	firebase "firebase.google.com/go/v4"
	"google.golang.org/api/option"
	"os"
	"strings"
)

// InitializeFirebase functions that initializes firebase app
//
// since we are hosting the cloud function in google, it automatically
// looks for the firebase project within the cloud infrastructure.
func InitializeFirebase(ctx context.Context) (*firebase.App, error) {
	dbUrl := "https://loooans-dev-stg-default-rtdb.asia-southeast1.firebasedatabase.app"
	//firOptsEnv := os.Getenv("FIR_OPTS")
	//fmt.Printf("firOptsEnv: %s", firOptsEnv)
	firOptsEnv := `{
  "type": "service_account",
  "project_id": "loooans-dev-stg",
  "private_key_id": "2a8c7ca0b3d977c84765e01f0646a160d8707570",
  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDxY0FVuC1w1YOo\nwVipxQtAIprHRuz+Lttmvh+bKSytRxorez2e5NDhBx+E0K5VdkuQBYksQOIfV/mQ\nxFxcSTs979yv497o1+RayWLl3sLmQ/k1912jSGP1rjBc+4bnkDArnmZkZ6Agd/GV\nncgAt/CBTilGfihkYRlpLzKJYX1QKQEpQAcGAx5Z95ozSGa4dZrk53nxvHtH2Y4H\nXvAf+ZKmk0ESP4Oo563c/jzGn2Yed+b42kYhJ/A32+lTOjy1AncQYD/xbFV+Ei0w\nceBBUyZ0lVeutc+sQFg1pnKRmLIrhqaWXNq4qrX+cBldMcvruR7EtCAbwPq5FdvK\nwJi54eLXAgMBAAECggEACJ63GOeLKooFZJkFoIe6f3TSOtGL6bEkq/DtfK37Zsiw\n5OKcGw4oGLvCDWJ3sfJCf9x4FI4l77aa4TznNh3LXB/dAqRMM9vEeirSOaE7K9vm\nN14jsuQFOyMYSQnBEd3dSoF36Jf8E4y/oiHQoENGobzNI95MykuJYRngCnXicrf3\nt+/60i+TYJEBWIZTAKCoCmjMGNrW1R15RJkAhqCKsSfDSw0BmkptVwGyFRQRexJG\nYGJGW0gwhjNdMT3Ggi2TdZOm6PibJCL3WfPcX0AFn2oOsHntcCAcoAQMg91fnRDp\nxHvN9z1YJgEiCtAXoHulM0oZmhkb1/gAu0w08o46qQKBgQD8oCDP27SDw0SSY28m\n+weGaHXQFqPZvj0SwChF4vI9CDYUjmbmziLQ9M/+jmuHz+BxdaEHXhLcuzypO3ia\n9FSLN9XzoebDXe6kD7EvjqEmU46zHYMzvwRSMpICozOm08ORPjPtIzUcp4l89YJ6\npMbPpc82sc6swuNokcMkWOXDswKBgQD0nLLXGysZ5gkN19Vc4N84uOEb6SQdQhy2\njsJNFPxlu0PbTEgddc1mI5whQcaRI1aB8m88xMXULrcEX+sUgPiP8d6CNM/CP0QB\npNTazK+k9m/TEiIHOov5vy/MceOWlGnqWUObB2fiHbKTE6AHO5O5hiiGNyZqSMOQ\nuVfaiPbiTQKBgGuanT9MOwCgzPV5qx+0b0kd94iyDAq0UHlLJhxWhY3fkIGDAmuv\nQ/8zN+Eassy/i79oNjXYKTqh+j2vWjjOd7BxEQ3cWVnACeUR1gwGubeEgdTjbj49\nT87fQXgkId0eeD/GegG5LGdPKW3zeSdaRmCuJKwMYpcN0CV7aN5zizKnAoGBAOye\nA7Vmd3v29D0q0h6k++jflgmsrZ2LzUCeub9clIZH7mzczkmJIaYyvh3BhbXxzAWp\noQbUhVUp1ynpKvpLg6WiXw3uziXlkwBQFQKNyz40kJlJShdZ//sXgMIwTOnlKMtj\ni60ULd4hwhLZggxdChoFd3/VK1jWiC6fyyb/JGplAoGASKY5QUASffd8Zl520kN2\nszbB6cUnVU7Oln/vSl4zHVDSuMWm93PeH2LgF16yHuCPeSsQ33Km3D0Sub7ge9aD\nUy8l5JfY3r0V6YiNn6pi+9+V5h3fmur4WIC6J0fpSOYiK/MHL7wgflECz6pBncLz\nSOwT/un07j+nZJ/R1Tjx9q0=\n-----END PRIVATE KEY-----\n",
  "client_email": "firebase-adminsdk-bqdg7@loooans-dev-stg.iam.gserviceaccount.com",
  "client_id": "114693679321187723573",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-bqdg7%40loooans-dev-stg.iam.gserviceaccount.com",
  "universe_domain": "googleapis.com"
}`
	var firOpts types.FirebaseOptions

	if err := json.NewDecoder(strings.NewReader(firOptsEnv)).Decode(&firOpts); err != nil {
		return nil, err
	}

	optBytes, optErr := json.Marshal(firOpts)

	if optErr != nil {
		return nil, optErr
	}

	opt := option.WithCredentialsJSON(optBytes)

	env := os.Getenv("ENVIRONMENT")

	switch env {
	case "production":
		dbUrl = "https://loooans-prod-default-rtdb.asia-southeast1.firebasedatabase.app"
		break
	}

	conf := &firebase.Config{
		DatabaseURL: dbUrl,
	}

	app, err := firebase.NewApp(ctx, conf, opt)

	if err != nil {
		return nil, err
	}

	return app, nil
}
