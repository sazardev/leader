-- ── Python import catalog and buffer edits (0 tokens) ─────────────────────────
-- Pure data and logic shared by the `pysmart` completion source and the Python menu. One row per import: what the
-- user types (label/words), the statement to insert, and the package that must be installed for it to resolve.
-- Inserting an import means adding a LINE at the top of the file (module docstring / __future__ / existing imports),
-- never at the cursor: the cursor keeps the alias the user already typed. Nothing here starts a process.
local M = {}

---@class PyImport
---@field id string stable key
---@field group string group in the picker
---@field label string what completion inserts
---@field line string statement added at the top of the file
---@field detail string short description
---@field words string[] extra prefixes that match this row
---@field package string top-level package (for the installed check)
---@field auto boolean? false = never insert it just because the alias was typed (ambiguous short names)

--- @type PyImport[]
local CATALOG = {
  {
    id = "numpy",
    group = "Core",
    label = "np",
    line = "import numpy as np",
    detail = "arrays, math",
    words = { "numpy" },
    package = "numpy",
  },
  {
    id = "pandas",
    group = "Core",
    label = "pd",
    line = "import pandas as pd",
    detail = "DataFrames, read_csv",
    words = { "pandas" },
    package = "pandas",
  },
  {
    id = "matplotlib",
    group = "Core",
    label = "plt",
    line = "import matplotlib.pyplot as plt",
    detail = "plots",
    words = { "matplotlib", "pyplot" },
    package = "matplotlib",
  },
  {
    id = "seaborn",
    group = "Core",
    label = "sns",
    line = "import seaborn as sns",
    detail = "statistical plots",
    words = { "seaborn" },
    package = "seaborn",
  },
  {
    id = "scipy",
    group = "Core",
    label = "sp",
    line = "import scipy as sp",
    detail = "scientific computing",
    words = { "scipy" },
    package = "scipy",
  },
  {
    id = "pathlib",
    group = "Stdlib",
    label = "Path",
    line = "from pathlib import Path",
    detail = "file paths",
    words = {},
    package = "",
  },
  {
    id = "collections",
    group = "Stdlib",
    label = "Counter",
    line = "from collections import Counter",
    detail = "count values",
    words = {},
    package = "",
  },
  {
    id = "dataclasses",
    group = "Stdlib",
    label = "dataclass",
    line = "from dataclasses import dataclass",
    detail = "data classes",
    words = {},
    package = "",
  },
  {
    id = "typing",
    group = "Stdlib",
    label = "Optional",
    line = "from typing import Optional",
    detail = "type hints",
    words = {},
    package = "",
  },
  {
    id = "itertools",
    group = "Stdlib",
    label = "chain",
    line = "from itertools import chain",
    detail = "iteration tools",
    words = {},
    package = "",
  },
  {
    id = "scipy.stats",
    group = "SciPy",
    label = "stats",
    line = "from scipy import stats",
    detail = "statistical tests",
    words = { "scipy" },
    package = "scipy",
  },
  {
    id = "scipy.optimize",
    group = "SciPy",
    label = "minimize",
    line = "from scipy.optimize import minimize",
    detail = "optimization",
    words = {},
    package = "scipy",
  },
  {
    id = "scipy.signal",
    group = "SciPy",
    label = "signal",
    line = "from scipy import signal",
    detail = "signal processing",
    words = {},
    package = "scipy",
  },
  {
    id = "sklearn.model_selection",
    group = "scikit-learn",
    label = "train_test_split",
    line = "from sklearn.model_selection import train_test_split",
    detail = "split train/test",
    words = {},
    package = "sklearn",
  },
  {
    id = "sklearn.model_selection.cv",
    group = "scikit-learn",
    label = "cross_val_score",
    line = "from sklearn.model_selection import cross_val_score",
    detail = "cross validation",
    words = {},
    package = "sklearn",
  },
  {
    id = "sklearn.linear_model",
    group = "scikit-learn",
    label = "LinearRegression",
    line = "from sklearn.linear_model import LinearRegression",
    detail = "linear regression",
    words = {},
    package = "sklearn",
  },
  {
    id = "sklearn.ensemble",
    group = "scikit-learn",
    label = "RandomForestClassifier",
    line = "from sklearn.ensemble import RandomForestClassifier",
    detail = "random forest",
    words = {},
    package = "sklearn",
  },
  {
    id = "sklearn.preprocessing",
    group = "scikit-learn",
    label = "StandardScaler",
    line = "from sklearn.preprocessing import StandardScaler",
    detail = "scale features",
    words = {},
    package = "sklearn",
  },
  {
    id = "sklearn.preprocessing.encoder",
    group = "scikit-learn",
    label = "OneHotEncoder",
    line = "from sklearn.preprocessing import OneHotEncoder",
    detail = "encode categories",
    words = {},
    package = "sklearn",
  },
  {
    id = "sklearn.metrics",
    group = "scikit-learn",
    label = "classification_report",
    line = "from sklearn.metrics import classification_report",
    detail = "model metrics",
    words = {},
    package = "sklearn",
  },
  {
    id = "sklearn.metrics.confusion",
    group = "scikit-learn",
    label = "confusion_matrix",
    line = "from sklearn.metrics import confusion_matrix",
    detail = "model metrics",
    words = {},
    package = "sklearn",
  },
  {
    id = "sklearn.cluster",
    group = "scikit-learn",
    label = "KMeans",
    line = "from sklearn.cluster import KMeans",
    detail = "clustering",
    words = {},
    package = "sklearn",
  },
  {
    id = "sklearn.decomposition",
    group = "scikit-learn",
    label = "PCA",
    line = "from sklearn.decomposition import PCA",
    detail = "dimensionality",
    words = {},
    package = "sklearn",
  },
  {
    id = "statsmodels.api",
    group = "statsmodels",
    label = "sm",
    line = "import statsmodels.api as sm",
    detail = "statistical models",
    words = { "statsmodels" },
    package = "statsmodels",
  },
  {
    id = "statsmodels.formula",
    group = "statsmodels",
    label = "smf",
    line = "import statsmodels.formula.api as smf",
    detail = "formula models",
    words = {},
    package = "statsmodels",
  },
  {
    id = "polars",
    group = "Data",
    label = "pl",
    line = "import polars as pl",
    detail = "fast DataFrames",
    words = { "polars" },
    package = "polars",
  },
  {
    id = "pyarrow",
    group = "Data",
    label = "pq",
    line = "import pyarrow.parquet as pq",
    detail = "parquet files",
    words = { "parquet" },
    package = "pyarrow",
  },
  {
    id = "openpyxl",
    group = "Data",
    label = "load_workbook",
    line = "from openpyxl import load_workbook",
    detail = "Excel files",
    words = {},
    package = "openpyxl",
  },
  {
    id = "duckdb",
    group = "Data",
    label = "duckdb",
    line = "import duckdb",
    detail = "SQL on files",
    words = {},
    package = "duckdb",
  },
  {
    id = "sqlalchemy",
    group = "Data",
    label = "create_engine",
    line = "from sqlalchemy import create_engine",
    detail = "SQL databases",
    words = {},
    package = "sqlalchemy",
  },

  -- Scientific / ML: the aliases used in the industry (the full module names also match as prefixes).
  {
    id = "sklearn",
    group = "scikit-learn",
    label = "sk",
    line = "import sklearn as sk",
    detail = "scikit-learn module",
    words = { "sklearn" },
    package = "sklearn",
  },
  {
    id = "torch",
    group = "ML",
    label = "torch",
    line = "import torch",
    detail = "PyTorch",
    words = {},
    package = "torch",
  },
  {
    id = "tensorflow",
    group = "ML",
    label = "tf",
    line = "import tensorflow as tf",
    detail = "TensorFlow / Keras",
    words = { "tensorflow" },
    package = "tensorflow",
  },
  {
    id = "opencv",
    group = "ML",
    label = "cv2",
    line = "import cv2",
    detail = "OpenCV",
    words = { "opencv" },
    package = "cv2",
  },
  {
    id = "xgboost",
    group = "ML",
    label = "xgb",
    line = "import xgboost as xgb",
    detail = "gradient boosting",
    words = { "xgboost" },
    package = "xgboost",
  },
  {
    id = "lightgbm",
    group = "ML",
    label = "lgb",
    line = "import lightgbm as lgb",
    detail = "gradient boosting",
    words = { "lightgbm" },
    package = "lightgbm",
  },
  {
    id = "scipy.optimize.alias",
    group = "SciPy",
    label = "opt",
    line = "import scipy.optimize as opt",
    detail = "optimization",
    words = {},
    package = "scipy",
  },
  {
    id = "scipy.signal.alias",
    group = "SciPy",
    label = "sig",
    line = "import scipy.signal as sig",
    detail = "signal processing",
    words = {},
    package = "scipy",
  },
  {
    id = "scipy.integrate",
    group = "SciPy",
    label = "integrate",
    line = "from scipy import integrate",
    detail = "integration",
    words = {},
    package = "scipy",
  },
  {
    id = "scipy.spatial",
    group = "SciPy",
    label = "spatial",
    line = "from scipy import spatial",
    detail = "distances / trees",
    words = {},
    package = "scipy",
  },
  {
    id = "sklearn.metrics.accuracy",
    group = "scikit-learn",
    label = "accuracy_score",
    line = "from sklearn.metrics import accuracy_score",
    detail = "accuracy",
    words = {},
    package = "sklearn",
  },
  {
    id = "sklearn.metrics.mse",
    group = "scikit-learn",
    label = "mean_squared_error",
    line = "from sklearn.metrics import mean_squared_error",
    detail = "regression error",
    words = {},
    package = "sklearn",
  },
  {
    id = "sklearn.model_selection.grid",
    group = "scikit-learn",
    label = "GridSearchCV",
    line = "from sklearn.model_selection import GridSearchCV",
    detail = "hyperparameter search",
    words = {},
    package = "sklearn",
  },
  {
    id = "sklearn.pipeline",
    group = "scikit-learn",
    label = "Pipeline",
    line = "from sklearn.pipeline import Pipeline",
    detail = "chained steps",
    words = {},
    package = "sklearn",
  },
  {
    id = "sklearn.preprocessing.label",
    group = "scikit-learn",
    label = "LabelEncoder",
    line = "from sklearn.preprocessing import LabelEncoder",
    detail = "encode labels",
    words = {},
    package = "sklearn",
  },
  {
    id = "sklearn.linear_model.logistic",
    group = "scikit-learn",
    label = "LogisticRegression",
    line = "from sklearn.linear_model import LogisticRegression",
    detail = "classification",
    words = {},
    package = "sklearn",
  },

  -- Data / visualization
  {
    id = "plotly.express",
    group = "Data",
    label = "px",
    line = "import plotly.express as px",
    detail = "interactive plots",
    words = { "plotly" },
    package = "plotly",
  },
  {
    id = "plotly.graph_objects",
    group = "Data",
    label = "go",
    line = "import plotly.graph_objects as go",
    detail = "interactive figures",
    words = {},
    package = "plotly",
    auto = false, -- too common as a variable name: never auto-insert while typing
  },
  {
    id = "missingno",
    group = "Data",
    label = "msno",
    line = "import missingno as msno",
    detail = "missing-value plots",
    words = {},
    package = "missingno",
  },

  -- Stdlib utilities (the short ones are opt-in only: completion still offers them).
  {
    id = "datetime",
    group = "Stdlib",
    label = "dt",
    line = "import datetime as dt",
    detail = "dates and times",
    words = { "datetime" },
    package = "",
  },
  {
    id = "collections.defaultdict",
    group = "Stdlib",
    label = "defaultdict",
    line = "from collections import defaultdict",
    detail = "dict with defaults",
    words = {},
    package = "",
  },
  {
    id = "typing.Any",
    group = "Stdlib",
    label = "Any",
    line = "from typing import Any",
    detail = "type hints",
    words = {},
    package = "",
  },
  {
    id = "typing.Dict",
    group = "Stdlib",
    label = "Dict",
    line = "from typing import Dict",
    detail = "type hints",
    words = {},
    package = "",
  },
  {
    id = "timedelta",
    group = "Stdlib",
    label = "timedelta",
    line = "from datetime import timedelta",
    detail = "time intervals",
    words = {},
    package = "",
  },
  {
    id = "json",
    group = "Stdlib",
    label = "json",
    line = "import json",
    detail = "JSON files",
    words = {},
    package = "",
    auto = false,
  },
  {
    id = "os",
    group = "Stdlib",
    label = "os",
    line = "import os",
    detail = "operating system",
    words = {},
    package = "",
    auto = false,
  },
  {
    id = "sys",
    group = "Stdlib",
    label = "sys",
    line = "import sys",
    detail = "system / interpreter",
    words = {},
    package = "",
    auto = false,
  },
  {
    id = "re",
    group = "Stdlib",
    label = "re",
    line = "import re",
    detail = "regular expressions",
    words = {},
    package = "",
    auto = false,
  },
}

