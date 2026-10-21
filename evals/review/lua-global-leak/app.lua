local M = {}

function M.collect(list)
  result = {}
  for _, v in ipairs(list) do
    if v > 0 then
      result[#result + 1] = v
    end
  end
  return result
end

return M
