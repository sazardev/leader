def summarize(d):
    result = {}
    for key in d:
        value = d[key]
        if value is not None:
            result[key] = round(value * 100) / 100
    total = 0
    for key in result:
        total = total + result[key]
    return result, total