M.CATALOG = CATALOG

--- Ready-made groups for the menu (one click, several imports)
---@return table[]
function M.bundles()
  return {
    {
      label = "Data analysis starter",
      desc = "numpy · pandas · matplotlib · seaborn",
      ids = { "numpy", "pandas", "matplotlib", "seaborn" },
    },
    { label = "NumPy + pandas", desc = "the two aliases used everywhere", ids = { "numpy", "pandas" } },
    { label = "Plots", desc = "matplotlib + seaborn", ids = { "matplotlib", "seaborn" } },
    {
      label = "Machine learning",
      desc = "sklearn: split, models, scaling, metrics",
      ids = { "train_test_split", "StandardScaler", "LinearRegression", "classification_report" },
    },
    { label = "Statistics", desc = "scipy.stats + statsmodels", ids = { "scipy.stats", "statsmodels.api" } },
    {
      label = "Machine learning starter",
      desc = "sklearn split, scaling, model, metrics",
      ids = { "train_test_split", "StandardScaler", "LogisticRegression", "classification_report" },
    },
    { label = "Deep learning", desc = "torch + tensorflow + OpenCV", ids = { "torch", "tensorflow", "opencv" } },
    { label = "Interactive plots", desc = "plotly express + graph_objects", ids = { "plotly.express", "plotly.graph_objects" } },
  }
