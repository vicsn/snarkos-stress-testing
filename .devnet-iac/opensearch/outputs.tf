output "collection_enpdoint" {
  value = "${aws_opensearchserverless_collection.collection.collection_endpoint}:443"
}

output "dashboard_endpoint" {
  value = aws_opensearchserverless_collection.collection.dashboard_endpoint
}