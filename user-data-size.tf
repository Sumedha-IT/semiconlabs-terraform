# Fail at plan time when gzip payload exceeds EC2 16 KiB.
data "external" "lab_user_data_payload" {
  program = ["node", "${path.module}/scripts/gzip-b64-payload-len.js"]
  query = {
    b64 = local.lab_user_data_gzip_b64
  }
}

check "lab_user_data_ec2_limit" {
  assert {
    condition = (
      data.external.lab_user_data_payload.result.ok == "true" &&
      data.external.lab_user_data_payload.result.gzip == "true"
    )
    error_message = "Lab user-data must be gzip-compressed and <= 16384 bytes (payload=${data.external.lab_user_data_payload.result.len} bytes). TEMP: shrink user-data.sh.tftpl or enable S3 split (bootstrap-full on S3 + stub)."
  }
}
