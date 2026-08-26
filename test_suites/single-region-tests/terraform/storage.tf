# ------------------------------------------------
# GCS bucket for compiler cache (sccache)

resource "google_storage_bucket" "compiler_cache" {
  count    = var.create_compiler_cache_bucket ? 1 : 0
  name     = var.compiler_cache_bucket
  location = var.gcp_region
  project  = var.gcp_project

  # Force destroy to prevent apply errors on recreation
  force_destroy = true

  # Lifecycle management — clean up old cache objects
  lifecycle_rule {
    condition {
      age = 30 # days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }

  # Enable versioning for better cache reliability
  versioning {
    enabled = true
  }

  # Make bucket publicly readable for cross-project cache sharing
  uniform_bucket_level_access = true

  labels = {
    owner   = var.owner
    purpose = "compiler-cache"
    devnet  = var.devnet_name
  }
}

# Public read access for compiler cache sharing
resource "google_storage_bucket_iam_member" "compiler_cache_public_read" {
  count  = var.create_compiler_cache_bucket ? 1 : 0
  bucket = google_storage_bucket.compiler_cache[0].name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}