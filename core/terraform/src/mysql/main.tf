terraform {
  required_providers {
    mysql = {
      source = "terraform-providers/mysql"
      version = "~> 1.6"
    }
  }
}

provider "mysql" {
  endpoint = "/var/lib/mysql/mysql.sock"
  username = "root"
}

resource "mysql_database" "db" {
  name = var.mysql_dbname
}

resource "mysql_user" "user_localhost" {
  host               = "localhost"
  user               = mysql_database.db.name
  plaintext_password = "password"
}

resource "mysql_grant" "user_localhost" {
  host       = mysql_user.user_localhost.host
  user       = mysql_user.user_localhost.user
  database   = mysql_database.db.name
  privileges = ["ALL"]
}

resource "mysql_user" "user_any" {
  host               = "%"
  user               = mysql_database.db.name
  plaintext_password = "password"
}

resource "mysql_grant" "user_any" {
  host       = mysql_user.user_any.host
  user       = mysql_user.user_any.user
  database   = mysql_database.db.name
  privileges = ["ALL"]
}
