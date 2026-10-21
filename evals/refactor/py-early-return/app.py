def first_even(items):
    result = None
    if items:
        for item in items:
            if item % 2 == 0:
                result = item
                break
    return result
