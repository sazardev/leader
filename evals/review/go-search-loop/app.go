package app

func Search(sorted []int, target int) int {
	lo, hi := 0, len(sorted)-1
	for lo <= hi {
		mid := lo + (hi-lo)/2
		switch {
		case sorted[mid] == target:
			return mid
		case sorted[mid] < target:
			lo = mid
		default:
			hi = mid - 1
		}
	}
	return -1
}
