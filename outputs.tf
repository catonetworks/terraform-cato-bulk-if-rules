# Section Outputs
output "sections" {
  description = "Map of all created Internet Firewall sections with their details"
  value = {
    for k, v in cato_if_section.sections : k => {
      id           = v.id
      name         = v.section.name
      position     = v.at.position
      section_data = v.section
    }
  }
}

output "section_ids" {
  description = "Map of section names to their IDs"
  value = {
    for k, v in cato_if_section.sections : k => v.id
  }
}

output "section_names" {
  description = "List of all created section names"
  value       = [for section in cato_if_section.sections : section.section.name]
}

# Rule Outputs
output "rules" {
  description = "Map of all created Internet Firewall rules with their details"
  value = {
    for k, v in cato_if_rule.rules : k => {
      id          = v.rule.id
      name        = v.rule.name
      enabled     = v.rule.enabled
      action      = v.rule.action
      description = try(v.rule.description, "")
      rule_data   = v.rule
    }
  }
}

output "rule_ids" {
  description = "Map of rule names to their IDs"
  value = {
    for k, v in cato_if_rule.rules : v.rule.name => v.rule.id
  }
}

output "rule_names" {
  description = "List of all created rule names"
  value       = [for rule in cato_if_rule.rules : rule.rule.name]
}

output "enabled_rules" {
  description = "List of enabled rule names"
  value       = [for rule in cato_if_rule.rules : rule.rule.name if rule.rule.enabled]
}

output "disabled_rules" {
  description = "List of disabled rule names"
  value       = [for rule in cato_if_rule.rules : rule.rule.name if !rule.rule.enabled]
}

output "allow_rules" {
  description = "List of rules with ALLOW action"
  value       = [for rule in cato_if_rule.rules : rule.rule.name if rule.rule.action == "ALLOW"]
}

output "block_rules" {
  description = "List of rules with BLOCK action"
  value       = [for rule in cato_if_rule.rules : rule.rule.name if rule.rule.action == "BLOCK"]
}

# Bulk Move Operation Output
output "bulk_move_operation" {
  description = "Details of the bulk move operation"
  value = {
    section_to_start_after_id = cato_bulk_if_move_rule.all_if_rules.section_to_start_after_id
    rules_moved               = length(local.rules_data)
    sections_created          = length(local.sections_data)
    rule_data                 = cato_bulk_if_move_rule.all_if_rules.rule_data
    section_data              = cato_bulk_if_move_rule.all_if_rules.section_data
  }
}

# Summary Statistics
output "deployment_summary" {
  description = "Summary statistics of the deployment"
  value = {
    total_sections_created = length(cato_if_section.sections)
    total_rules_created    = length(cato_if_rule.rules)
    enabled_rules_count    = length([for rule in cato_if_rule.rules : rule if rule.rule.enabled])
    disabled_rules_count   = length([for rule in cato_if_rule.rules : rule if !rule.rule.enabled])
    allow_rules_count      = length([for rule in cato_if_rule.rules : rule if rule.rule.action == "ALLOW"])
    block_rules_count      = length([for rule in cato_if_rule.rules : rule if rule.rule.action == "BLOCK"])
    sections_by_name       = { for section in cato_if_section.sections : section.section.name => section.id }
    rules_by_action = {
      ALLOW = [for rule in cato_if_rule.rules : rule.rule.name if rule.rule.action == "ALLOW"]
      BLOCK = [for rule in cato_if_rule.rules : rule.rule.name if rule.rule.action == "BLOCK"]
    }
  }
}

# Configuration Data Outputs
output "parsed_configuration" {
  description = "Parsed configuration data from the JSON file"
  value = {
    source_file_path      = var.ifw_rules_json_file_path
    rules_data_count      = length(local.ifw_rules_data)
    sections_data_count   = length(local.sections_data)
    rules_mapping_count   = length(local.rules_data)
    section_names_ordered = [for section in local.sections_data : section.section_name]
  }
}

# Rule to Section Mapping
output "rules_to_sections_mapping" {
  description = "Mapping of rules to their assigned sections with ordering"
  value = {
    for rule_mapping in local.rules_data : rule_mapping.rule_name => {
      section_name     = rule_mapping.section_name
      index_in_section = rule_mapping.index_in_section
      rule_id          = try(cato_if_rule.rules[rule_mapping.rule_name].rule.id, "")
      section_id       = try(cato_if_section.sections[rule_mapping.section_name].id, "")
    }
  }
}

# Sub-Policy Outputs (NEW - see ifw-sub-policy-json-design.md)
output "sub_policy_ids" {
  description = "Map of sub-policy names to their IDs"
  value = {
    for k, v in cato_if_sub_policy.sub_policies : k => v.id
  }
}

output "sub_policy_scope_rule_ids" {
  description = "Map of sub-policy names to the ID of their underlying SUB_POLICY_SCOPE rule"
  value = {
    for k, v in cato_if_sub_policy.sub_policies : k => v.scope_rule_id
  }
}

output "sub_rule_ids" {
  description = "Map of sub-rules (keyed \"<sub_policy_name>::<rule_name>\") to their IDs"
  value = {
    for k, v in cato_if_rule.sub_rules : k => v.rule.id
  }
}

# Unmanaged sub-sections (provider has no sub-policy parenting on cato_if_section
# yet - these are export/import-only, not created/managed by this module).
# Keyed "<sub_policy_name>::<section_name>".
output "unmanaged_sub_sections" {
  description = "Sub-sections present in the JSON that this module cannot yet manage (no cato_if_section sub-policy parenting in the provider). Informational only."
  value       = local.sub_sections_data
}

# rules_in_sections rows that order a rule INSIDE a sub-policy. The provider's
# cato_bulk_if_move_rule cannot yet consume these (ordering inside sub-policies
# is creation-order best-effort - see main.tf). Informational only.
output "unordered_sub_policy_rules" {
  description = "rules_in_sections rows that order a rule inside a sub-policy, which cato_bulk_if_move_rule does not yet support. Informational only."
  value       = local.unordered_sub_policy_rules_data
}

# Cleanup rule ids, re-resolved by the provider on every read/update: the
# cleanup is always the sub-policy's LAST rule, so this tracks manual moves.
output "cleanup_rule_ids" {
  description = "Map of sub-policy name to the id of its cleanup rule (the sub-policy's last rule, API-managed identity)."
  value       = { for name, sp in cato_if_sub_policy.sub_policies : name => sp.cleanup_rule_id }
}

# Sub-policy scope rows whose parent section is not managed by this module
# (e.g. the account's default section). Their placement fell back to
# LAST_IN_POLICY and they are excluded from the move resource (see main.tf).
output "unordered_sub_policies" {
  description = "rules_in_sections sub-policy rows whose parent section is not in sections[], so cato_bulk_if_move_rule does not order them. Informational only."
  value       = local.unordered_sub_policies_data
}

# Section to Rules Mapping
output "sections_to_rules_mapping" {
  description = "Mapping of sections to their assigned rules with ordering"
  value = {
    for section_name in distinct([for rule_mapping in local.rules_data : rule_mapping.section_name]) :
    section_name => {
      section_id = try(cato_if_section.sections[section_name].id, "")
      rules = [
        for rule_mapping in local.rules_data :
        {
          rule_name        = rule_mapping.rule_name
          index_in_section = rule_mapping.index_in_section
          rule_id          = try(cato_if_rule.rules[rule_mapping.rule_name].rule.id, "")
        }
        if rule_mapping.section_name == section_name
      ]
    }
  }
}
