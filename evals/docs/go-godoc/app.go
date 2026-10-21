package app

import "strings"

func Initials(name string) string {
	var out []string
	for _, part := range strings.Fields(name) {
		out = append(out, strings.ToUpper(part[:1]))
	}
	return strings.Join(out, "")
}
