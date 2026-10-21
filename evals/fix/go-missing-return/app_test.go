package app

import "testing"

func TestSign(t *testing.T) {
	if Sign(5) != 1 || Sign(-5) != -1 || Sign(0) != 0 {
		t.Fatal("wrong sign")
	}
}
