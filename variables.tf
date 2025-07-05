## Config Data Directory and File Names
variable "ifw_rules_json_file_path" {
  type        = string
  description = "Path to the json file containing the ifw rule data."
}

variable "section_to_start_after_id" {
  type        = string
  description = "The ID of the section after which to start adding rules."
  default     = null
}
