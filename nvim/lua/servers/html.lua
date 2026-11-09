-- HTML: also attach to Razor (.razor/.cshtml) for markup completion (tags, attributes). The C# parts inside
-- @code still need seblyng/roslyn.nvim for full intelligence (see docs/cheatsheets/csharp.md).
return {
  filetypes = { "html", "razor" },
}
