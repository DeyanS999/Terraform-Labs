variable "instance_size" {
  description = "Provide SKU size"
  default = "Standard_B1s"
}

variable "location" {
  default = "eastus"
}

variable "tags" {
    description = "tags for resource"
  type = map(string)
  default = {
    environm    = "test"
  }
}