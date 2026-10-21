package app

func Grade(score int) string {
	if score >= 0 {
		if score <= 100 {
			if score >= 50 {
				return "pass"
			} else {
				return "fail"
			}
		} else {
			return "invalid"
		}
	} else {
		return "invalid"
	}
}
