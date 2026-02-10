package utils

import (
	"encoding/json"
	"io"
	"net/http"
)

func TestReceive(w http.ResponseWriter, r *http.Request) {
	defer r.Body.Close()

	body, err := io.ReadAll(r.Body)

	if err != nil {
		print("error: " + err.Error())
	}

	print("url:")
	println(r.URL.String())
	print("body:")
	println(string(body))

	json.NewEncoder(w).Encode(map[string]any{
		"message": "success",
	})
}
