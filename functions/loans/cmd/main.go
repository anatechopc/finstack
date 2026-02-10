package main

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

	log.Info("added cloud functions")
}

func main() {
	log.Info("starting")
	env := ""

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
	//router := mux.NewRouter()
	//userRoute := router.PathPrefix("/users").Subrouter()
	//userRoute.HandleFunc("/add", users.AddUser)
	//userRoute.HandleFunc("/update", users.UpdateUser)
	//
	//router.Use(middleware.ValidateRequest)
	//
	//router.Schemes("https")
	//
	//srv := &http.Server{
	//	Addr: "0.0.0.0:8080",
	//	// Good practice to set timeouts to avoid Slowloris attacks.
	//	WriteTimeout: time.Second * 15,
	//	ReadTimeout:  time.Second * 15,
	//	IdleTimeout:  time.Second * 60,
	//	Handler:      router, // Pass our instance of gorilla/mux in.
	//}
	//
	//err := srv.ListenAndServe()
	//
	//if err != nil {
	//	log.Fatal("something error")
	//	log.Fatal(err.Error())
	//	os.Exit(1)
	//}
}
