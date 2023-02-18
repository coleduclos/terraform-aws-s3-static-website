variable "error_document_key" {
    type = string
    default = "error.html"
}

variable "index_document_suffix" {
    type = string
    default = "index.html"
}

variable "public_hosted_zone_name" {
    type = string
}

variable "tags" {
    type = map
}