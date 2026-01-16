terraform {
  required_providers {
    k3d = {
      source  = "pvrevo/k3d"
      version = "0.0.7"
    }
  }
}

resource "k3d_cluster" "eagle_mgmt" {
  name = "eagle-mgmt"
}

resource "k3d_cluster" "eagle_prod" {
  name = "eagle-prod"
}