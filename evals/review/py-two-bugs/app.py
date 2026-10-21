def top_scores(scores, n):
    """Return the n highest scores, best first, without changing the input."""
    scores.sort(reverse=True)
    best = []
    for i in range(n + 1):
        best.append(scores[i])
    return best
