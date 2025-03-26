resource "aws_key_pair" "builder_main_key" {
    key_name   = "builder-main-key"
    public_key = file("${var.PUBLIC_KEY_PATH}")
}
