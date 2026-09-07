resource "aws_efs_file_system" "clickhouse" {
  creation_token  = "openpanel-${var.env_name}-clickhouse"
  encrypted       = true
  throughput_mode = "elastic"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
}

resource "aws_efs_mount_target" "clickhouse" {
  for_each = toset(data.aws_subnets.private.ids)

  file_system_id  = aws_efs_file_system.clickhouse.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

# The official ClickHouse image runs the server process as the "clickhouse"
# user, uid/gid 101, as of the image pinned in
# infra/clickhouse-image/Dockerfile (Task 14). Verify this before the first
# apply with `docker run --rm <built-image> id clickhouse` — if it differs,
# update both this access point and the Dockerfile's assumptions together.
resource "aws_efs_access_point" "clickhouse" {
  file_system_id = aws_efs_file_system.clickhouse.id

  posix_user {
    uid = 101
    gid = 101
  }

  root_directory {
    path = "/clickhouse-data"

    creation_info {
      owner_uid   = 101
      owner_gid   = 101
      permissions = "0755"
    }
  }
}
