import Caelestia.Services
import qs.components
import qs.services

PerfStat {
    icon: "memory"
    accent: Colours.palette.m3primary
    maxText: "100%/100°C"
    value: Cpu.percentage
    valueText: {
        const usage = isNaN(Cpu.percentage)
        ? "..."
        : `${Math.round(Cpu.percentage * 100)}%`

        const temp = isNaN(Cpu.temperature) || Cpu.temperature <= 0
        ? "..."
        : `${Math.round(Cpu.temperature)}°C`

        return `${usage}/${temp}`
    }

    ServiceRef {
        service: Cpu
    }
}
