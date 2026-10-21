function sum(values) {
  let total = 0;
  for (const v of values) {
    total += v;
  }
  return total;
}

module.exports = { sum };
