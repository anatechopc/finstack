package users

import "com.loooans.app/api/service"

// GenerateOtpForTest re-exports service.GenerateOtp for use by external test
// packages (e.g., users_test). Allows tests to produce a (hash, otp) pair
// that survives the real service.VerifyOtp check.
func GenerateOtpForTest() (string, string, error) {
	return service.GenerateOtp()
}
