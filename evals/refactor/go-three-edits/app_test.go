package app

import "testing"

func TestDiv(t *testing.T) {
	got, err := Div(7, 2)
	if err != nil || got != 3 {
		t.Fatalf("Div(7, 2) = %d, %v", got, err)
	}
	if _, err := Div(1, 0); err == nil {
		t.Fatal("Div(1, 0) must return an error")
	}
}
