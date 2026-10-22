import Caelestia.Services
import qs.components
import qs.services

PerfStat {
    icon: "memory_alt"
    accent: Colours.palette.m3primary
    value: Memory.percentage
    maxText: "00.0 GiB"
    valueText: {
        if (Memory.total <= 0) return "..."
            let val = Memory.used
            let unit = "KiB"
            if (val >= 1024) { val /= 1024; unit = "MiB" }
            if (val >= 1024) { val /= 1024; unit = "GiB" }
            return val.toFixed(1) + " " + unit
    }

    ServiceRef {
        service: Memory
    }
}
