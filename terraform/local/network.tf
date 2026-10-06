# All local Compose projects share container DNS; no host.docker.internal.
resource "terraform_data" "network" {
  provisioner "local-exec" {
    command = "docker network inspect dotfiles-o11y >/dev/null 2>&1 || docker network create dotfiles-o11y"
  }
}
