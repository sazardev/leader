def fetch(url, retries=3, timeout=10.0):
    for attempt in range(retries):
        try:
            return _get(url, timeout)
        except TimeoutError:
            if attempt == retries - 1:
                raise


def _get(url, timeout):
    raise NotImplementedError
