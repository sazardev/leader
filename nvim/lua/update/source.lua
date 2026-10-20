-- ── Where updates are looked up ──────────────────────────────────────────────
-- GitHub, without its API (no rate limit, no token): the raw `VERSION` and `CHANGELOG.md` of the branch the config
-- follows, and the redirect of `releases/latest` for the desktop app's own release. One tiny request tells whether
-- anything is new; the changelog is only downloaded when it is. Every request has a timeout and fails quietly (no
-- network is not an error worth a message). `settings.update.base` / `.releases` point it elsewhere (a mirror, a test).
local semver = require "update.semver"

local M = {}

---@param cfg table settings.update
---@return string base url of the raw files
function M.base(cfg)
  return cfg.base or ("https://raw.githubusercontent.com/%s/%s"):format(cfg.repo, cfg.branch)
end

---@param cfg table
---@return string? url of releases/latest
function M.releases(cfg)
  if cfg.releases == false then
    return nil
  end
  return cfg.releases or ("https://github.com/%s/releases/latest"):format(cfg.repo)
end

--- GET `url`; calls back with the body or nil + a reason.
---@param url string
---@param cb fun(body: string?, err: string?)
local function get(url, cb)
  local ok = pcall(function()
    vim.system({ "curl", "-fsSL", "--connect-timeout", "6", "--max-time", "15", url }, { text = true }, function(res)
      vim.schedule(function()
        if res.code == 0 then
          cb(res.stdout, nil)
        else
          cb(nil, vim.trim(res.stderr or "") ~= "" and vim.trim(res.stderr) or ("curl exited " .. res.code))
        end
      end)
    end)
  end)
  if not ok then
    cb(nil, "curl is not available")
  end
end

--- The tag `releases/latest` redirects to ("v1.7.0"), without following it.
---@param url string
---@param cb fun(tag: string?)
local function release_tag(url, cb)
  local ok = pcall(function()
    vim.system(
      { "curl", "-s", "-o", "/dev/null", "--connect-timeout", "6", "--max-time", "12", "-w", "%{redirect_url}", url },
      { text = true },
      function(res)
        vim.schedule(function()
          local tag = res.code == 0 and (res.stdout or ""):match "/tag/([^/%s]+)%s*$" or nil
          cb(tag and semver.clean(tag) or nil)
        end)
      end
    )
  end)
  if not ok then
    cb(nil)
  end
end

---@class UpdateInfo
---@field version string the newest config version
---@field changelog string? CHANGELOG.md, only when `version` is newer than `current`
---@field release string? the newest published desktop app release

--- Looks everything up.
---@param cfg table settings.update
---@param current string the installed config version (the changelog is fetched only when `version` is newer)
---@param cb fun(info: UpdateInfo?, err: string?)
function M.fetch(cfg, current, cb)
  get(M.base(cfg) .. "/VERSION", function(body, err)
    local version = body and semver.parse(vim.trim(body)) and semver.clean(body) or nil
    if not version then
      return cb(nil, err or "no version found")
    end
    local info = { version = version }
    local pending = 1
    local function done()
      pending = pending - 1
      if pending == 0 then
        cb(info, nil)
      end
    end
    if semver.newer(version, current) then
      pending = pending + 1
      get(M.base(cfg) .. "/CHANGELOG.md", function(text)
        info.changelog = text
        done()
      end)
    end
    local releases = M.releases(cfg)
    if releases then
      pending = pending + 1
      release_tag(releases, function(tag)
        info.release = tag
        done()
      end)
    end
    done()
  end)
end

return M
