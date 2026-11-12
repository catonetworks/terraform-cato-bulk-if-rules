# Terraform Cato Bulk Internet Firewall Rules Module

This module allows you to bulk import Internet Firewall (IFW) rules and sections from a JSON configuration file, and define the order of those rules and sections within the Cato policy.

## Usage

The module reads a JSON configuration file that defines:
- **Rules**: Individual firewall rules with their configurations
- **Sections**: Logical groupings for organizing rules
- **Rule ordering**: Defines which rules belong to which sections and their order within sections

### Basic Example

```hcl
module "bulk_ifw_rules" {
  source = "catonetworks/bulk-if-rules/cato"
  
  ifw_rules_json_file_path = "./config_data/all_ifw_rules_and_sections.json"
  section_to_start_after_id = "existing-section-id" # Optional
}
```

### JSON Configuration Structure

The JSON file should contain a nested structure with the following key components:

- `data.policy.internetFirewall.policy.rules[]` - Array of firewall rules
- `data.policy.internetFirewall.policy.sections[]` - Array of sections with index and name
- `data.policy.internetFirewall.policy.rules_in_sections[]` - Mapping of rules to sections with ordering

#### Key Fields:

**Rules Array**: Each rule contains standard IFW rule properties like name, description, enabled status, source, destination, action, and tracking settings.

**Sections Array**: Defines sections with:
- `section_index`: The order of the section in the policy
- `section_name`: The display name of the section

**Rules in Sections Array**: Maps rules to sections with:
- `index_in_section`: The order of the rule within its section
- `section_name`: The section this rule belongs to
- `rule_name`: The name of the rule to place in the section

<details>
<summary>Click to expand full JSON configuration example</summary>

```json
{
  "data": {
    "policy": {
      "internetFirewall": {
        "policy": {
          "enabled": true,
          "rules": [
            {
              "rule": {
                "name": "My IFW Rule 1",
                "description": "My IFW Rule 1",
                "enabled": true,
                "source": {},
                "connectionOrigin": "REMOTE",
                "destination": {},
                "action": "ALLOW",
                "tracking": {
                  "alert": {
                    "enabled": false,
                    "frequency": "DAILY"
                  },
                  "event": {
                    "enabled": true
                  }
                }
              }
            },
            {
              "rule": {
                "name": "My IFW Rule 2",
                "description": "My IFW Rule 2",
                "enabled": true,
                "source": {},
                "connectionOrigin": "REMOTE",
                "destination": {},
                "action": "ALLOW",
                "tracking": {
                  "alert": {
                    "enabled": false,
                    "frequency": "DAILY"
                  },
                  "event": {
                    "enabled": true
                  }
                }
              }
            },
            {
              "rule": {
                "name": "My IFW Rule 3",
                "description": "My IFW Rule 3",
                "enabled": true,
                "source": {},
                "connectionOrigin": "REMOTE",
                "destination": {},
                "action": "ALLOW",
                "tracking": {
                  "alert": {
                    "enabled": false,
                    "frequency": "DAILY"
                  },
                  "event": {
                    "enabled": true
                  }
                }
              }
            }
          ],
          "sections": [
            {
              "section_index": 1,
              "section_name": "My IFW Section 1"
            },
            {
              "section_index": 2,
              "section_name": "My IFW Section 2"
            }
          ],
          "rules_in_sections": [
            {
              "index_in_section": 1,
              "section_name": "My IFW Section 1",
              "rule_name": "My IFW Rule 1"
            },
            {
              "index_in_section": 2,
              "section_name": "My IFW Section 2",
              "rule_name": "My IFW Rule 2"
            },
            {
              "index_in_section": 1,
              "section_name": "My IFW Section 2",
              "rule_name": "My IFW Rule 3"
            }
          ]
        }
      }
    }
  }
}
```
</details>

### How Rule Ordering Works

Based on the example above:
1. **Section 1** ("My IFW Section 1") is created first
2. **Section 2** ("My IFW Section 2") is created second
3. **Rule 1** is placed in Section 1 at position 1
4. **Rule 3** is placed in Section 2 at position 1
5. **Rule 2** is placed in Section 2 at position 2

The final policy structure will be:
```
├── My IFW Section 1
│   └── My IFW Rule 1
└── My IFW Section 2
    ├── My IFW Rule 3
    └── My IFW Rule 2
```

### Parameters

- `ifw_rules_json_file_path`: Path to your JSON configuration file
- `section_to_start_after_id`: (Optional) ID of an existing section after which to insert the new sections

