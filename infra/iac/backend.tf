terraform {
  # State lives in S3-compatible object storage. Cloudflare R2 works and is
  # what this was written against; any S3 bucket does.
  #
  # Nothing identifying is in here on purpose. The endpoint hostname contains
  # the account id, so it is passed at init time instead:
  #
  #   tofu init \
  #     -backend-config="endpoints={s3=\"https://<account>.r2.cloudflarestorage.com\"}"
  #
  # R2 credentials are NOT AWS credentials, and the failure when you mix them
  # up is unhelpful: an access key of the wrong length. AWS keys are 20
  # characters, R2's are 32. If a plan cannot load state, check that first.
  backend "s3" {
    bucket = "tfstate"
    key    = "prod/terraform.tfstate"

    # R2 ignores the region and the s3 backend insists on one.
    region = "auto"

    # All 4 exist because R2 is not AWS: there is no instance metadata
    # endpoint, no STS to ask for an account id, and no region to validate.
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true

    # State holds every attribute of every resource. On R2 the bucket is
    # encrypted at rest anyway; this is the layer above that.
    encrypt = true
  }
}
