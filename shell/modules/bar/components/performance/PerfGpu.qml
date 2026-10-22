import Caelestia.Services
import qs.components
import qs.services

PerfStat {
    icon: "desktop_windows"
    accent: Colours.palette.m3secondary
    maxText: "100%/100°C"
    value: Gpu.percentage
    valueText: {
        const usage = isNaN(Gpu.percentage)
        ? "..."
        : `${Math.round(Gpu.percentage * 100)}%`

        const temp = isNaN(Gpu.temperature) || Gpu.temperature <= 0
        ? "..."
        : `${Math.round(Gpu.temperature)}°C`

        return `${usage}/${temp}`
    }

    ServiceRef {
        service: Gpu
    }
}