## Working with Existing Rules (Brownfield Deployments)

If your Cato Management Application already has a live Internet Firewall policy, don't recreate it — **adopt** it. Adoption is a three-part flow: export the live policy to JSON, point this module at that JSON, then import the existing objects into Terraform state so that your first `terraform apply` changes nothing in the live tenant.

Two import paths are supported:

| Path | Style | Preview before state changes? |
|------|-------|-------------------------------|
| **Option A (recommended)** — native Terraform `import` blocks in a one-shot `migration.tf` | Declarative | Yes — `terraform plan` shows the complete adoption before state is touched |
| **Option B** — `catocli import if_rules_to_tf` | Imperative (runs `terraform import` per resource) | No — state is mutated as the command runs |

Both paths rely on the same module convention: every `for_each` state address is keyed by **name** (rule name, section name, sub-policy name), so import targets line up 1:1 against the exported JSON with no hand-mapping.

### Step 1 — Install and configure the Cato CLI

```bash
pip3 install catocli
catocli configure set
```

`catocli configure set` prompts for your Cato API key and account ID and stores them as a named profile (AWS-CLI style).

### Step 2 — Export the live policy

```bash
catocli export if_rules
```

This writes `config_data/all_ifw_rules_and_sections.json` in exactly the format this module consumes. The export also captures each object's live ID (`sections[].section_id`, `rules[].rule.id`, `sub_policies[].sub_policy_id`) — these are the brownfield **import keys** used in Step 4, and are ignored on greenfield applies.

### Step 3 — Point the module at the export

```hcl
module "if_rules" {
  source = "catonetworks/bulk-if-rules/cato"

  ifw_rules_json_file_path = "./config_data/all_ifw_rules_and_sections.json"
}
```

Run `terraform init`, then continue to Step 4 **before** applying — an apply at this point would try to create duplicates of objects that already exist in the live policy.

### Step 4 — Import the existing objects into Terraform state

Whichever option you choose, the state addresses and import IDs are the same:

| Object | State address | Import ID (from the export) |
|--------|---------------|-----------------------------|
| Section | `module.if_rules.cato_if_section.sections["<section_name>"]` | `sections[].section_id` |
| Rule | `module.if_rules.cato_if_rule.rules["<rule_name>"]` | `rules[].rule.id` |
| Sub-policy | `module.if_rules.cato_if_sub_policy.sub_policies["<sub_policy_name>"]` | `sub_policies[].sub_policy_id` |
| Sub-policy rule | `module.if_rules.cato_if_rule.sub_rules["<sub_policy_name>::<rule_name>"]` | `rules[].rule.id` |

`cato_bulk_if_move_rule.all_if_rules` is **never imported** — it is plan-time ordering orchestration with no live object of its own, and is created on the first apply after adoption. This is why a correct adoption plan always shows exactly `1 to add`.

#### Option A (recommended) — native Terraform import blocks (`migration.tf`)

Requires Terraform >= 1.7 (for `for_each` on `import` blocks). Create a one-shot `migration.tf` beside your module call. It derives every import target directly from the same JSON export the module reads, so there is nothing to hand-maintain — re-exporting refreshes both the config and the import IDs at once:

<details>
<summary>migration.tf — complete example</summary>

```hcl
locals {
  ifw_policy = jsondecode(file("./config_data/all_ifw_rules_and_sections.json")).data.policy.internetFirewall.policy

  ifw_main_sections = {
    for s in local.ifw_policy.sections : s.section_name => s
    if try(s.sub_policy_name, null) == null
  }
  ifw_main_rules = {
    for r in local.ifw_policy.rules : r.rule.name => r.rule
    if try(r.sub_policy_name, null) == null
  }
  ifw_sub_policies = {
    for sp in try(local.ifw_policy.sub_policies, []) : sp.sub_policy_name => sp
  }
  ifw_sub_rules = {
    for r in local.ifw_policy.rules : "${r.sub_policy_name}::${r.rule.name}" => r.rule
    if try(r.sub_policy_name, null) != null
  }
}

import {
  for_each = local.ifw_main_sections
  to       = module.if_rules.cato_if_section.sections[each.key]
  id       = each.value.section_id
}

import {
  for_each = local.ifw_main_rules
  to       = module.if_rules.cato_if_rule.rules[each.key]
  id       = each.value.id
}

import {
  for_each = local.ifw_sub_policies
  to       = module.if_rules.cato_if_sub_policy.sub_policies[each.key]
  id       = each.value.sub_policy_id
}

import {
  for_each = local.ifw_sub_rules
  to       = module.if_rules.cato_if_rule.sub_rules[each.key]
  id       = each.value.id
}

# cato_bulk_if_move_rule.all_if_rules is plan-time ordering orchestration —
# it has no live object of its own, so it is never imported; it's created on
# the first apply after the resources above are adopted.
#
# Sub-sections (sections[] entries with sub_policy_name set) have no
# resource to import into: cato_if_section has no sub-policy parenting yet
# (see "Known provider gaps" below). They stay export/import-only, surfaced
# via the unmanaged_sub_sections output.
```

