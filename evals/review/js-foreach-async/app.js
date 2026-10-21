async function saveAll(items, save) {
  items.forEach(async (item) => {
    await save(item);
  });
  return items.length;
}
