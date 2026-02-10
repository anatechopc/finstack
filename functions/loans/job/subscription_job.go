package job

import (
	"cloud.google.com/go/firestore"
	"cloud.google.com/go/firestore/apiv1/firestorepb"
	"com.loooans.app/utils"
	"context"
	"encoding/json"
	"fmt"
	"google.golang.org/api/iterator"
	"io"
	"math"
	"net/http"
	"os"
	"time"
)

// eyJhbGciOiJSUzI1NiIsImtpZCI6IjQ4YTYzYmM0NzY3Zjg1NTBhNTMyZGM2MzBjZjdlYjQ5ZmYzOTdlN2MiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20iLCJhenAiOiIzMjU1NTk0MDU1OS5hcHBzLmdvb2dsZXVzZXJjb250ZW50LmNvbSIsImF1ZCI6IjMyNTU1OTQwNTU5LmFwcHMuZ29vZ2xldXNlcmNvbnRlbnQuY29tIiwic3ViIjoiMTA1MjA3OTkxNzExOTIxNzYzMTI0IiwiaGQiOiJhbmFoZWltdGVjaG5vbG9naWVzLmNvbSIsImVtYWlsIjoiZGFmZHVsZHVsYW9AYW5haGVpbXRlY2hub2xvZ2llcy5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwiYXRfaGFzaCI6IjNhNWtDNGdndnBSTkM4N0xQSGtFQnciLCJpYXQiOjE3MDU1Mzg5MjgsImV4cCI6MTcwNTU0MjUyOH0.VCLBuuoBa6n1WtsPjQLSVfkl-yWqBHS_UABJRcizAtP-hlNSknx9CjQvQ55_DjqwEPzXP39dI3cKUG96KUMCBLG6o2SGc77ey3TEKqQ9N7hM1dPVc5Zen2ic-gCHSC6yyILcHj5kHS8H_23JdtxF_rTu83IfYlPE9Hckuu1SpGrOT6LRvKgMP9HtJAl1-Q9r2F8csJJyLCTa_FLsY8ym7jqIkpKBjIaY2jF9EDFwXY2GGg3RfU-sUQTRLQlNkGPc20axAiS_nFDlOKyq-DbXKajJin1wZ6T1JLtM_P5uwuGhMAIwMVCKqHxFQNu0j1FzU87Tm0-M8-woX5X_ncSM1w

