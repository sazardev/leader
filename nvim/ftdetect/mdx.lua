-- MDX (*.mdx): Markdown with JSX. There is no `mdx` parser in nvim-treesitter, so to make it visible
-- (treesitter, render-markdown, prettier, markdownlint, the <leader>m menu) it is detected as `markdown`.
-- JSX stays visible as `html_tag` (injected to HTML) and `tsx`/`jsx` fences via the language injection.
-- Tolerant on purpose: what it does not understand (imports, `{expr}`) stays as plain text, never as an error.
vim.filetype.add { extension = { mdx = "markdown" } }