</details>

Preview the adoption — nothing touches state during a plan:

```bash
terraform plan
```

Expect:

```
Plan: N to import, 1 to add, 0 to change, 0 to destroy.
```

- **`N to import`** — every live section, rule, and sub-policy, adopted at its name-keyed address.
- **`1 to add`** — the `cato_bulk_if_move_rule` ordering resource (never imported; see the note above).
- **Any `to change`** — the JSON export is stale relative to the live policy. **Stop and re-export** (`catocli export if_rules`) rather than letting `terraform apply` overwrite live rules with stale config.

Once the plan reads clean, adopt:

```bash
terraform apply
```

Then **delete `migration.tf`** — it is one-shot by design; leaving it in place just re-evaluates the same (now no-op) import blocks on every future plan.

#### Option B — `catocli import if_rules_to_tf` (imperative alternative)

A prescriptive, one-command alternative for when authoring import blocks isn't practical (e.g. a fully scripted onboarding pipeline). It walks the exported JSON and runs `terraform import` for each section, rule, and sub-policy. Unlike Option A, state is mutated immediately as the command runs — there is no plan preview.

```bash
catocli import if_rules_to_tf config_data/all_ifw_rules_and_sections.json --module-name=module.if_rules
```

**Parameters:**
- `config_data/all_ifw_rules_and_sections.json`: Path to your exported JSON file
- `--module-name=module.if_rules`: The state address of your module instance (must match the `module "..."` label in your configuration)

#### Importing a single resource by hand

The state-address table above also drives one-off prescriptive imports, useful when a single rule or section was created out-of-band and just needs to be pulled into existing state:

```bash
terraform import 'module.if_rules.cato_if_rule.rules["My IFW Rule 1"]' <rule_id>
terraform import 'module.if_rules.cato_if_section.sections["My IFW Section 1"]' <section_id>
```

### Step 5 — Verify

```bash
terraform plan
```

- After **Option A**, the plan should report **no changes** — the apply that performed the imports also created the ordering resource.
- After **Option B**, the first plan shows `1 to add` (the `cato_bulk_if_move_rule` ordering resource) and nothing else; apply it once, after which plans report no changes.

Any other diff means the live policy and the JSON have drifted — re-export and compare before applying.

### Backup and Restore Workflow

If unintended changes are made directly to rules and sections in the Cato Management Application, you can restore to the last known good state:

1. **Apply your last known good configuration:**
   ```bash
   terraform apply
   ```
   This will restore rules and sections to match your Terraform configuration.

2. **Alternatively, re-export and compare:**
   ```bash
   catocli export if_rules
   # Compare with your existing JSON file to identify changes
   ```

## Sub-policies

The Internet Firewall supports **sub-policies**: a nested policy, scoped by a
`SUB_POLICY_SCOPE` rule, with its own rules and (optionally) its own
sub-sections. This module supports creating and ordering sub-policies and
their rules. The full JSON contract is specified in
`ifw-sub-policy-json-design.md` (companion design doc in the
`reference-architecture-cma-configs` repo) — this section summarizes the new
keys and the current limitations.

### New JSON keys

- `data.policy.internetFirewall.policy.sub_policies[]` - one entry per
  sub-policy: `sub_policy_name`, `description`, `enabled`, `scope` (the
  `SUB_POLICY_SCOPE` rule's matching criteria - same shape as a rule's
  top-level fields, minus `name`/`action`/`description`), plus
  `sub_policy_id`/`scope_rule_id` (brownfield import keys only; ignored on
  greenfield apply).
- `sections[]` entries may carry `sub_policy_name` to mark a sub-section owned
  by that sub-policy (`section_index` restarts per parent - main policy or
  owning sub-policy).
- `rules[]` entries may carry `sub_policy_name` to mark a rule owned by that
  sub-policy. The rule's `section.name` is either the sub-section's name or
  `""` when the sub-policy has no explicit sub-section.
