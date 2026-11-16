-- MariaDB: same client flags as MySQL, but `--ssl-mode` is MySQL's and `ANALYZE FORMAT=JSON` replaces EXPLAIN ANALYZE.
return require("sqlrun.dialects.mysql_base").new {
  label = "MariaDB",
  short = "MariaDB",
  schemes = { "mariadb" },
  client = "mariadb",
  alts = { "mysql" },
  sqlfluff = "mariadb",
  formatter = "mariadb",
  install = "pacman -S mariadb-clients · apt install mariadb-client · brew install mariadb",
  tip = "MariaDB's client takes `--ssl`, not MySQL's `--ssl-mode`; the `mariadb` binary is preferred over `mysql`.",
}
