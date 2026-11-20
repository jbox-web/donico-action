# !!! THIS IS A GENERATED FILE !!! DON'T EDIT ME MANUALLY !!!
# Instead edit donico.yml and run donico generate-files

variable "BUILD_DATE" {
  validation {
    condition = BUILD_DATE != ""
    error_message = "The variable 'BUILD_DATE' must not be empty."
  }
}

##########################
# BOOKWORM - example 1.0 #
##########################

target "bookworm-1-0-build" {
  dockerfile = "Dockerfile"
  args = {
    BUILD_DATE = "${BUILD_DATE}"
    DISTRO_NAME = "bookworm"
    EXAMPLE_VERSION = "1.0"
  }
  platforms = ["linux/amd64", "linux/arm64"]
  output    = [{ type = "docker" }]
  tags      = ["example/1.0/bookworm:${BUILD_DATE}"]
}

target "bookworm-1-0-push" {
  dockerfile = "Dockerfile"
  args = {
    BUILD_DATE = "${BUILD_DATE}"
    DISTRO_NAME = "bookworm"
    EXAMPLE_VERSION = "1.0"
  }
  platforms = ["linux/amd64", "linux/arm64"]
  output    = [{ type = "registry" }]
  tags      = [
    "registry.invalid/donico-action/example:1.0-bookworm",
  ]
}
