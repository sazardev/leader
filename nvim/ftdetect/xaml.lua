-- XAML (*.xaml): XML markup. There is no `xaml` parser in nvim-treesitter, so the `xaml` filetype is
-- registered onto the `xml` parser (the `xml` parser is declared by languages/xaml.lua).
vim.filetype.add { extension = { xaml = "xaml" } }
pcall(vim.treesitter.language.register, "xml", "xaml")
