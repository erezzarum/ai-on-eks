# =============================================================================
# Network interface definitions per instance type and use case.
#
# Each entry is a list of objects with:
#   - network_card_index: The physical network card (NCI)
#   - device_index:       The logical device slot on that card (DI)
#   - interface_type:     "interface" (ENA, gets IP) or "efa-only" (EFA, no IP)
#
# Use Case 1 — IP Optimized:
#   Primary network interface as ENA, EFA-only for the rest of network cards.
#
# Use Case 2 — Bandwidth Optimized:
#   Primary network interface as ENA, combination of EFA-only and ENA
#   interfaces to maximize IP and EFA network bandwidth.
#
# Sorted by (network_card_index, device_index).
# =============================================================================

locals {

  # ---------------------------------------------------------------------------
  # p5.48xlarge — 32 network cards (NCI 0-31), 2 device indices (DI 0-1)
  # ---------------------------------------------------------------------------

  # IP Optimized: 1 IP — ENA on NCI0/DI0, EFA-only on NCI0-31/DI1
  p5_48xlarge_use_case_1 = concat(
    [{ network_card_index = 0, device_index = 0, interface_type = "interface" }],
    [for nci in range(0, 32) : { network_card_index = nci, device_index = 1, interface_type = "efa-only" }]
  )

  # Bandwidth Optimized: 8 IPs — ENA on NCI0/DI0 + NCI4,8,12,16,20,24,28/DI1, EFA-only on remaining
  p5_48xlarge_use_case_2 = concat(
    [{ network_card_index = 0, device_index = 0, interface_type = "interface" }],
    [{ network_card_index = 0, device_index = 1, interface_type = "efa-only" }],
    [for nci in range(1, 32) : { network_card_index = nci, device_index = 0, interface_type = "efa-only" }],
    [for nci in [4, 8, 12, 16, 20, 24, 28] : { network_card_index = nci, device_index = 1, interface_type = "interface" }]
  )

  # ---------------------------------------------------------------------------
  # p5e.48xlarge — 32 network cards (NCI 0-31), 2 device indices (DI 0-1)
  # Same topology as p5.48xlarge
  # ---------------------------------------------------------------------------

  # IP Optimized: same as p5.48xlarge
  p5e_48xlarge_use_case_1 = local.p5_48xlarge_use_case_1

  # Bandwidth Optimized: same as p5.48xlarge
  p5e_48xlarge_use_case_2 = local.p5_48xlarge_use_case_2

  # ---------------------------------------------------------------------------
  # p5en.48xlarge — 16 network cards (NCI 0-15), 3 device indices (DI 0-2)
  # ---------------------------------------------------------------------------

  # IP Optimized: 1 IP — ENA on NCI0/DI0, EFA-only on NCI0-15/DI1
  p5en_48xlarge_use_case_1 = concat(
    [{ network_card_index = 0, device_index = 0, interface_type = "interface" }],
    [for nci in range(0, 16) : { network_card_index = nci, device_index = 1, interface_type = "efa-only" }]
  )

  # Bandwidth Optimized: 8 IPs — ENA on NCI0/DI0 + NCI2,4,6,8,10,12,14/DI1, EFA-only on NCI0-15/DI2
  p5en_48xlarge_use_case_2 = concat(
    [{ network_card_index = 0, device_index = 0, interface_type = "interface" }],
    [for nci in [2, 4, 6, 8, 10, 12, 14] : { network_card_index = nci, device_index = 1, interface_type = "interface" }],
    [for nci in range(0, 16) : { network_card_index = nci, device_index = 2, interface_type = "efa-only" }]
  )

  # ---------------------------------------------------------------------------
  # p6-b200.48xlarge — 8 network cards (NCI 0-7), 3 device indices (DI 0-2)
  # ---------------------------------------------------------------------------

  # IP Optimized: 1 IP — ENA on NCI0/DI0, EFA-only on NCI0-7/DI1
  p6_b200_48xlarge_use_case_1 = concat(
    [{ network_card_index = 0, device_index = 0, interface_type = "interface" }],
    [for nci in range(0, 8) : { network_card_index = nci, device_index = 1, interface_type = "efa-only" }]
  )

  # Bandwidth Optimized: 8 IPs — ENA on NCI0/DI0 + NCI1-7/DI1, EFA-only on NCI0-7/DI2
  p6_b200_48xlarge_use_case_2 = concat(
    [{ network_card_index = 0, device_index = 0, interface_type = "interface" }],
    [for nci in range(1, 8) : { network_card_index = nci, device_index = 1, interface_type = "interface" }],
    [for nci in range(0, 8) : { network_card_index = nci, device_index = 2, interface_type = "efa-only" }]
  )

  # ---------------------------------------------------------------------------
  # p6-b300.48xlarge — 17 network cards (NCI 0-16), 3 device indices (DI 0-2)
  # ---------------------------------------------------------------------------

  # IP Optimized: 1 IP — ENA on NCI0/DI0, EFA-only on NCI1-16/DI1
  p6_b300_48xlarge_use_case_1 = concat(
    [{ network_card_index = 0, device_index = 0, interface_type = "interface" }],
    [for nci in range(1, 17) : { network_card_index = nci, device_index = 1, interface_type = "efa-only" }]
  )

  # Bandwidth Optimized: 17 IPs — ENA on NCI0/DI0 + NCI1-16/DI1, EFA-only on NCI1-16/DI0
  p6_b300_48xlarge_use_case_2 = concat(
    [{ network_card_index = 0, device_index = 0, interface_type = "interface" }],
    [for nci in range(1, 17) : { network_card_index = nci, device_index = 1, interface_type = "interface" }],
    [for nci in range(1, 17) : { network_card_index = nci, device_index = 0, interface_type = "efa-only" }]
  )

  # ---------------------------------------------------------------------------
  # p6e-gb200.36xlarge — 17 network cards (NCI 0-16), 3 device indices (DI 0-2)
  # Only a subset of NCIs are used: EFA on NCI 1,5,9,13, ENA on NCI 0,2,6,10,14
  # ---------------------------------------------------------------------------

  # IP Optimized: 1 IP — ENA on NCI0/DI0, EFA-only on NCI1,5,9,13/DI1
  p6e_gb200_36xlarge_use_case_1 = concat(
    [{ network_card_index = 0, device_index = 0, interface_type = "interface" }],
    [for nci in [1, 5, 9, 13] : { network_card_index = nci, device_index = 1, interface_type = "efa-only" }]
  )

  # Bandwidth Optimized: 5 IPs — ENA on NCI0/DI0 + NCI2,6,10,14/DI1, EFA-only on NCI1,5,9,13/DI2
  p6e_gb200_36xlarge_use_case_2 = concat(
    [{ network_card_index = 0, device_index = 0, interface_type = "interface" }],
    [for nci in [2, 6, 10, 14] : { network_card_index = nci, device_index = 1, interface_type = "interface" }],
    [for nci in [1, 5, 9, 13] : { network_card_index = nci, device_index = 2, interface_type = "efa-only" }]
  )

  # ---------------------------------------------------------------------------
  # Lookup map: instance_type -> use_case -> specs
  # ---------------------------------------------------------------------------
  instance_type_configs = {
    "p5.48xlarge" = {
      1 = local.p5_48xlarge_use_case_1
      2 = local.p5_48xlarge_use_case_2
    }
    "p5e.48xlarge" = {
      1 = local.p5e_48xlarge_use_case_1
      2 = local.p5e_48xlarge_use_case_2
    }
    "p5en.48xlarge" = {
      1 = local.p5en_48xlarge_use_case_1
      2 = local.p5en_48xlarge_use_case_2
    }
    "p6-b200.48xlarge" = {
      1 = local.p6_b200_48xlarge_use_case_1
      2 = local.p6_b200_48xlarge_use_case_2
    }
    "p6-b300.48xlarge" = {
      1 = local.p6_b300_48xlarge_use_case_1
      2 = local.p6_b300_48xlarge_use_case_2
    }
    "p6e-gb200.36xlarge" = {
      1 = local.p6e_gb200_36xlarge_use_case_1
      2 = local.p6e_gb200_36xlarge_use_case_2
    }
  }

  # Selected specs for the given instance type and use case
  raw_specs = local.instance_type_configs[var.instance_type][var.use_case]

  # Sort by network_card_index, then device_index (Terraform sort is lexicographic,
  # so we use a composite key for ordering)
  sorted_network_interfaces = [
    for spec in sort([
      for s in local.raw_specs : format("%04d-%04d|%d|%d|%s",
        s.network_card_index,
        s.device_index,
        s.network_card_index,
        s.device_index,
        s.interface_type
      )
      ]) : {
      network_card_index = tonumber(split("|", spec)[1])
      device_index       = tonumber(split("|", spec)[2])
      interface_type     = split("|", spec)[3]
    }
  ]
}
