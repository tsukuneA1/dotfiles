# Defaults for LANGFUSE_INIT_* (headless initialization) — not secrets, so
# safe to commit.
# https://langfuse.com/self-hosting/administration/headless-initialization

variable "init_org_id" {
  type    = string
  default = "claude-code"
}

variable "init_org_name" {
  type    = string
  default = "Coding Agents (local)"
}

variable "init_project_id" {
  type    = string
  default = "claude-code"
}

variable "init_project_name" {
  type    = string
  default = "Coding Agents"
}

variable "init_user_email" {
  type    = string
  default = "admin@example.com"
}

variable "init_user_name" {
  type    = string
  default = "admin"
}
