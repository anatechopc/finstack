package service

// /*
import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"
	"strconv"
	"time"
)

func generateSalt() string {
	randomBytes := make([]byte, 16)
	_, err := rand.Read(randomBytes)
	if err != nil {
		return ""
	}
	return base64.URLEncoding.EncodeToString(randomBytes)
}

func generateHash() string {
	secretKey := "Loooans! app the greatest application in the universe!"
	message := time.Now().UTC().String()
	salt := generateSalt()

	hash := hmac.New(sha256.New, []byte(secretKey))
	io.WriteString(hash, message+salt)
	//fmt.Printf("\nHMAC-Sha256: %x", hash.Sum(nil))

	return fmt.Sprintf("%x", hash.Sum(nil))

	//hash = hmac.New(sha512.New, []byte(secretKey))
	//io.WriteString(hash, message+salt)
	//fmt.Printf("\n\nHMAC-sha512: %x", hash.Sum(nil))
}

func GenerateOtp() (string, string, error) {
	hashStr := generateHash()
	otp, err := getOtp(hashStr)

	if err != nil {
		return "", "", err
	}

	return hashStr, otp, nil
}

func getOtp(hashStr string) (string, error) {
	lastChar := string(hashStr[len(hashStr)-1])
	offset, _ := strconv.ParseInt(lastChar, 16, 64)

	// offset is multiplied by 2 to determine the exact index from the
	// hexStr.
	// a character is represented by 4 bits, the hex grouping is by bytes.
	// which is, a hex group consists of 2 characters.
	positionStart := offset * 2
	// position end is determined by the next 31 bits from the start.
	// So, from the start, there will be 8 characters.
	positionEnd := positionStart + 8
	hexForOtp := hashStr[positionStart:positionEnd]
	//fmt.Println("hexForOtp: ", hexForOtp)

	conv, err := strconv.ParseInt(hexForOtp, 16, 64)
	//fmt.Println("conv: ", conv)

	if err != nil {
		return "", err
	}

	converted := fmt.Sprintf("%d", conv)
	//fmt.Printf("converted: %s\n", converted)
	otp := converted[len(converted)-6:]
	//fmt.Println("some: ", some)

	return otp, nil
}

func VerifyOtp(hashStr string, receivedOtp string) (bool, error) {
	otp, err := getOtp(hashStr)

	if err != nil {
		return false, err
	}

	return otp == receivedOtp, nil
}