- `rules_in_sections[]` rows gain two optional fields:
  - `entry_type`: `"rule"` (default) or `"sub_policy"` - a `"sub_policy"` row
    is the sub-policy's `SUB_POLICY_SCOPE` row, positioned among its sibling
    rules in the parent section via `index_in_section`.
  - `sub_policy_name`: on a rule row, orders that rule *inside* the named
    sub-policy (combined with `section_name: ""` for sub-policies without an
    explicit sub-section).

A legacy file (no `sub_policies` key, no `entry_type`/`sub_policy_name`
anywhere) is a valid instance of this schema and produces **byte-identical**
resource sets at today's addresses (`cato_if_section.sections["<name>"]`,
`cato_if_rule.rules["<name>"]`) - no state migration for existing deployments.

### Resources created

- `cato_if_sub_policy.sub_policies` - keyed by `sub_policy_name`. Positioned
  `LAST_IN_SECTION` under the parent section derived from its
  `entry_type: "sub_policy"` row in `rules_in_sections`; falls back to
  `LAST_IN_POLICY` when that parent section isn't managed by this module
  (e.g. `"Default Outbound Internet"`, or a sub-policies-only config with no
  custom sections at all).
- `cato_if_rule.sub_rules` - keyed `"<sub_policy_name>::<rule_name>"`, with
  `sub_policy_id` set to the owning `cato_if_sub_policy`.

### Known provider gaps

- **No sub-section resource.** The provider's `cato_if_section` has no
  sub-policy parenting yet, so sub-sections are **export/import-only** - this
  module does not create them. They're surfaced via the
  `unmanaged_sub_sections` output for visibility.
- **No ordering inside a sub-policy.** `cato_bulk_if_move_rule` does not yet
  support reordering rules *inside* a sub-policy (its reorder input's
  `SubRules` is always empty, and rules with an empty `SectionID` are skipped
  from main-policy reordering). Rows that would order a rule inside a
  sub-policy are excluded from the move resource and surfaced via the
  `unordered_sub_policy_rules` output instead - order inside a sub-policy is
  **creation-order best-effort only**. Sub-policies themselves (as scope rows
  among sibling rules in a section) ARE ordered correctly, since a scope row
  is a real rule in the live policy index with a real parent section.

## Using Module Outputs

The module provides comprehensive outputs that can be used for monitoring, auditing, integration with other systems, and operational insights. Below are practical examples of how to use these outputs in your Terraform configuration.

<details>
<summary>Click to expand example client-side outputs</summary>

