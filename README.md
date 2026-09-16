## Inventory Manager

Allows moderators to view and modify other players' inventories **in real time**, with snapshots to undo changes and a log.

### Privileges

`inv_manager` View and modify inventories, empty, take, save, and restore snapshots
`inv_viewer` View inventories, snapshots, and the log only (read-only)

### Commands

`/inv` List of connected players
`/inv <player> [section]`
`/invm <player>` Main inventory
`/invc <player>` Crafting grid
`/invb <player> [1-4]` Unified Inventory bags
`/invsave <player>` Save a snapshot
`/invsnapshots <player>` List snapshots
`/invrestore <player> <n>` Restores a snapshot
`/invlog <player> [number]` Last changes made


### Configuración

```
inv_manager.sync_interval = 0.1
inv_manager.highlight_time = 3
inv_manager.allow_self = false
inv_manager.protected_privs = server
inv_manager.max_snapshots = 10
inv_manager.snapshot_interval = 600
inv_manager.snapshot_on_death = true
inv_manager.snapshot_on_leave = true
inv_manager.max_log_entries = 200
```

## Licencia

* MIT License (MIT) para el código.
* Attribution 4.0 International (CC BY 4.0) para las texturas.