def moving_sum(values, size):
    sums = []
    for i in range(len(values) - size + 2):
        sums.append(sum(values[i:i + size]))
    return sums