// SubscriptionJob - A cron job that checks all subscription related tasks
// like:
//   - Bill creation
//   - Subscription validation
//
// This job runs everyday at 00:00:00
// Note: this function should only be called in cron job (Google cloud scheduler)
func SubscriptionJob(w http.ResponseWriter, r *http.Request) {
	log, errLog := utils.InitializeLogger("subscription_job")

	if errLog != nil {
		http.Error(w, errLog.Error(), http.StatusInternalServerError)
		return
	}

	log.Debug("checking cors")
	// cors
	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "POST")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.Header().Set("Access-Control-Max-Age", "3600")
		w.WriteHeader(http.StatusNoContent)
		return
	}

	w.Header().Set("Access-Control-Allow-Credentials", "true")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	// cors done

	//if !utils.ValidateRequest(w, r) {
	//	return
	//}

	log.Debug("Checking http method")
	if r.Method != http.MethodPost {
		http.Error(w, "Use POST method", http.StatusBadRequest)
		return
	}

	body, errBody := io.ReadAll(r.Body)

	defer r.Body.Close()

	log.Debug("Reading body")
	if errBody != nil {
		http.Error(w, errBody.Error(), http.StatusBadRequest)
		return
	}

	var parsedBody map[string]any
	errJson := json.Unmarshal(body, &parsedBody)

	if errJson != nil {
		http.Error(w, errJson.Error(), http.StatusInternalServerError)
		return
	}

	jobSource := parsedBody["source"]

	log.Debug("Checking source")
	if jobSource != nil {
		if fmt.Sprint(jobSource) != "job" {
			log.Error(fmt.Sprintf("Not a Job. Source: %s", jobSource))
			http.Error(w, "Not a Job.", http.StatusBadRequest)
			return
		}
	}

	log.Debug("Initializing firebase")
	ctx := context.Background()
	app, errFirebaseAdmin := utils.InitializeFirebase(ctx)

	if errFirebaseAdmin != nil {
		log.Error("error initialize firebase admin: " + errFirebaseAdmin.Error())
		http.Error(w, "Firebase admin initialization error: "+errFirebaseAdmin.Error(), http.StatusInternalServerError)
		return
	}

	env := os.Getenv("ENVIRONMENT")
	subdomain := ""
	collectionPrefix := ""

	switch env {
	case "development":
		subdomain = "dev."
		collectionPrefix = "dev_"
		break
	case "staging":
		subdomain = "stg."
		collectionPrefix = "stg_"
		break
	}

	fsClient, errFirestoreClient := app.Firestore(ctx)

	if errFirestoreClient != nil {
		log.Error("error fsClient client: " + errFirestoreClient.Error() + subdomain)
		http.Error(w, "error fsClient client: "+errFirestoreClient.Error(), http.StatusInternalServerError)
		return
	}

	// functions
	/**
	check if n days has elapsed from the date in milliseconds
	*/
	isNDays := func(n int, compareMillis int64) bool {
		now := time.Now()
		validUntil := time.UnixMilli(compareMillis)
		day := 24 * time.Hour

		log.Debug(fmt.Sprintf("isNDays: math.Round(validUntil.Sub(now).Hours())", math.Round(validUntil.Sub(now).Hours())))
		log.Debug(fmt.Sprintf("isNDays: (day.Hours() * float64(n))", day.Hours()*float64(n)))

		return math.Round(validUntil.Sub(now).Hours()) == (day.Hours() * float64(n))
	}

	getUsers := func(companyId string, onlyAdmin bool) []map[string]interface{} {
		/**
		Currently, we have these user roles:
		  UserRole.customer: 'customer',
		  UserRole.delivery: 'delivery',
		  UserRole.sales: 'sales',
		  UserRole.office: 'office',
		  UserRole.admin: 'admin',
		  UserRole.superUser: 'superUser',
		  UserRole.warehouseManager: 'warehouseManager',
		  UserRole.supplier: 'supplier',
		For this query, we only need to exclude superUser, customer and supplier
		since they are not part of the company.

		The user roles may grow and we may introduce new user roles in the
		future.

		TODO: find a way to query for all roles except for the following:
			superUser,
			customer,
			supplier.

		*/
		roles := []string{
			"delivery",
			"sales",
			"office",
			"admin",
			"warehouseManager",
		}

		if onlyAdmin {
			roles = []string{
				"admin",
			}
		}

		users, _ := fsClient.Collection(collectionPrefix+"users").
			Where("company_id", "==", companyId).
			Where("user_roles", "array-contains-any", roles).
			Where("deleted_at", "==", nil).
			//Where("user_roles", "not-in", []interface{}{[]string{"superUser", "customer", "supplier"}}).
			Documents(ctx).
			GetAll()

		var mappedUsers []map[string]interface{}

		for _, user := range users {
			mappedUser := user.Data()
			mappedUsers = append(mappedUsers, mappedUser)
		}

		return mappedUsers
	}

	getVehicleCount := func(companyId string) int64 {

		where := fsClient.Collection(collectionPrefix+"vehicles").
			Where("company_id", "==", companyId).
			Where("deleted_at", "==", nil)
		result, _ := where.NewAggregationQuery().WithCount("all").Get(ctx)

		count := int64(0)

		countResult, ok := result["all"]
		if !ok {
			log.Error("Could not get COUNT for vehicles")
			count = 0
		} else {
			count = countResult.(*firestorepb.Value).GetIntegerValue()
		}

		return count
	}

	getPricingConfig := func(company map[string]interface{}) map[string]interface{} {
		return company["pricing"].(map[string]interface{})
	}

	createBill := func(company map[string]interface{}, userCount int64, vehicleCount int64) string {
		type data map[string]interface{}

		parseParticulars := func(particulars []interface{}) []data {
			p := []data{}

			for _, particular := range particulars {
				part := particular.(map[string]interface{})
				p = append(p, part)
			}

			return p
		}

		companyId := company["id"].(string)
		log.Info("creating bill for " + companyId)
		pricing := getPricingConfig(company)
		userSubscriptionPrice := 0.0
		vehicleSubscriptionPrice := 0.0
		price, ok := pricing["user_subscription_price"].(int64)
		vPrice, vOk := pricing["vehicle_subscription_price"].(int64)

		if !ok {
			userSubscriptionPrice = pricing["user_subscription_price"].(float64)
		} else {
			userSubscriptionPrice = float64(price)
		}

		if !vOk {
			vehicleSubscriptionPrice = pricing["vehicle_subscription_price"].(float64)
		} else {
			vehicleSubscriptionPrice = float64(vPrice)
		}

		nextBillId := company["next_bill_id"]
		var billDoc *firestore.DocumentRef
		now := time.Now()
		var bill data
		var particulars []data
		currentBillAmount := 0.0

		if nextBillId == nil {
			billDoc = fsClient.Collection(collectionPrefix + "bills").NewDoc()
			bill = make(data)
			bill["created_at"] = now.UnixMilli()
			bill["client_id"] = companyId
			bill["start_date"] = company["valid_until"]
			bill["due_date"] = company["valid_until"]
			bill["id"] = billDoc.ID
		} else {
			billDoc = fsClient.Collection(collectionPrefix + "bills").Doc(nextBillId.(string))
			billData, _ := billDoc.Get(ctx)
			someBill := billData.Data()
			bill = someBill
			fmt.Printf("Document data: %#v\n", someBill)
			someParticulars, _ := someBill["particulars"].([]interface{})
			particulars = parseParticulars(someParticulars)
			fmt.Printf("Document data: %#v\n", someParticulars)
			currentBillAmount = bill["amount"].(float64)
		}

		particularUser := data{
			"particular": "Users",
			"price":      userSubscriptionPrice,
			"quantity":   userCount,
		}

		particularVehicle := data{
			"particular": "Vehicles",
			"price":      vehicleSubscriptionPrice,
			"quantity":   vehicleCount,
		}

		particulars = append(particulars, particularUser)
		particulars = append(particulars, particularVehicle)

		userTotalAmount := userSubscriptionPrice * float64(userCount)
		vehicleTotalAmount := vehicleSubscriptionPrice * float64(vehicleCount)

		bill["updated_at"] = now.UnixMilli()
		bill["amount"] = currentBillAmount + userTotalAmount + vehicleTotalAmount
		bill["particulars"] = particulars
		bill["end_date"] = time.UnixMilli(company["valid_until"].(int64)).AddDate(0, 1, 0).UnixMilli()

		billDoc.Set(ctx, bill)

		return billDoc.ID
	}

	getAdminEmails := func(users []map[string]interface{}) []string {
		var adminEmails = []string{}

		transformUserRoles := func(userRoles []interface{}) []string {
			var transformed = []string{}

			for _, userRole := range userRoles {
				transformed = append(transformed, userRole.(string))
			}

			return transformed
		}

		for _, user := range users {
			userRoles := transformUserRoles(user["user_roles"].([]interface{}))

			for _, role := range userRoles {
				if role == "admin" {
					adminEmails = append(adminEmails, user["email"].(string))
				}
			}
		}

		return adminEmails
	}
	// end functions

	companiesIter := fsClient.Collection(collectionPrefix+"companies").
		Where("type", "==", "client").
		Where("pricing.user_subscription_tier", "!=", "free").
		Documents(ctx)

	defer companiesIter.Stop()
	// https://golang.cafe/blog/golang-time-format-example.html
	// Seems formatting in Go is very different from other languages.
	// Make sure to follow the time set in the link.
	dateFormat := "Monday, January 2 2006"

	for {
		doc, err := companiesIter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			log.Error(err.Error())
			break
		}

		company := doc.Data()
		validUntil := company["valid_until"].(int64)
		validUntilTime := time.UnixMilli(validUntil)

		users := getUsers(company["id"].(string), false)
		vehicleCount := getVehicleCount(company["id"].(string))
		createBill(company, int64(len(users)), vehicleCount)

		if isNDays(15, validUntil) {
			users := getUsers(company["id"].(string), false)
			vehicleCount := getVehicleCount(company["id"].(string))
			billId := createBill(company, int64(len(users)), vehicleCount)
			// update company next bill id
			fsClient.Collection(collectionPrefix+"companies").
				Doc(company["id"].(string)).
				Update(ctx, []firestore.Update{{Path: "next_bill_id", Value: billId}})

			// get admins here
			adminEmails := getAdminEmails(users)

			// url something like /invoice/{billId}
			/**
			NOTE: Message to admins
				Hi there!

				Your bill is ready.

				Please pay the subscription on or before {date here} to avoid service deactivation.
				Please be reminded that payment validation is up to 48 hours.

				Thank you

				Regards,
				Ayooo! Team
			*/
			utils.SendEmail("Your bill is ready", fmt.Sprintf("<p>Hi there!</p><p>Your bill is ready.</br>Please pay the subscription on or before %s to avoid service deactivation.</br>Please be reminded that payment validation is up to 48 hours.</br>Check out your bill at https://%scom.loooans.com/invoice/%s</p><p>Thank you</p><p>Regards,</br>Ayooo! Team</p></br><p>NOTE: This is an auto-generated email. Do not respond</p>", validUntilTime.Format(dateFormat), subdomain, billId), adminEmails)
		} else if isNDays(0, validUntil) {
			// send email reminding user of the current bill.;
			users := getUsers(company["id"].(string), true)
			adminEmails := getAdminEmails(users)
			/**
			NOTE: Message to admins
				Hi there!

				Your bill is due today.
				Please pay the subscription to avoid service deactivation.
				Please be reminded that payment validation is up to 48 hours.

				Thank you

				Regards,
				Ayooo! Team
			*/
			utils.SendEmail("Your bill is due today", fmt.Sprintf("<p>Hi there!</p><p>Your bill is due today.</br>Please pay the subscription to avoid service deactivation.</br>Please be reminded that payment validation is up to 48 hours.</p><p>Thank you</p><p>Regards,</br>Ayooo! Team</p></br><p>NOTE: This is an auto-generated email. Do not respond</p>"), adminEmails)
		} else {
			//check if now == validUntil + 48 hour duration
			now := time.Now()
			// time extension of validity
			timeExtension := 48 * time.Hour
			extendedValidity := time.UnixMilli(validUntil).Add(timeExtension)

			if extendedValidity.Sub(now).Hours() == 0 {
				// check current bill payment
				// it is the 48th hour
				// forceLogout = true
				// email client
				db, errDb := app.Database(ctx)
				if errDb != nil {
					log.Error("error realtime db: " + errDb.Error())
					http.Error(w, "Realtime DB error: "+errDb.Error(), http.StatusInternalServerError)
					return
				}

				dbRef := db.NewRef(fmt.Sprintf("companies/%s/authentication/force_logout", company["id"].(string)))
				dbRefErr := dbRef.Set(ctx, true)

				if dbRefErr != nil {
					log.Error("error realtime db ref: " + dbRefErr.Error())
					http.Error(w, "Realtime DB ref error: "+dbRefErr.Error(), http.StatusInternalServerError)
					return
				}

				users := getUsers(company["id"].(string), true)
				adminEmails := getAdminEmails(users)
				/**
				NOTE: Message to admins
					Hi there!

					Your Ayooo! service is restricted.
					Please pay the subscription to activate your service. Your service will be activated after payment validation.
					Please be reminded that payment validation is up to 48 hours.

					Thank you

					Regards,
					Ayooo! Team
				*/
				utils.SendEmail("Your missed your bill", fmt.Sprintf("<p>Hi there!</p><p>Your Ayooo! service is restricted.</br>Please pay the subscription to activate your service Your service will be activated after payment validation.</br>Please be reminded that payment validation is up to 48 hours.</p><p>Thank you</p><p>Regards,</br>Ayooo! Team</p></br><p>NOTE: This is an auto-generated email. Do not respond</p>"), adminEmails)
			}
		}
	}

	log.Info("Job executed successfully")
}
