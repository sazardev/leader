package app

import "os"

func Sizes(paths []string) ([]int64, error) {
	var out []int64
	for _, p := range paths {
		f, err := os.Open(p)
		if err != nil {
			return nil, err
		}
		defer f.Close()
		st, err := f.Stat()
		if err != nil {
			return nil, err
		}
		out = append(out, st.Size())
	}
	return out, nil
}
