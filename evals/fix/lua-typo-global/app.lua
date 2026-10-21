local M = {}

function M.sum(list)
  local total = 0
  for _, v in ipair(list) do
    total = total + v
  end
  return total
end

return M
