locals {
  ifw_rules_json = jsondecode(file("${var.ifw_rules_json_file_path}"))
  ifw_rules_data = local.ifw_rules_json.data.policy.internetFirewall.policy.rules

  sections_data_unsorted = local.ifw_rules_json.data.policy.internetFirewall.policy.sections
  rules_in_sections_data = local.ifw_rules_json.data.policy.internetFirewall.policy.rules_in_sections
  sub_policies_data_raw  = try(local.ifw_rules_json.data.policy.internetFirewall.policy.sub_policies, [])

  # ───────────────────────────────────────────────────────────────────────
  # Backward-compatible split (design doc:
  # ifw-sub-policy-json-design.md). Legacy files have no sub_policies key and
  # no sub_policy_name/entry_type anywhere, so every try() below defaults to
  # "main policy" / "rule" and this split is a no-op: main_* == today's full
  # data, byte-identical resource sets at today's addresses.
  # ───────────────────────────────────────────────────────────────────────

  # Sections: main (no sub_policy_name) vs sub-sections (sub_policy_name set).
  main_sections_unsorted = [for s in local.sections_data_unsorted : s if try(s.sub_policy_name, null) == null]
  sub_sections_unsorted  = [for s in local.sections_data_unsorted : s if try(s.sub_policy_name, null) != null]

  # Create a map with section_index as key to sort sections correctly
  sections_by_index = {
    for section in local.main_sections_unsorted :
    tostring(section.section_index) => section
  }
  # Sort sections by section_index to ensure consistent ordering regardless of JSON file order
  sections_data_list = [
    for index in sort(keys(local.sections_by_index)) :
    local.sections_by_index[index]
  ]
  # Convert sections to map for provider schema compatibility
  sections_data = {
    for section in local.sections_data_list :
    section.section_name => section
  }

  # Sub-sections: NOT managed by this module yet (cato_if_section has no
  # sub-policy parenting) — exposed via the unmanaged_sub_sections output
  # only. Keyed "<sub_policy_name>::<section_name>" (the composite identity
  # from the design doc) since two different sub-policies may each have a
  # sub-section with the same name.
  sub_sections_data = {
    for s in local.sub_sections_unsorted :
    "${s.sub_policy_name}::${s.section_name}" => s
  }

  # Rules: main-policy rules (no sub_policy_name) vs sub-policy rules.
  main_rules_data = [for r in local.ifw_rules_data : r if try(r.sub_policy_name, null) == null]
  sub_rules_data  = [for r in local.ifw_rules_data : r if try(r.sub_policy_name, null) != null]

  # Sub-policies metadata, keyed by name (the for_each key / lookup key).
  sub_policies_data = {
    for sp in local.sub_policies_data_raw :
    sp.sub_policy_name => sp
  }

  # Parent-section lookup for each sub-policy, derived from its
  # entry_type == "sub_policy" row in rules_in_sections (the scope row's
  # position among sibling rules in the parent section).
  sub_policy_parent_section = {
    for row in local.rules_in_sections_data :
    row.sub_policy_name => row.section_name
    if try(row.entry_type, "rule") == "sub_policy"
  }

  # ───────────────────────────────────────────────────────────────────────
  # rules_in_sections split for the move resource (cato_bulk_if_move_rule):
  #   - plain main-policy rule rows (sub_policy_name absent/null) - unchanged
  #   - sub-policy SCOPE rows (entry_type == "sub_policy") remapped into a
  #     rule-shaped row (rule_name = sub_policy_name) - scope rows ARE rules
  #     in the live index with a real parent section, so the move resource
  #     can order sub-policies among sibling rules by name.
  # Rows that order a rule INSIDE a sub-policy (sub_policy_name set on a rule
  # row, entry_type default "rule") are EXCLUDED here - the provider's
  # cato_bulk_if_move_rule has no support yet for ordering inside sub-policies
  # (its reorder input's SubRules is always built empty, and rules with an
  # empty SectionID are skipped). They are surfaced via the
  # unordered_sub_policy_rules output instead.
  # Scope rows whose parent section is NOT managed by this module (e.g. the
  # account's default section, or any section absent from sections[]) are also
  # EXCLUDED: cato_if_sub_policy already placed them via the LAST_IN_POLICY
  # fallback, and a move row naming a section the reorder input can't resolve
  # drops the scope rule from the input entirely - the API then rejects the
  # whole reorder with reorderPolicyMissingRules. Surfaced via the
  # unordered_sub_policies output instead.
  # ───────────────────────────────────────────────────────────────────────
  main_policy_move_rows = concat(
    [for row in local.rules_in_sections_data : row if try(row.sub_policy_name, null) == null],
    [
      for row in local.rules_in_sections_data : {
        index_in_section = row.index_in_section
        section_name     = row.section_name
        rule_name        = row.sub_policy_name
      }
      if try(row.entry_type, "rule") == "sub_policy" && contains(keys(local.sections_data), row.section_name)
    ]
  )

  unordered_sub_policies_data = [
    for row in local.rules_in_sections_data : row
    if try(row.entry_type, "rule") == "sub_policy" && !contains(keys(local.sections_data), row.section_name)
  ]
  # Convert rules to map for provider schema compatibility
  rules_data = {
    for rule in local.main_policy_move_rows :
    rule.rule_name => rule
  }

  unordered_sub_policy_rules_data = [
    for row in local.rules_in_sections_data : row
    if try(row.sub_policy_name, null) != null && try(row.entry_type, "rule") == "rule"
  ]

  # ───────────────────────────────────────────────────────────────────────
  # Shared rule-body construction. Main rules and sub-rules carry the exact
  # same `rules[]` entry shape ({audit, rule, properties, sub_policy_name?}),
  # so the merge pattern below is computed once, keyed by rule name (rule
  # names are globally unique - existing module constraint), and both the
  # `cato_if_rule.rules` and `cato_if_rule.sub_rules` resources look up into
  # it. This is the same try()-guard merge pattern used for every rule field.
  # ───────────────────────────────────────────────────────────────────────
  # Cleanup rules ride along in sub_policies[].cleanup_rule (the API auto-creates
  # one per sub-policy; cato_if_sub_policy embeds and manages it). Their entry
  # shape matches rules[] exactly, so they share the rule_bodies merge below.
  cleanup_rule_entries = [
    for sp in local.sub_policies_data_raw : sp.cleanup_rule
    if try(sp.cleanup_rule, null) != null
  ]

  rule_bodies = {
    for entry in concat(local.main_rules_data, local.sub_rules_data, local.cleanup_rule_entries) :
    entry.rule.name => merge(
      {
        name    = entry.rule.name
        enabled = entry.rule.enabled
        action  = entry.rule.action
        # Always include tracking block with defaults
        tracking = {
          alert = merge(
            {
              enabled   = try(entry.rule.tracking.alert.enabled, false)
              frequency = try(entry.rule.tracking.alert.frequency, "IMMEDIATE")
            },
            # Only include mailing_list if it exists and is not empty
            try(length(entry.rule.tracking.alert.mailingList), 0) > 0 ? {
              mailing_list = [for ml in entry.rule.tracking.alert.mailingList : can(ml.name) ? { name = ml.name } : { id = ml.id }]
            } : {},
            # Only include subscription_group if it exists and is not empty
            try(length(entry.rule.tracking.alert.subscriptionGroup), 0) > 0 ? {
              subscription_group = [for sg in entry.rule.tracking.alert.subscriptionGroup : can(sg.name) ? { name = sg.name } : { id = sg.id }]
            } : {},
            # Only include webhook if it exists and is not empty
            try(length(entry.rule.tracking.alert.webhook), 0) > 0 ? {
              webhook = [for wh in entry.rule.tracking.alert.webhook : can(wh.name) ? { name = wh.name } : { id = wh.id }]
            } : {}
          )
          event = {
            enabled = try(entry.rule.tracking.event.enabled, true)
          }
        }
      },

      # Only include description if it's not empty
      entry.rule.description != "" ? {
        description = entry.rule.description
      } : {},

      # Only include connection_origin if it exists
      try(entry.rule.connectionOrigin, null) != null ? {
        connection_origin = entry.rule.connectionOrigin
      } : {},

      # Only include device_os if it exists and is not empty
      try(length(entry.rule.deviceOS), 0) > 0 ? {
        device_os = entry.rule.deviceOS
      } : {},

      # Only include country if it exists and is not empty
      try(length(entry.rule.country), 0) > 0 ? {
        country = [for country in entry.rule.country : can(country.name) ? { name = country.name } : { id = country.id }]
      } : {},

      # Only include device if it exists and is not empty
      try(length(entry.rule.device), 0) > 0 ? {
        device = [for device in entry.rule.device : can(device.name) ? { name = device.name } : { id = device.id }]
      } : {},

      # Dynamic source block - include if source exists (even if empty)
      try(entry.rule.source, null) != null ? {
        source = {
          for k, v in {
            ip          = try(length(entry.rule.source.ip), 0) > 0 ? entry.rule.source.ip : null
            host        = try(length(entry.rule.source.host), 0) > 0 ? [for host in entry.rule.source.host : can(host.name) ? { name = host.name } : { id = host.id }] : null
            site        = try(length(entry.rule.source.site), 0) > 0 ? [for site in entry.rule.source.site : can(site.name) ? { name = site.name } : { id = site.id }] : null
            users_group = try(length(entry.rule.source.usersGroup), 0) > 0 ? [for group in entry.rule.source.usersGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
            subnet      = try(length(entry.rule.source.subnet), 0) > 0 && can(entry.rule.source.subnet[0].name) || can(entry.rule.source.subnet[0].id) ? [for subnet in entry.rule.source.subnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
            ip_range = try(length(entry.rule.source.ipRange), 0) > 0 ? [for range in entry.rule.source.ipRange : {
              from = range.from
              to   = range.to
            }] : null
            network_interface   = try(length(entry.rule.source.networkInterface), 0) > 0 ? [for ni in entry.rule.source.networkInterface : can(ni.name) ? { name = ni.name } : { id = ni.id }] : null
            floating_subnet     = try(length(entry.rule.source.floatingSubnet), 0) > 0 ? [for subnet in entry.rule.source.floatingSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
            site_network_subnet = try(length(entry.rule.source.siteNetworkSubnet), 0) > 0 ? [for subnet in entry.rule.source.siteNetworkSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
            system_group        = try(length(entry.rule.source.systemGroup), 0) > 0 ? [for group in entry.rule.source.systemGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
            group               = try(length(entry.rule.source.group), 0) > 0 ? [for group in entry.rule.source.group : can(group.name) ? { name = group.name } : { id = group.id }] : null
            user                = try(length(entry.rule.source.user), 0) > 0 ? [for user in entry.rule.source.user : can(user.name) ? { name = user.name } : { id = user.id }] : null
          } : k => v if v != null
        }
      } : {},

      # Dynamic destination block - always include destination even if empty
      {
        destination = {
          for k, v in {
            app_category             = try(length(entry.rule.destination.appCategory), 0) > 0 ? [for cat in entry.rule.destination.appCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null
            application              = try(length(entry.rule.destination.application), 0) > 0 ? [for app in entry.rule.destination.application : can(app.name) ? { name = app.name } : { id = app.id }] : null
            custom_app               = try(length(entry.rule.destination.customApp), 0) > 0 ? [for app in entry.rule.destination.customApp : can(app.name) ? { name = app.name } : { id = app.id }] : null
            custom_category          = try(length(entry.rule.destination.customCategory), 0) > 0 ? [for cat in entry.rule.destination.customCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null
            sanctioned_apps_category = try(length(entry.rule.destination.sanctionedAppsCategory), 0) > 0 ? [for cat in entry.rule.destination.sanctionedAppsCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null
            domain                   = try(length(entry.rule.destination.domain), 0) > 0 ? entry.rule.destination.domain : null
            fqdn                     = try(length(entry.rule.destination.fqdn), 0) > 0 ? entry.rule.destination.fqdn : null
            ip                       = try(length(entry.rule.destination.ip), 0) > 0 ? entry.rule.destination.ip : null
            ip_range = try(length(entry.rule.destination.ipRange), 0) > 0 ? [for range in entry.rule.destination.ipRange : {
              from = range.from
              to   = range.to
            }] : null
            country    = try(length(entry.rule.destination.country), 0) > 0 ? [for country in entry.rule.destination.country : can(country.name) ? { name = country.name } : { id = country.id }] : null
            remote_asn = try(length(entry.rule.destination.remoteAsn), 0) > 0 ? entry.rule.destination.remoteAsn : null
          } : k => v if v != null
        }
      },

      # Dynamic service block - only if service has content
      try(length(entry.rule.service.standard), 0) > 0 || try(length(entry.rule.service.custom), 0) > 0 ? {
        service = {
          for k, v in {
            standard = try(length(entry.rule.service.standard), 0) > 0 ? [for svc in entry.rule.service.standard : can(svc.name) ? { name = svc.name } : { id = svc.id }] : null

            custom = try(length(entry.rule.service.custom), 0) > 0 ? [for svc in entry.rule.service.custom : {
              protocol = svc.protocol
              port     = try(length(svc.port), 0) > 0 ? [for p in svc.port : tostring(p)] : null
              port_range = try(svc.portRange, null) != null ? {
                from = tostring(svc.portRange.from)
                to   = tostring(svc.portRange.to)
              } : null
            }] : null
          } : k => v if v != null
        }
      } : {},

      # Dynamic schedule block - only if custom schedules exist
      try(entry.rule.schedule.customTimeframePolicySchedule, null) != null ||
      try(entry.rule.schedule.customRecurringPolicySchedule, null) != null ||
      try(entry.rule.schedule.activeOn, "ALWAYS") != "ALWAYS" ? {
        schedule = {
          for k, v in {
            active_on        = try(entry.rule.schedule.activeOn, "ALWAYS")
            custom_timeframe = try(entry.rule.schedule.customTimeframePolicySchedule, null)
            custom_recurring = try(entry.rule.schedule.customRecurringPolicySchedule, null)
          } : k => v if v != null && (k != "active_on" || v != "ALWAYS")
        }
      } : {},

      # Dynamic exceptions block - only if exceptions exist
      try(length(entry.rule.exceptions), 0) > 0 ? {
        exceptions = [
          for exception in entry.rule.exceptions : merge(
            {
              name = exception.name
            },

            # Exception connection_origin
            try(exception.connectionOrigin, null) != null ? {
              connection_origin = exception.connectionOrigin
            } : {},

            # Exception country
            try(length(exception.country), 0) > 0 ? {
              country = [for country in exception.country : can(country.name) ? { name = country.name } : { id = country.id }]
            } : {},

            # Exception device_os - only include if not empty
            try(length(exception.deviceOS), 0) > 0 ? {
              device_os = exception.deviceOS
            } : {},

            # Exception source - always required
            {
              source = {
                for k, v in {
                  ip                = try(length(exception.source.ip), 0) > 0 ? exception.source.ip : null
                  host              = try(length(exception.source.host), 0) > 0 ? [for host in exception.source.host : can(host.name) ? { name = host.name } : { id = host.id }] : null
                  site              = try(length(exception.source.site), 0) > 0 ? [for site in exception.source.site : can(site.name) ? { name = site.name } : { id = site.id }] : null
                  users_group       = try(length(exception.source.usersGroup), 0) > 0 ? [for group in exception.source.usersGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
                  network_interface = try(length(exception.source.networkInterface), 0) > 0 ? [for ni in exception.source.networkInterface : can(ni.name) ? { name = ni.name } : { id = ni.id }] : null
                  ip_range = try(length(exception.source.ipRange), 0) > 0 ? [for range in exception.source.ipRange : {
                    from = range.from
                    to   = range.to
                  }] : null
                  floating_subnet     = try(length(exception.source.floatingSubnet), 0) > 0 ? [for subnet in exception.source.floatingSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
                  site_network_subnet = try(length(exception.source.siteNetworkSubnet), 0) > 0 ? [for subnet in exception.source.siteNetworkSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
                  system_group        = try(length(exception.source.systemGroup), 0) > 0 ? [for group in exception.source.systemGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
                  group               = try(length(exception.source.group), 0) > 0 ? [for group in exception.source.group : can(group.name) ? { name = group.name } : { id = group.id }] : null
                  user                = try(length(exception.source.user), 0) > 0 ? [for user in exception.source.user : can(user.name) ? { name = user.name } : { id = user.id }] : null
                  subnet              = try(length(exception.source.subnet), 0) > 0 && can(exception.source.subnet[0].name) || can(exception.source.subnet[0].id) ? [for subnet in exception.source.subnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
                } : k => v if v != null
              }
            },

            # Exception destination - always required
            {
              destination = {
                for k, v in {
                  app_category             = try(length(exception.destination.appCategory), 0) > 0 ? [for cat in exception.destination.appCategory : { name = cat.name }] : null
                  application              = try(length(exception.destination.application), 0) > 0 ? [for app in exception.destination.application : { name = app.name }] : null
                  custom_app               = try(length(exception.destination.customApp), 0) > 0 ? [for app in exception.destination.customApp : { name = app.name }] : null
                  custom_category          = try(length(exception.destination.customCategory), 0) > 0 ? [for cat in exception.destination.customCategory : { name = cat.name }] : null
                  sanctioned_apps_category = try(length(exception.destination.sanctionedAppsCategory), 0) > 0 ? [for cat in exception.destination.sanctionedAppsCategory : { name = cat.name }] : null
                  domain                   = try(length(exception.destination.domain), 0) > 0 ? exception.destination.domain : null
                  fqdn                     = try(length(exception.destination.fqdn), 0) > 0 ? exception.destination.fqdn : null
                  country                  = try(length(exception.destination.country), 0) > 0 ? [for country in exception.destination.country : { name = country.name }] : null
                  ip                       = try(length(exception.destination.ip), 0) > 0 ? exception.destination.ip : null
                  subnet                   = try(length(exception.destination.subnet), 0) > 0 ? [for subnet in exception.destination.subnet : { name = subnet.name }] : null
                  ip_range = try(length(exception.destination.ipRange), 0) > 0 ? [for range in exception.destination.ipRange : {
                    from = range.from
                    to   = range.to
                  }] : null
                  remote_asn = try(length(exception.destination.remoteAsn), 0) > 0 ? exception.destination.remoteAsn : null
                } : k => v if v != null
              }
            },

            # Exception service - always required
            {
              service = {
                for k, v in {
                  standard = try(length(exception.service.standard), 0) > 0 ? [for svc in exception.service.standard : { name = svc.name }] : null

                  custom = try(length(exception.service.custom), 0) > 0 ? [for svc in exception.service.custom : {
                    protocol = svc.protocol
                    port     = svc.port
                  }] : null
                } : k => v if v != null
              }
            }
          )
        ]
      } : {}
    )
  }
}

# Safety guard: fails plan if the main policy has 0 rules, unless
# allow_empty_policy is explicitly set — protects against a truncated or
# wrong-tenant export destroying the live policy via an empty for_each.
resource "terraform_data" "guard_empty_policy" {
  lifecycle {
    precondition {
      condition     = var.allow_empty_policy || length(local.main_rules_data) > 0
      error_message = "Policy JSON contains 0 rules. If intentional (greenfield/teardown), set allow_empty_policy = true. A truncated or wrong-tenant export would otherwise destroy the entire live policy."
    }
  }
}

resource "cato_if_section" "sections" {
  for_each = local.sections_data
  at = {
    position = "LAST_IN_POLICY"
  }
  section = {
    name = each.value.section_name
  }
}

resource "cato_if_rule" "rules" {
  depends_on = [cato_if_section.sections]
  for_each   = { for rule in local.main_rules_data : rule.rule.name => rule }

  at = {
    position = "LAST_IN_POLICY" // adding last to reorder in cato_bulk_if_move_rule
  }

  rule = local.rule_bodies[each.value.rule.name]
}

resource "cato_bulk_if_move_rule" "all_if_rules" {
  depends_on                = [cato_if_section.sections, cato_if_rule.rules, cato_if_sub_policy.sub_policies]
  rule_data                 = local.rules_data
  section_data              = local.sections_data
  section_to_start_after_id = var.section_to_start_after_id != null ? var.section_to_start_after_id : null
}

# ─────────────────────────────────────────────────────────────────────────
# Sub-policies (NEW). See ifw-sub-policy-json-design.md for the full schema.
# Keyed by sub_policy_name (globally unique, same constraint as rule names).
# ─────────────────────────────────────────────────────────────────────────
resource "cato_if_sub_policy" "sub_policies" {
  depends_on = [cato_if_section.sections]
  for_each   = local.sub_policies_data

  name        = each.value.sub_policy_name
  description = try(each.value.description, "")

  # Cleanup rule: the API auto-creates one per sub-policy; when the export
  # nests it (sub_policies[].cleanup_rule) manage it with the configured body,
  # otherwise omit it and adopt the API default (ALLOW, tracking disabled).
  cleanup_rule = try(local.rule_bodies[each.value.cleanup_rule.rule.name], null)

  # Position: LAST_IN_SECTION under the parent section derived from this
  # sub-policy's entry_type == "sub_policy" row in rules_in_sections. Some
  # configs scope sub-policies directly under "Default Outbound Internet",
  # which this module does not manage as a cato_if_section resource (and may
  # not exist in sections_data at all, e.g. a sub-policies-only config) - in
  # that case fall back to LAST_IN_POLICY with no ref.
  at = contains(keys(local.sections_data), try(local.sub_policy_parent_section[each.key], "")) ? {
    position = "LAST_IN_SECTION"
    ref      = cato_if_section.sections[local.sub_policy_parent_section[each.key]].id
    } : {
    position = "LAST_IN_POLICY"
  }

  # Scope: same try()-guard merge pattern as cato_if_rule.rules, applied to
  # each.value.scope instead of each.value.rule - but action/name/description
  # are Computed on the provider's scope attribute and must NOT be passed.
  # enabled comes from scope_enabled (the SUB_POLICY_SCOPE rule's flag, the
  # one terraform can manage) - NOT from each.value.enabled, which mirrors the
  # sub-policy object's own policy.enabled: that flag is not settable via the
  # public API (no enabled on addSubPolicy, no updateSubPolicy, no policy
  # selector on updatePolicy) and is informational only in the export.
  scope = merge(
    {
      enabled = try(each.value.scope_enabled, true)

    },

    # Only include connection_origin if it exists
    try(each.value.scope.connectionOrigin, null) != null ? {
      connection_origin = each.value.scope.connectionOrigin
    } : {},

    # Only include device_os if it exists and is not empty
    try(length(each.value.scope.deviceOS), 0) > 0 ? {
      device_os = each.value.scope.deviceOS
    } : {},

    # Only include country if it exists and is not empty
    try(length(each.value.scope.country), 0) > 0 ? {
      country = [for country in each.value.scope.country : can(country.name) ? { name = country.name } : { id = country.id }]
    } : {},

    # Only include device if it exists and is not empty
    try(length(each.value.scope.device), 0) > 0 ? {
      device = [for device in each.value.scope.device : can(device.name) ? { name = device.name } : { id = device.id }]
    } : {},

    # Dynamic source block - include if source exists (even if empty)
    try(each.value.scope.source, null) != null ? {
      source = {
        for k, v in {
          ip          = try(length(each.value.scope.source.ip), 0) > 0 ? each.value.scope.source.ip : null
          host        = try(length(each.value.scope.source.host), 0) > 0 ? [for host in each.value.scope.source.host : can(host.name) ? { name = host.name } : { id = host.id }] : null
          site        = try(length(each.value.scope.source.site), 0) > 0 ? [for site in each.value.scope.source.site : can(site.name) ? { name = site.name } : { id = site.id }] : null
          users_group = try(length(each.value.scope.source.usersGroup), 0) > 0 ? [for group in each.value.scope.source.usersGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
          subnet      = try(length(each.value.scope.source.subnet), 0) > 0 && can(each.value.scope.source.subnet[0].name) || can(each.value.scope.source.subnet[0].id) ? [for subnet in each.value.scope.source.subnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
          ip_range = try(length(each.value.scope.source.ipRange), 0) > 0 ? [for range in each.value.scope.source.ipRange : {
            from = range.from
            to   = range.to
          }] : null
          network_interface   = try(length(each.value.scope.source.networkInterface), 0) > 0 ? [for ni in each.value.scope.source.networkInterface : can(ni.name) ? { name = ni.name } : { id = ni.id }] : null
          floating_subnet     = try(length(each.value.scope.source.floatingSubnet), 0) > 0 ? [for subnet in each.value.scope.source.floatingSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
          site_network_subnet = try(length(each.value.scope.source.siteNetworkSubnet), 0) > 0 ? [for subnet in each.value.scope.source.siteNetworkSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
          system_group        = try(length(each.value.scope.source.systemGroup), 0) > 0 ? [for group in each.value.scope.source.systemGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
          group               = try(length(each.value.scope.source.group), 0) > 0 ? [for group in each.value.scope.source.group : can(group.name) ? { name = group.name } : { id = group.id }] : null
          user                = try(length(each.value.scope.source.user), 0) > 0 ? [for user in each.value.scope.source.user : can(user.name) ? { name = user.name } : { id = user.id }] : null
        } : k => v if v != null
      }
    } : {},

    # Dynamic destination block - always include destination even if empty
    {
      destination = {
        for k, v in {
          app_category             = try(length(each.value.scope.destination.appCategory), 0) > 0 ? [for cat in each.value.scope.destination.appCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null
          application              = try(length(each.value.scope.destination.application), 0) > 0 ? [for app in each.value.scope.destination.application : can(app.name) ? { name = app.name } : { id = app.id }] : null
          custom_app               = try(length(each.value.scope.destination.customApp), 0) > 0 ? [for app in each.value.scope.destination.customApp : can(app.name) ? { name = app.name } : { id = app.id }] : null
          custom_category          = try(length(each.value.scope.destination.customCategory), 0) > 0 ? [for cat in each.value.scope.destination.customCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null
          sanctioned_apps_category = try(length(each.value.scope.destination.sanctionedAppsCategory), 0) > 0 ? [for cat in each.value.scope.destination.sanctionedAppsCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null
          domain                   = try(length(each.value.scope.destination.domain), 0) > 0 ? each.value.scope.destination.domain : null
          fqdn                     = try(length(each.value.scope.destination.fqdn), 0) > 0 ? each.value.scope.destination.fqdn : null
          ip                       = try(length(each.value.scope.destination.ip), 0) > 0 ? each.value.scope.destination.ip : null
          ip_range = try(length(each.value.scope.destination.ipRange), 0) > 0 ? [for range in each.value.scope.destination.ipRange : {
            from = range.from
            to   = range.to
          }] : null
          country    = try(length(each.value.scope.destination.country), 0) > 0 ? [for country in each.value.scope.destination.country : can(country.name) ? { name = country.name } : { id = country.id }] : null
          remote_asn = try(length(each.value.scope.destination.remoteAsn), 0) > 0 ? each.value.scope.destination.remoteAsn : null
        } : k => v if v != null
      }
    },

    # Dynamic service block - only if service has content
    try(length(each.value.scope.service.standard), 0) > 0 || try(length(each.value.scope.service.custom), 0) > 0 ? {
      service = {
        for k, v in {
          standard = try(length(each.value.scope.service.standard), 0) > 0 ? [for svc in each.value.scope.service.standard : can(svc.name) ? { name = svc.name } : { id = svc.id }] : null

          custom = try(length(each.value.scope.service.custom), 0) > 0 ? [for svc in each.value.scope.service.custom : {
            protocol = svc.protocol
            port     = try(length(svc.port), 0) > 0 ? [for p in svc.port : tostring(p)] : null
            port_range = try(svc.portRange, null) != null ? {
              from = tostring(svc.portRange.from)
              to   = tostring(svc.portRange.to)
            } : null
          }] : null
        } : k => v if v != null
      }
    } : {},

    # Dynamic schedule block - only if custom schedules exist
    try(each.value.scope.schedule.customTimeframePolicySchedule, null) != null ||
    try(each.value.scope.schedule.customRecurringPolicySchedule, null) != null ||
    try(each.value.scope.schedule.activeOn, "ALWAYS") != "ALWAYS" ? {
      schedule = {
        for k, v in {
          active_on        = try(each.value.scope.schedule.activeOn, "ALWAYS")
          custom_timeframe = try(each.value.scope.schedule.customTimeframePolicySchedule, null)
          custom_recurring = try(each.value.scope.schedule.customRecurringPolicySchedule, null)
        } : k => v if v != null && (k != "active_on" || v != "ALWAYS")
      }
    } : {},

    # Dynamic exceptions block - only if exceptions exist
    try(length(each.value.scope.exceptions), 0) > 0 ? {
      exceptions = [
        for exception in each.value.scope.exceptions : merge(
          {
            name = exception.name
          },
          try(exception.connectionOrigin, null) != null ? {
            connection_origin = exception.connectionOrigin
          } : {},
          try(length(exception.country), 0) > 0 ? {
            country = [for country in exception.country : can(country.name) ? { name = country.name } : { id = country.id }]
          } : {},
          try(length(exception.deviceOS), 0) > 0 ? {
            device_os = exception.deviceOS
          } : {},
          {
            source = {
              for k, v in {
                ip                = try(length(exception.source.ip), 0) > 0 ? exception.source.ip : null
                host              = try(length(exception.source.host), 0) > 0 ? [for host in exception.source.host : can(host.name) ? { name = host.name } : { id = host.id }] : null
                site              = try(length(exception.source.site), 0) > 0 ? [for site in exception.source.site : can(site.name) ? { name = site.name } : { id = site.id }] : null
                users_group       = try(length(exception.source.usersGroup), 0) > 0 ? [for group in exception.source.usersGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
                network_interface = try(length(exception.source.networkInterface), 0) > 0 ? [for ni in exception.source.networkInterface : can(ni.name) ? { name = ni.name } : { id = ni.id }] : null
                ip_range = try(length(exception.source.ipRange), 0) > 0 ? [for range in exception.source.ipRange : {
                  from = range.from
                  to   = range.to
                }] : null
                floating_subnet     = try(length(exception.source.floatingSubnet), 0) > 0 ? [for subnet in exception.source.floatingSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
                site_network_subnet = try(length(exception.source.siteNetworkSubnet), 0) > 0 ? [for subnet in exception.source.siteNetworkSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
                system_group        = try(length(exception.source.systemGroup), 0) > 0 ? [for group in exception.source.systemGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
                group               = try(length(exception.source.group), 0) > 0 ? [for group in exception.source.group : can(group.name) ? { name = group.name } : { id = group.id }] : null
                user                = try(length(exception.source.user), 0) > 0 ? [for user in exception.source.user : can(user.name) ? { name = user.name } : { id = user.id }] : null
                subnet              = try(length(exception.source.subnet), 0) > 0 && can(exception.source.subnet[0].name) || can(exception.source.subnet[0].id) ? [for subnet in exception.source.subnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
              } : k => v if v != null
            }
          },
          {
            destination = {
              for k, v in {
                app_category             = try(length(exception.destination.appCategory), 0) > 0 ? [for cat in exception.destination.appCategory : { name = cat.name }] : null
                application              = try(length(exception.destination.application), 0) > 0 ? [for app in exception.destination.application : { name = app.name }] : null
                custom_app               = try(length(exception.destination.customApp), 0) > 0 ? [for app in exception.destination.customApp : { name = app.name }] : null
                custom_category          = try(length(exception.destination.customCategory), 0) > 0 ? [for cat in exception.destination.customCategory : { name = cat.name }] : null
                sanctioned_apps_category = try(length(exception.destination.sanctionedAppsCategory), 0) > 0 ? [for cat in exception.destination.sanctionedAppsCategory : { name = cat.name }] : null
                domain                   = try(length(exception.destination.domain), 0) > 0 ? exception.destination.domain : null
                fqdn                     = try(length(exception.destination.fqdn), 0) > 0 ? exception.destination.fqdn : null
                country                  = try(length(exception.destination.country), 0) > 0 ? [for country in exception.destination.country : { name = country.name }] : null
                ip                       = try(length(exception.destination.ip), 0) > 0 ? exception.destination.ip : null
                subnet                   = try(length(exception.destination.subnet), 0) > 0 ? [for subnet in exception.destination.subnet : { name = subnet.name }] : null
                ip_range = try(length(exception.destination.ipRange), 0) > 0 ? [for range in exception.destination.ipRange : {
                  from = range.from
                  to   = range.to
                }] : null
                remote_asn = try(length(exception.destination.remoteAsn), 0) > 0 ? exception.destination.remoteAsn : null
              } : k => v if v != null
            }
          },
          {
            service = {
              for k, v in {
                standard = try(length(exception.service.standard), 0) > 0 ? [for svc in exception.service.standard : { name = svc.name }] : null
                custom = try(length(exception.service.custom), 0) > 0 ? [for svc in exception.service.custom : {
                  protocol = svc.protocol
                  port     = svc.port
                }] : null
              } : k => v if v != null
            }
          }
        )
      ]
    } : {}
  )
}

# ─────────────────────────────────────────────────────────────────────────
# Sub-rules (NEW): rules owned by a sub-policy. Keyed "<sub_policy_name>::
# <rule_name>" (composite identity, mirroring sub_sections_data). The rule
# body is looked up from the shared local.rule_bodies by rule name (globally
# unique). `at` is always LAST_IN_POLICY - the provider repositions the rule
# inside the sub-policy, before its cleanup rule, automatically.
#
# IMPORTANT provider gap: ordering of rules WITHIN a sub-policy is
# creation-order best-effort only. cato_bulk_if_move_rule does not yet
# support reordering inside sub-policies (see main.tf locals comment above /
# ifw-sub-policy-json-design.md "Provider gap"), so index_in_section on a
# sub-policy's rule rows (see unordered_sub_policy_rules output) is NOT
# enforced by this module today.
# ─────────────────────────────────────────────────────────────────────────
resource "cato_if_rule" "sub_rules" {
  depends_on = [cato_if_sub_policy.sub_policies]
  for_each   = { for rule in local.sub_rules_data : "${rule.sub_policy_name}::${rule.rule.name}" => rule }

  sub_policy_id = cato_if_sub_policy.sub_policies[each.value.sub_policy_name].id

  at = {
    position = "LAST_IN_POLICY"
  }

  rule = local.rule_bodies[each.value.rule.name]
}
