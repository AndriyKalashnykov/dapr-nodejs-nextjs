plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# renovate: datasource=github-releases depName=terraform-linters/tflint-ruleset-azurerm
plugin "azurerm" {
  enabled = true
  version = "0.31.1"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

config {
  call_module_type = "all" # lint modules recursively
}

# Generator modules accept values through inputs that tflint can't evaluate
# without a plan; the `terraform` ruleset's `documented_variables` etc. still
# apply, but silence noise from required-provider unused where we set
# `~> 4.68.0` identically across modules (intentional pinning).
rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}
