locals {
  ifw_rules_json         = jsondecode(file("${var.ifw_rules_json_file_path}"))
  ifw_rules_data         = local.ifw_rules_json.data.policy.internetFirewall.policy.rules
  sections_data_unsorted = local.ifw_rules_json.data.policy.internetFirewall.policy.sections
  # Create a map with section_index as key to sort sections correctly
  sections_by_index = {
    for section in local.sections_data_unsorted :
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
  # Convert rules to map for provider schema compatibility
  rules_data = {
    for rule in local.ifw_rules_json.data.policy.internetFirewall.policy.rules_in_sections :
    rule.rule_name => rule
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
  for_each   = { for rule in local.ifw_rules_data : rule.rule.name => rule }

  at = {
    position = "LAST_IN_POLICY" // adding last to reorder in cato_bulk_if_move_rule
  }

  rule = merge(
    {
      name    = each.value.rule.name
      enabled = each.value.rule.enabled
      action  = each.value.rule.action
      # Always include tracking block with defaults
      tracking = {
        alert = merge(
          {
            enabled   = try(each.value.rule.tracking.alert.enabled, false)
            frequency = try(each.value.rule.tracking.alert.frequency, "IMMEDIATE")
          },
          # Only include mailing_list if it exists and is not empty
          try(length(each.value.rule.tracking.alert.mailingList), 0) > 0 ? {
            mailing_list = [for ml in each.value.rule.tracking.alert.mailingList : can(ml.name) ? { name = ml.name } : { id = ml.id }]
          } : {},
          # Only include subscription_group if it exists and is not empty
          try(length(each.value.rule.tracking.alert.subscriptionGroup), 0) > 0 ? {
            subscription_group = [for sg in each.value.rule.tracking.alert.subscriptionGroup : can(sg.name) ? { name = sg.name } : { id = sg.id }]
          } : {},
          # Only include webhook if it exists and is not empty
          try(length(each.value.rule.tracking.alert.webhook), 0) > 0 ? {
            webhook = [for wh in each.value.rule.tracking.alert.webhook : can(wh.name) ? { name = wh.name } : { id = wh.id }]
          } : {}
        )
        event = {
          enabled = try(each.value.rule.tracking.event.enabled, true)
        }
      }
    },

    # Only include description if it's not empty
    each.value.rule.description != "" ? {
      description = each.value.rule.description
    } : {},

    # Only include connection_origin if it exists
    try(each.value.rule.connectionOrigin, null) != null ? {
      connection_origin = each.value.rule.connectionOrigin
    } : {},

    # Only include device_os if it exists and is not empty
    try(length(each.value.rule.deviceOS), 0) > 0 ? {
      device_os = each.value.rule.deviceOS
    } : {},

    # Only include country if it exists and is not empty
    try(length(each.value.rule.country), 0) > 0 ? {
      country = [for country in each.value.rule.country : can(country.name) ? { name = country.name } : { id = country.id }]
    } : {},

    # Only include device if it exists and is not empty
    try(length(each.value.rule.device), 0) > 0 ? {
      device = [for device in each.value.rule.device : can(device.name) ? { name = device.name } : { id = device.id }]
    } : {},

    # Dynamic source block - include if source exists (even if empty)
    try(each.value.rule.source, null) != null ? {
      source = {
        for k, v in {
          ip          = try(length(each.value.rule.source.ip), 0) > 0 ? each.value.rule.source.ip : null
          host        = try(length(each.value.rule.source.host), 0) > 0 ? [for host in each.value.rule.source.host : can(host.name) ? { name = host.name } : { id = host.id }] : null
          site        = try(length(each.value.rule.source.site), 0) > 0 ? [for site in each.value.rule.source.site : can(site.name) ? { name = site.name } : { id = site.id }] : null
          users_group = try(length(each.value.rule.source.usersGroup), 0) > 0 ? [for group in each.value.rule.source.usersGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
          subnet      = try(length(each.value.rule.source.subnet), 0) > 0 ? [for subnet in each.value.rule.source.subnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
          ip_range = try(length(each.value.rule.source.ipRange), 0) > 0 ? [for range in each.value.rule.source.ipRange : {
            from = range.from
            to   = range.to
          }] : null
          network_interface   = try(length(each.value.rule.source.networkInterface), 0) > 0 ? [for ni in each.value.rule.source.networkInterface : can(ni.name) ? { name = ni.name } : { id = ni.id }] : null
          floating_subnet     = try(length(each.value.rule.source.floatingSubnet), 0) > 0 ? [for subnet in each.value.rule.source.floatingSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
          site_network_subnet = try(length(each.value.rule.source.siteNetworkSubnet), 0) > 0 ? [for subnet in each.value.rule.source.siteNetworkSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
          system_group        = try(length(each.value.rule.source.systemGroup), 0) > 0 ? [for group in each.value.rule.source.systemGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
          group               = try(length(each.value.rule.source.group), 0) > 0 ? [for group in each.value.rule.source.group : can(group.name) ? { name = group.name } : { id = group.id }] : null
          user                = try(length(each.value.rule.source.user), 0) > 0 ? [for user in each.value.rule.source.user : can(user.name) ? { name = user.name } : { id = user.id }] : null
        } : k => v if v != null
      }
    } : {},

    # Dynamic destination block - always include destination even if empty
    {
      destination = {
        for k, v in {
          app_category             = try(length(each.value.rule.destination.appCategory), 0) > 0 ? [for cat in each.value.rule.destination.appCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null
          application              = try(length(each.value.rule.destination.application), 0) > 0 ? [for app in each.value.rule.destination.application : can(app.name) ? { name = app.name } : { id = app.id }] : null
          custom_app               = try(length(each.value.rule.destination.customApp), 0) > 0 ? [for app in each.value.rule.destination.customApp : can(app.name) ? { name = app.name } : { id = app.id }] : null
          custom_category          = try(length(each.value.rule.destination.customCategory), 0) > 0 ? [for cat in each.value.rule.destination.customCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null
          sanctioned_apps_category = try(length(each.value.rule.destination.sanctionedAppsCategory), 0) > 0 ? [for cat in each.value.rule.destination.sanctionedAppsCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null
          domain                   = try(length(each.value.rule.destination.domain), 0) > 0 ? each.value.rule.destination.domain : null
          fqdn                     = try(length(each.value.rule.destination.fqdn), 0) > 0 ? each.value.rule.destination.fqdn : null
          ip                       = try(length(each.value.rule.destination.ip), 0) > 0 ? each.value.rule.destination.ip : null
          ip_range = try(length(each.value.rule.destination.ipRange), 0) > 0 ? [for range in each.value.rule.destination.ipRange : {
            from = range.from
            to   = range.to
          }] : null
          country    = try(length(each.value.rule.destination.country), 0) > 0 ? [for country in each.value.rule.destination.country : can(country.name) ? { name = country.name } : { id = country.id }] : null
          remote_asn = try(length(each.value.rule.destination.remoteAsn), 0) > 0 ? each.value.rule.destination.remoteAsn : null
        } : k => v if v != null
      }
    },

    # Dynamic service block - only if service has content
    try(length(each.value.rule.service.standard), 0) > 0 || try(length(each.value.rule.service.custom), 0) > 0 ? {
      service = {
        for k, v in {
          standard = try(length(each.value.rule.service.standard), 0) > 0 ? [for svc in each.value.rule.service.standard : can(svc.name) ? { name = svc.name } : { id = svc.id }] : null

          custom = try(length(each.value.rule.service.custom), 0) > 0 ? [for svc in each.value.rule.service.custom : merge(
            {
              protocol = svc.protocol
            },
            try(svc.port, null) != null ? {
              port = [for p in svc.port : tostring(p)]
            } : {},
            try(svc.portRange, null) != null ? {
              port_range = {
                from = tostring(svc.portRange.from)
                to   = tostring(svc.portRange.to)
              }
            } : {}
          )] : null
        } : k => v if v != null
      }
    } : {},

    # Dynamic schedule block - only if custom schedules exist
    try(each.value.rule.schedule.customTimeframePolicySchedule, null) != null ||
    try(each.value.rule.schedule.customRecurringPolicySchedule, null) != null ||
    try(each.value.rule.schedule.activeOn, "ALWAYS") != "ALWAYS" ? {
      schedule = {
        for k, v in {
          active_on        = try(each.value.rule.schedule.activeOn, "ALWAYS")
          custom_timeframe = try(each.value.rule.schedule.customTimeframePolicySchedule, null)
          custom_recurring = try(each.value.rule.schedule.customRecurringPolicySchedule, null)
        } : k => v if v != null && (k != "active_on" || v != "ALWAYS")
      }
    } : {},

    # Dynamic exceptions block - only if exceptions exist
    try(length(each.value.rule.exceptions), 0) > 0 ? {
      exceptions = [
        for exception in each.value.rule.exceptions : merge(
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
                subnet              = try(length(exception.source.subnet), 0) > 0 ? [for subnet in exception.source.subnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
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

resource "cato_bulk_if_move_rule" "all_if_rules" {
  depends_on                = [cato_if_section.sections, cato_if_rule.rules]
  rule_data                 = local.rules_data
  section_data              = local.sections_data
  section_to_start_after_id = var.section_to_start_after_id != null ? var.section_to_start_after_id : null
}
