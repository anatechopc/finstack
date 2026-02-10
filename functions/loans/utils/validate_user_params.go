package utils

import "com.loooans.app/types"

func ValidateUser(user types.User) bool {
	return user.Email != "" && user.Password != "" && user.DisplayName != ""
}
