resource "aws_key_pair" "stress_testing_manager_main_key" {
    key_name   = "stress_testing_manager-main-key${local.name_suffix}"
    public_key = file("${var.PUBLIC_KEY_PATH}")
}