```hcl
# Basic deployment information
output "deployment_info" {
  description = "Basic information about the Internet Firewall deployment"
  value = {
    total_sections = module.if_rules.deployment_summary.total_sections_created
    total_rules    = module.if_rules.deployment_summary.total_rules_created
    enabled_rules  = module.if_rules.deployment_summary.enabled_rules_count
    disabled_rules = module.if_rules.deployment_summary.disabled_rules_count
    source_file    = module.if_rules.parsed_configuration.source_file_path
  }
}

# Quick reference for rule and section IDs
output "quick_reference" {
  description = "Quick reference maps for rules and sections"
  value = {
    section_ids = module.if_rules.section_ids
    rule_ids    = module.if_rules.rule_ids
  }
}

# Security policy overview
output "security_policy_overview" {
  description = "Overview of the security policy configuration"
  value = {
    allow_rules_count = module.if_rules.deployment_summary.allow_rules_count
    block_rules_count = module.if_rules.deployment_summary.block_rules_count
    allow_rules       = module.if_rules.allow_rules
    block_rules       = module.if_rules.block_rules
    disabled_rules    = module.if_rules.disabled_rules
  }
}

# Detailed section structure
output "section_structure" {
  description = "Detailed view of how rules are organized in sections"
  value       = module.if_rules.sections_to_rules_mapping
}

# Bulk move operation details
output "bulk_move_details" {
  description = "Details about the bulk move operation that organized the rules"
  value       = module.if_rules.bulk_move_operation
}

# Configuration validation
output "configuration_validation" {
  description = "Validation information about the parsed configuration"
  value = {
    source_file           = module.if_rules.parsed_configuration.source_file_path
    rules_in_json         = module.if_rules.parsed_configuration.rules_data_count
    sections_in_json      = module.if_rules.parsed_configuration.sections_data_count
    rule_mappings_in_json = module.if_rules.parsed_configuration.rules_mapping_count
    section_order         = module.if_rules.parsed_configuration.section_names_ordered
    rules_created         = module.if_rules.deployment_summary.total_rules_created
    sections_created      = module.if_rules.deployment_summary.total_sections_created
  }
}

# Example: Filtered outputs for specific use cases
output "critical_rules" {
  description = "Example of filtering rules for critical security rules (BLOCK actions)"
  value = {
    block_rule_names = module.if_rules.block_rules
    block_rule_count = length(module.if_rules.block_rules)
    block_rule_ids   = [for rule_name in module.if_rules.block_rules : module.if_rules.rule_ids[rule_name]]
  }
}

# Example: Rules that might need attention
output "rules_needing_attention" {
  description = "Example of identifying rules that might need attention"
  value = {
    disabled_rules       = module.if_rules.disabled_rules
    disabled_rules_count = length(module.if_rules.disabled_rules)
    disabled_rule_ids    = [for rule_name in module.if_rules.disabled_rules : module.if_rules.rule_ids[rule_name]]
  }
}

# Example: Section-specific information
output "section_details" {
  description = "Example of extracting detailed information about sections"
  value = {
    section_names = module.if_rules.section_names
    sections_with_rule_counts = {
      for section_name, section_data in module.if_rules.sections_to_rules_mapping :
      section_name => {
        section_id = section_data.section_id
        rule_count = length(section_data.rules)
        rule_names = [for rule in section_data.rules : rule.rule_name]
      }
    }
  }
}

# Example: For integration with monitoring systems
output "monitoring_metrics" {
  description = "Example metrics that could be sent to monitoring systems"
  value = {
    deployment_timestamp     = timestamp()
    total_firewall_rules     = module.if_rules.deployment_summary.total_rules_created
    total_firewall_sections  = module.if_rules.deployment_summary.total_sections_created
    active_security_rules    = module.if_rules.deployment_summary.enabled_rules_count
    inactive_security_rules  = module.if_rules.deployment_summary.disabled_rules_count
    permissive_rules_count   = module.if_rules.deployment_summary.allow_rules_count
    restrictive_rules_count  = module.if_rules.deployment_summary.block_rules_count
    configuration_source     = basename(module.if_rules.parsed_configuration.source_file_path)
    bulk_move_operation_data = module.if_rules.bulk_move_operation
  }
}

# Example: For audit and compliance reporting
output "audit_report" {
  description = "Example audit report using module outputs"
  value = {
    deployment_summary = {
      date                = timestamp()
      source_config_file  = module.if_rules.parsed_configuration.source_file_path
      sections_deployed   = module.if_rules.deployment_summary.total_sections_created
      rules_deployed      = module.if_rules.deployment_summary.total_rules_created
      rules_by_status = {
        enabled  = module.if_rules.deployment_summary.enabled_rules_count
        disabled = module.if_rules.deployment_summary.disabled_rules_count
      }
      rules_by_action = {
        allow = module.if_rules.deployment_summary.allow_rules_count
        block = module.if_rules.deployment_summary.block_rules_count
      }
    }
    rule_organization = module.if_rules.sections_to_rules_mapping
    disabled_rules_list = module.if_rules.disabled_rules
    block_rules_list    = module.if_rules.block_rules
  }
}
```
</details>

### Output Use Cases

These example outputs demonstrate various practical applications:

- **`deployment_info`**: Quick deployment overview for dashboards
- **`quick_reference`**: ID mappings for referencing resources in other modules
- **`security_policy_overview`**: Security-focused analysis of rule actions
- **`section_structure`**: Understanding rule organization and hierarchy
- **`bulk_move_details`**: Operational details about the deployment process
- **`configuration_validation`**: Comparing JSON input with actual deployment
- **`critical_rules`**: Filtering for security-critical rules (BLOCK actions)
- **`rules_needing_attention`**: Identifying disabled rules for review
- **`section_details`**: Detailed section analysis with rule counts
- **`monitoring_metrics`**: Metrics formatted for monitoring systems
- **`audit_report`**: Comprehensive audit trail for compliance

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.13 |
| <a name="requirement_cato"></a> [cato](#requirement\_cato) | >= 1.2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_cato"></a> [cato](#provider\_cato) | >= 1.2.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [cato_bulk_if_move_rule.all_if_rules](https://registry.terraform.io/providers/catonetworks/cato/latest/docs/resources/bulk_if_move_rule) | resource |
| [cato_if_rule.rules](https://registry.terraform.io/providers/catonetworks/cato/latest/docs/resources/if_rule) | resource |
| [cato_if_rule.sub_rules](https://registry.terraform.io/providers/catonetworks/cato/latest/docs/resources/if_rule) | resource |
| [cato_if_section.sections](https://registry.terraform.io/providers/catonetworks/cato/latest/docs/resources/if_section) | resource |
| [cato_if_sub_policy.sub_policies](https://registry.terraform.io/providers/catonetworks/cato/latest/docs/resources/if_sub_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allow_empty_policy"></a> [allow\_empty\_policy](#input\_allow\_empty\_policy) | Safety guard: fail planning when the policy JSON contains 0 rules unless explicitly allowed. Protects against a truncated or wrong-tenant export destroying the live policy. Set true only for intentional greenfield/teardown. | `bool` | `false` | no |
| <a name="input_ifw_rules_json_file_path"></a> [ifw\_rules\_json\_file\_path](#input\_ifw\_rules\_json\_file\_path) | Path to the json file containing the ifw rule data. | `string` | n/a | yes |
| <a name="input_section_to_start_after_id"></a> [section\_to\_start\_after\_id](#input\_section\_to\_start\_after\_id) | The ID of the section after which to start adding rules. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_allow_rules"></a> [allow\_rules](#output\_allow\_rules) | List of rules with ALLOW action |
| <a name="output_block_rules"></a> [block\_rules](#output\_block\_rules) | List of rules with BLOCK action |
| <a name="output_bulk_move_operation"></a> [bulk\_move\_operation](#output\_bulk\_move\_operation) | Details of the bulk move operation |
| <a name="output_deployment_summary"></a> [deployment\_summary](#output\_deployment\_summary) | Summary statistics of the deployment |
| <a name="output_disabled_rules"></a> [disabled\_rules](#output\_disabled\_rules) | List of disabled rule names |
| <a name="output_enabled_rules"></a> [enabled\_rules](#output\_enabled\_rules) | List of enabled rule names |
| <a name="output_parsed_configuration"></a> [parsed\_configuration](#output\_parsed\_configuration) | Parsed configuration data from the JSON file |
| <a name="output_rule_ids"></a> [rule\_ids](#output\_rule\_ids) | Map of rule names to their IDs |
| <a name="output_rule_names"></a> [rule\_names](#output\_rule\_names) | List of all created rule names |
| <a name="output_rules"></a> [rules](#output\_rules) | Map of all created Internet Firewall rules with their details |
| <a name="output_rules_to_sections_mapping"></a> [rules\_to\_sections\_mapping](#output\_rules\_to\_sections\_mapping) | Mapping of rules to their assigned sections with ordering |
| <a name="output_section_ids"></a> [section\_ids](#output\_section\_ids) | Map of section names to their IDs |
| <a name="output_section_names"></a> [section\_names](#output\_section\_names) | List of all created section names |
| <a name="output_sections"></a> [sections](#output\_sections) | Map of all created Internet Firewall sections with their details |
| <a name="output_sections_to_rules_mapping"></a> [sections\_to\_rules\_mapping](#output\_sections\_to\_rules\_mapping) | Mapping of sections to their assigned rules with ordering |
| <a name="output_sub_policy_ids"></a> [sub\_policy\_ids](#output\_sub\_policy\_ids) | Map of sub-policy names to their IDs |
| <a name="output_sub_policy_scope_rule_ids"></a> [sub\_policy\_scope\_rule\_ids](#output\_sub\_policy\_scope\_rule\_ids) | Map of sub-policy names to the ID of their underlying SUB\_POLICY\_SCOPE rule |
| <a name="output_sub_rule_ids"></a> [sub\_rule\_ids](#output\_sub\_rule\_ids) | Map of sub-rules (keyed "<sub\_policy\_name>::<rule\_name>") to their IDs |
| <a name="output_unmanaged_sub_sections"></a> [unmanaged\_sub\_sections](#output\_unmanaged\_sub\_sections) | Sub-sections present in the JSON that this module cannot yet manage (no cato\_if\_section sub-policy parenting in the provider). Informational only. |
| <a name="output_unordered_sub_policy_rules"></a> [unordered\_sub\_policy\_rules](#output\_unordered\_sub\_policy\_rules) | rules\_in\_sections rows that order a rule inside a sub-policy, which cato\_bulk\_if\_move\_rule does not yet support. Informational only. |
<!-- END_TF_DOCS -->