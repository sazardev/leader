-- MySQL 8: `--table` for a boxed result, `MYSQL_PWD` for the password, `--ssl-mode` from the URL query.
return require("sqlrun.dialects.mysql_base").new {
  label = "MySQL",
  short = "MySQL",
  schemes = { "mysql" },
  client = "mysql",
  alts = { "mariadb" },
  sqlfluff = "mysql",
  formatter = "mysql",
  install = "pacman -S mariadb-clients · apt install default-mysql-client · brew install mysql-client",
  tip = "the password goes to the client through MYSQL_PWD, never in argv; `?ssl-mode=DISABLED` turns TLS off.",
}
