package app

import "testing"

func TestGrade(t *testing.T) {
	cases := map[int]string{-1: "invalid", 0: "fail", 49: "fail", 50: "pass", 100: "pass", 101: "invalid"}
	for in, want := range cases {
		if got := Grade(in); got != want {
			t.Fatalf("Grade(%d) = %q, want %q", in, got, want)
		}
	}
}