end

local by_id = {}
for _, row in ipairs(CATALOG) do
  by_id[row.id] = row
end

---@param id string
---@return PyImport?
function M.get(id)
  return by_id[id]
end

--- Whole-word alias lookup for typing-triggered imports. Only distinctive aliases qualify (see `auto = false`).
---@param word string
---@return PyImport?
function M.auto_alias(word)
  if #word < 2 then
    return
  end
  for _, row in ipairs(CATALOG) do
    if row.auto ~= false and row.label == word then
      return row
    end
  end
end

--- Catalog rows whose alias appears as a whole word in `line` (`np.`, `pd.read_csv`, `train_test_split(`…).
--- Pure: no buffer, no process. Used when text changes in insert mode and by the tests.
---@param line string
---@return PyImport[]
function M.used_in_line(line)
  local out = {}
  for _, row in ipairs(CATALOG) do
    if row.auto ~= false then
      local pattern = "%f[%w_]" .. vim.pesc(row.label) .. "%f[^%w_]"
      if line:find(pattern) then
        out[#out + 1] = row
      end
    end
  end
  return out
end

local function settings()
  return require("core.settings").python or {}
end

--- Completion rows matching a typed prefix (at least two letters, to stay quiet)
---@param word string
---@param installed table<string, boolean>?
---@return table[]
function M.matches(word, installed)
  if #word < 2 then
    return {}
  end
  local out = {}
  local lower = word:lower()
  for _, row in ipairs(CATALOG) do
    local hit = vim.startswith(row.label:lower(), lower)
    if not hit then
      for _, w in ipairs(row.words) do
        if vim.startswith(w:lower(), lower) then
          hit = true
          break
        end
      end
    end
    if hit then
      local available = row.package == "" or installed == nil or installed[row.package] ~= false
      out[#out + 1] = {
        row = row,
        label = row.label,
        detail = available and row.detail or (row.detail .. " · uv add " .. row.package),
        available = available,
        kind = row.line:match "^from " and "symbol" or "module",
      }
    end
  end
  return out
end

--- Aliases bound by the imports of a Python buffer, mapped to the module/symbol they point at (pure).
--- `import a.b as c` → c = "a.b"; `import a.b` → a = "a.b"; `from a import b as c` → c = "a.b".
---@param lines string[]
---@return table<string, string>
function M.aliases(lines)
  local out = {}
  for _, line in ipairs(lines) do
    local mod = line:match "^%s*from%s+([%w_.]+)%s+import"
    if mod then
      local name, as = line:match "^%s*from%s+[%w_.]+%s+import%s+([%w_]+)%s+as%s+([%w_]+)"
      if not name then
        name = line:match "^%s*from%s+[%w_.]+%s+import%s+([%w_]+)"
      end
      if name then
        out[as or name] = mod .. "." .. name
      end
    else
      local name, as = line:match "^%s*import%s+([%w_.]+)%s+as%s+([%w_]+)"
      if name then
        out[as] = name
      else
        name = line:match "^%s*import%s+([%w_.]+)"
        if name then
          out[name:match "^([%w_]+)"] = name
        end
      end
    end
  end
  return out
end

-- ── top-of-file insertion ────────────────────────────────────────────────────

local function is_import(line)
  return line:match "^%s*import%s+[%w_%.]" ~= nil or line:match "^%s*from%s+[%w_%.]+%s+import%s+" ~= nil
end

--- Is this statement already in the file? (whitespace-insensitive)
---@param lines string[]
---@param statement string
---@return boolean
function M.has(lines, statement)
  local want = vim.trim(statement)
  for _, line in ipairs(lines) do
    if vim.trim(line) == want then
      return true
    end
  end
  return false
end

--- Where a new import goes: after the module docstring, `from __future__`, and the last import.
---@param lines string[]
---@return integer 0-based row
function M.insert_row(lines)
  local i = 1
  if lines[i] and lines[i]:match "^#!" then
    i = i + 1
  end
  while lines[i] and (lines[i]:match "^%s*$" or lines[i]:match "^%s*#") do
    i = i + 1
  end
  -- module docstring (""" or ''', possibly multiline)
  local line = lines[i] or ""
  local q = line:match "^%s*([\"'])%1%1"
  if q then
    local close = q .. q .. q
    if not line:find(close, 4, true) then
      for j = i + 1, #lines do
        if lines[j]:find(close, 1, true) then
          i = j
          break
        end
      end
    end
    i = i + 1
  end
  local row = i - 1 -- 0-based: before the first real statement
  local last = nil
  while i <= #lines do
    local s = lines[i]
    if is_import(s) then
      last = i
    end
    if is_import(s) or s:match "^%s*$" or s:match "^%s*#" then
      i = i + 1
    else
      break
    end
  end
  return last or row
end

--- Add statements to a buffer, once each. Returns what was actually inserted.
---@param buf integer
---@param statements string[]
---@return string[]
function M.apply(buf, statements)
  local cfg = settings().imports or {}
  if cfg.enabled == false then
    return {}
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local seen, missing = {}, {}
  for _, statement in ipairs(statements or {}) do
    local row = M.get(statement)
    local line = statement
    if row then
      line = row.line
    end
    if line and line ~= "" and not seen[line] and not M.has(lines, line) then
      seen[line] = true
      missing[#missing + 1] = line
    end
  end
  if #missing == 0 then
    return {}
  end
  table.sort(missing)
  local at = M.insert_row(lines)
  vim.api.nvim_buf_set_lines(buf, at, at, false, missing)
  return missing
end

--- Blank out quoted strings and comments, keeping byte positions. Shared with
--- the typing-triggered auto-import (utils/pyauto.lua) and the cleanup module.
---@param line string
---@return string
function M.mask(line)
  local out, i, quote = {}, 1, nil
  while i <= #line do
    local c = line:sub(i, i)
    if quote then
      if c == "\\" then
        out[#out + 1] = "  "
        i = i + 2
      else
        out[#out + 1] = " "
        if c == quote then
          quote = nil
        end
        i = i + 1
      end
    elseif c == '"' or c == "'" then
      quote = c
      out[#out + 1] = " "
      i = i + 1
    elseif c == "#" then
      while i <= #line do
        out[#out + 1] = " "
        i = i + 1
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Pure counterpart of `apply`: returns new lines with the statements inserted at the top.
---@param lines string[]
---@param statements string[]
---@return string[]
function M.apply_to_lines(lines, statements)
  local seen, missing = {}, {}
  for _, statement in ipairs(statements or {}) do
    local row = M.get(statement)
    local line = row and row.line or statement
    if line and line ~= "" and not seen[line] and not M.has(lines, line) then
      seen[line] = true
      missing[#missing + 1] = line
    end
  end
  if #missing == 0 then
    return lines
  end
  table.sort(missing)
  local out = vim.deepcopy(lines)
  local at = M.insert_row(out)
  for i = #missing, 1, -1 do
    table.insert(out, at + 1, missing[i])
  end
  return out
end

-- ── installed packages (fast directory scan, once per project) ────────────────

local installed_cache, stamp_cache = {}, {}

local function venv_stamp(root)
  -- pysmart calls this on every keystroke: reuse the stat for half a second (uv add is not a per-key event).
  local now = vim.uv.now()
  local hit = stamp_cache[root]
  if hit and now - hit.at < 500 then
    return hit.value
  end
  local lib = vim.uv.fs_stat(root .. "/.venv/lib") or vim.uv.fs_stat(root .. "/venv/lib")
  local value = lib and lib.mtime.sec or 0
  stamp_cache[root] = { value = value, at = now }
  return value
end

--- Top-level packages present in the project's virtual environment.
--- The scan is cached until the venv's `lib` folder changes (`uv add` in the same session).
---@param root string
---@return table<string, boolean>
function M.installed(root)
  local stamp = venv_stamp(root)
  local cached = installed_cache[root]
  if cached and cached.stamp == stamp then
    return cached.found
  end
  local found = {}
  for _, venv in ipairs { root .. "/.venv", root .. "/venv" } do
    local handle = vim.uv.fs_scandir(venv .. "/lib")
    if handle then
      while true do
        local name = vim.uv.fs_scandir_next(handle)
        if not name then
          break
        end
        if name:match "^python" then
          local site = venv .. "/lib/" .. name .. "/site-packages"
          local s = vim.uv.fs_scandir(site)
          if s then
            while true do
              local pkg = vim.uv.fs_scandir_next(s)
              if not pkg then
                break
              end
              local base = pkg:match "^([%w_]+)"
              if base then
                found[base] = true
                if base == "scikit_learn" then
                  found.sklearn = true
                end
              end
            end
          end
        end
      end
    end
  end
  installed_cache[root] = { found = found, stamp = stamp }
  return found
end

--- Forget the cached scan (after `uv add` in the same session)
function M.reset()
  installed_cache, stamp_cache = {}, {}
end

return M
