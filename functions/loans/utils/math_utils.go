package utils

import "math"

// RoundFloat Rounds the float to the nearest decimal places
func RoundFloat(val float64, precision uint) float64 {
	ratio := math.Pow(10, float64(precision))
	return math.Round(val*ratio) / ratio
}
