import Caelestia.Services
import qs.components
import qs.services

PerfStat {
    icon: "memory_alt"
    accent: Colours.palette.m3primary
    value: Memory.percentage
    valueText: Memory.total > 0 ? Units.formatKibUsage(Memory.used,Memory.total) : "..."

    ServiceRef {
        service: Memory
    }
}
