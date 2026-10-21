package app

import "fmt"

func Div(a, b int) int {
	if b == 0 {
		panic("division by zero")
	}
	fmt.Println("dividing", a, b)
	return a / b
}
