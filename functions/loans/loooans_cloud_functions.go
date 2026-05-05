package loooans_cloud_functions

import (
	"com.loooans.app/api/users"
	"com.loooans.app/triggers"
	"com.loooans.app/utils"
	"github.com/GoogleCloudPlatform/functions-framework-go/funcframework"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"go.uber.org/zap"
	"os"
)

var log *zap.Logger

func init() {
	log, _ = utils.InitializeLogger("loooans_cloud_functions")
	// ignore sync errors as per comment: https://github.com/uber-go/zap/issues/328#issuecomment-284337436
	log.Sync()

	log.Info("init")
	//functions.HTTP("CORSEnabledFunction", middleware.CORSEnabledFunction)
	// ---- cloud functions ---- //
	//functions.HTTP("addUser", users.AddUser)
	//functions.HTTP("updateUser", users.UpdateUser)
	functions.HTTP("requestOtp", users.RequestOtp)
	functions.HTTP("verifyOtp", users.VerifyOtp)
	//functions.HTTP("verifyUserEmail", users.VerifyUserEmail)
	//functions.HTTP("updateUserEmail", users.UpdateUserEmail)
	functions.HTTP("sendEmail", utils.SendEmailHttp)
	functions.HTTP("sometest", users.SomeTest)

	// ---- job ---- //
	//functions.HTTP("subscriptionJob", job.SubscriptionJob)

	// ---- cloud functions triggers (firestore) ---- //
	functions.CloudEvent("userCreated", triggers.UserCreated)
	functions.CloudEvent("loanChanges", triggers.LoanChanges)
	functions.CloudEvent("loanScheduleChanges", triggers.LoanScheduleChanges)
	functions.CloudEvent("capitalCreated", triggers.CapitalCreated)
	functions.CloudEvent("notificationCreated", triggers.NotificationCreated)
	functions.CloudEvent("reviewCreated", triggers.ReviewCreated)
	functions.CloudEvent("paymentCreated", triggers.PaymentCreated)
	functions.CloudEvent("userChanges", triggers.UserChanges)

	log.Info("added cloud functions")
	start()
}

func start() {
	log.Info("start")
	env := ""

	// check if we are running on the correctly predefined environment
	// exit if not.
	// predefined environment are:
	// 	development
	// 	staging
	// 	production
	if env = os.Getenv("ENVIRONMENT"); env == "" {
		log.Fatal("Runtime environment not defined")
		os.Exit(1)
	}

	log.Info("Running on " + env + " Environment")
	// Use PORT environment variable, or default to 8080.
	port := "8080"
	if envPort := os.Getenv("PORT"); envPort != "" {
		port = envPort
	}

	log.Info("Listening to port: {port}", zap.String("port", port))

	if err := funcframework.Start(port); err != nil {
		log.Fatal("funcframework.Start: {err}\n", zap.String("err", err.Error()))
	}
}
