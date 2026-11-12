# Changelog

## 0.0.9 (2026-11-04)

### Features
- Sub-policy support: `cato_if_sub_policy` with embedded API-created cleanup
  rule, `cato_if_rule.sub_rules` (keyed `<sub_policy_name>::<rule_name>`),
  scope rows ordered via `cato_bulk_if_move_rule`, shared `rule_bodies` local
  across main/sub/cleanup rules. New outputs: `sub_policy_ids`,
  `sub_policy_scope_rule_ids`, `sub_rule_ids`, `cleanup_rule_ids`,
  `unmanaged_sub_sections`, `unordered_sub_policies`,
  `unordered_sub_policy_rules`. Legacy (flat) JSON exports are unaffected.
- Added `allow_empty_policy` safety guard — planning fails when the policy
  JSON contains 0 rules unless explicitly allowed, protecting against
  truncated or wrong-tenant exports mass-destroying a live policy.
- README: brownfield import documentation now covers two options — native
  Terraform `import` blocks (recommended, declarative/previewable) and the
  `catocli import if_rules_to_tf` imperative alternative.

## 0.0.1 (2025-07-05)

### Features
- Initial bulk ifw rule module release

## 0.0.2 (2025-07-15)

### Features
- Refactor section data to sort and index by name to support reordering of source json without error

## 0.0.3 (2025-07-23)

### Features
- Fixed state management issues with name to id mapping

## 0.0.4 (2025-10-28)

### Features
- Fixed tracking.alert parsing and device_attributes

## 0.0.6 (2025-11-01)

### Features
- Updated required cato provider to 49 and TF version to >= 1.13

## 0.0.8 (2025-11-01)

### Features
- Updated import logic around customService with portrange, and subnet inpur params
