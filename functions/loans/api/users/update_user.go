package users

import (
	"com.loooans.app/utils"
	"encoding/json"
	"net/http"
)

func UpdateUser(w http.ResponseWriter, r *http.Request) {
	log, errLog := utils.InitializeLogger("update_user")

	if errLog != nil {
		http.Error(w, errLog.Error(), http.StatusBadRequest)
		return
	}

	log.Info("updating user")

	something := make(map[string]any)

	something["update"] = "hello update"

	json.NewEncoder(w).Encode(something)
}
