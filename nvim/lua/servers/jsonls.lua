-- SchemaStore schemas (tsconfig, package.json, nest-cli, etc.)
return {
  settings = {
    json = {
      schemas = require("schemastore").json.schemas(),
      validate = { enable = true },
    },
  },
}
