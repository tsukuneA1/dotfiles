# Generates docker-compose.yml's CHANGEME values.
# random_id.*.hex mirrors `openssl rand -hex <n>` (ENCRYPTION_KEY needs a
# 32-byte/64-char AES-256 key).

locals {
  # docker-compose.yml/.env live in ../../services/langfuse, not here.
  langfuse_dir = "${path.module}/../../services/langfuse"
}

resource "random_id" "salt" {
  byte_length = 32
}

resource "random_id" "encryption_key" {
  byte_length = 32
}

resource "random_id" "nextauth_secret" {
  byte_length = 32
}

# special=false: symbols (#, ' etc.) break .env parsing and shell
# interpolation (e.g. redis's `command:`).
resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "random_password" "clickhouse" {
  length  = 32
  special = false
}

resource "random_password" "redis" {
  length  = 32
  special = false
}

# One minio instance backs both root auth and S3 upload credentials, so the
# same password is reused across several env vars in docker-compose.yml.
resource "random_password" "minio" {
  length  = 32
  special = false
}

resource "random_id" "project_public_key" {
  byte_length = 16
}

resource "random_id" "project_secret_key" {
  byte_length = 16
}

resource "random_password" "init_user" {
  length  = 32
  special = false
}

resource "local_sensitive_file" "env" {
  filename        = "${local.langfuse_dir}/.env"
  file_permission = "0600"

  content = <<-EOT
    TELEMETRY_ENABLED=false
    SALT=${random_id.salt.hex}
    ENCRYPTION_KEY=${random_id.encryption_key.hex}
    NEXTAUTH_SECRET=${random_id.nextauth_secret.hex}
    POSTGRES_PASSWORD=${random_password.postgres.result}
    DATABASE_URL=postgresql://postgres:${random_password.postgres.result}@postgres:5432/postgres
    CLICKHOUSE_PASSWORD=${random_password.clickhouse.result}
    REDIS_AUTH=${random_password.redis.result}
    MINIO_ROOT_PASSWORD=${random_password.minio.result}
    LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY=${random_password.minio.result}
    LANGFUSE_S3_MEDIA_UPLOAD_SECRET_ACCESS_KEY=${random_password.minio.result}
    LANGFUSE_S3_BATCH_EXPORT_SECRET_ACCESS_KEY=${random_password.minio.result}
    LANGFUSE_INIT_ORG_ID=${var.init_org_id}
    LANGFUSE_INIT_ORG_NAME=${var.init_org_name}
    LANGFUSE_INIT_PROJECT_ID=${var.init_project_id}
    LANGFUSE_INIT_PROJECT_NAME=${var.init_project_name}
    LANGFUSE_INIT_PROJECT_PUBLIC_KEY=pk-lf-${random_id.project_public_key.hex}
    LANGFUSE_INIT_PROJECT_SECRET_KEY=sk-lf-${random_id.project_secret_key.hex}
    LANGFUSE_INIT_USER_EMAIL=${var.init_user_email}
    LANGFUSE_INIT_USER_NAME=${var.init_user_name}
    LANGFUSE_INIT_USER_PASSWORD=${random_password.init_user.result}
  EOT
}

# Just runs `docker compose up` after .env exists — see rules for why the
# compose file itself isn't reimplemented in Terraform.
resource "terraform_data" "compose_up" {
  triggers_replace = {
    env_sha256     = local_sensitive_file.env.content_sha256
    compose_sha256 = filesha256("${local.langfuse_dir}/docker-compose.yml")
    # clickhouse-users.d must exist before first container creation (compose
    # mounts it), and content changes need a container restart — see rules.
    clickhouse_users_xml_sha256 = local_sensitive_file.clickhouse_grafana_ro_users_xml.content_sha256
    # destroy-time provisioners can only read `self`, not top-level locals.
    langfuse_dir = local.langfuse_dir
  }

  provisioner "local-exec" {
    working_dir = local.langfuse_dir
    command     = "docker compose --parallel 1 up -d --wait --wait-timeout 300"
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = self.triggers_replace.langfuse_dir
    command     = "docker compose down"
  }

  depends_on = [
    terraform_data.network,
    local_sensitive_file.env,
    local_sensitive_file.clickhouse_grafana_ro_users_xml,
  ]
}
