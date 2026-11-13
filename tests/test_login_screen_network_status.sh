#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME="$REPO_ROOT/src/sddm/themes/full"
NET="$THEME/components/NetworkStatus.qml"

# The tile under the clock on the login screen shows the network instead of a quote. Nobody is
# logged in, so it reads the kernel's tables (/proc/net/route, wireless, dev). The parsing
# functions of the component are run for real in node; the QML around them is checked as text.

js_call() {
    # js_call <function> <js expression using the function>
    local name="$1" expr="$2" body
    body="$(awk -v n="function $name(" 'index($0, n) { on = 1 } on { print } on && /^    }$/ { exit }' "$NET")"
    node -e "
        $body
        const r = $expr;
        console.log(JSON.stringify(r));
    "
}

ROUTE=$'Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n'
ROUTE+=$'wlp2s0\t00000000\t0102A8C0\t0003\t0\t0\t600\t00000000\t0\t0\t0\n'
ROUTE+=$'enp3s0\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0\n'
ROUTE+=$'enp3s0\t0001A8C0\t00000000\t0001\t0\t0\t100\t00FFFFFF\t0\t0\t0\n'

route_expr() { printf '%s' "defaultInterface(\`$1\`)"; }

test_the_default_route_with_the_lowest_metric_names_the_interface() {
    assert_eq '"enp3s0"' "$(js_call defaultInterface "$(route_expr "$ROUTE")")" "wired (100) beats Wi-Fi (600)"
}

test_no_default_route_means_not_connected() {
    local only_local=$'Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\nenp3s0\t0001A8C0\t00000000\t0001\t0\t0\t100\t00FFFFFF\t0\t0\t0\n'

    assert_eq '""' "$(js_call defaultInterface "$(route_expr "$only_local")")" "a local route is not a way out"
    assert_eq '""' "$(js_call defaultInterface "$(route_expr "")")" "an empty table"
}

test_only_a_route_with_an_empty_mask_is_the_default_route() {
    local narrow=$'Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\nenp3s0\t00000000\t0101A8C0\t0003\t0\t0\t100\t000000FF\t0\t0\t0\n'

    assert_eq '""' "$(js_call defaultInterface "$(route_expr "$narrow")")" "0.0.0.0 with a mask is a small network, not the way out"
}

test_a_default_route_that_is_down_does_not_count() {
    local down=$'Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\nwlp2s0\t00000000\t0102A8C0\t0002\t0\t0\t600\t00000000\t0\t0\t0\n'

    assert_eq '""' "$(js_call defaultInterface "$(route_expr "$down")")" "the UP flag is bit 1"
}

WIRELESS=$'Inter-| sta-|   Quality        |   Discarded packets               | Missed | WE\n face | tus | link level noise |  nwid  crypt   frag  retry   misc | beacon | 22\n wlp2s0: 0000   56.  -54.  -256        0      0      0      0      0        0\n'

test_wifi_quality_is_the_link_value_out_of_70_as_percent() {
    assert_eq "80" "$(js_call wirelessQuality "wirelessQuality(\`$WIRELESS\`, 'wlp2s0')")" "56 of 70"
}

test_an_unreadable_quality_is_zero_percent_and_still_wireless() {
    local broken=$'h1\nh2\n wlp2s0: 0000   .  -54.  -256\n'

    assert_eq "0" "$(js_call wirelessQuality "wirelessQuality(\`$broken\`, 'wlp2s0')")" "listed, so wireless; no number, so 0"
}

test_an_interface_that_is_not_in_the_wireless_table_is_wired() {
    assert_eq "-1" "$(js_call wirelessQuality "wirelessQuality(\`$WIRELESS\`, 'enp3s0')")" "not wireless"
    assert_eq "-1" "$(js_call wirelessQuality "wirelessQuality('', 'wlp2s0')")" "no table"
}

DEV=$'Inter-|   Receive                                                |  Transmit\n face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n    lo:  100 1 0 0 0 0 0 0   100 1 0 0 0 0 0 0\nenp3s0:123456789 900 0 0 0 0 0 0 555000 700 0 0 0 0 0 0\n'

test_byte_counters_are_read_for_the_named_interface_only() {
    assert_eq '{"rx":123456789,"tx":555000}' "$(js_call byteCounters "byteCounters(\`$DEV\`, 'enp3s0')")" "received and sent bytes, also when the colon touches the number"
    assert_eq 'null' "$(js_call byteCounters "byteCounters(\`$DEV\`, 'wlp2s0')")" "an interface that is not listed"
}

test_rates_are_shown_in_a_readable_unit() {
    assert_eq '"0 B/s"' "$(js_call formatRate 'formatRate(0)')" "idle"
    assert_eq '"512 B/s"' "$(js_call formatRate 'formatRate(512)')" "bytes"
    assert_eq '"1000 B/s"' "$(js_call formatRate 'formatRate(1000)')" "the next unit starts at 1024"
    assert_eq '"1.5 KB/s"' "$(js_call formatRate 'formatRate(1536)')" "one decimal below 100"
    assert_eq '"250 KB/s"' "$(js_call formatRate 'formatRate(256000)')" "none above"
    assert_eq '"2.0 MB/s"' "$(js_call formatRate 'formatRate(2 * 1024 * 1024)')" "megabytes"
    assert_eq '"0 B/s"' "$(js_call formatRate 'formatRate(-5)')" "a counter that went back (an interface reset) is not a negative speed"
}

test_the_login_screen_shows_the_network_tile_where_the_quote_was() {
    local tile
    tile="$(awk '/id: topRightRect/ { on = 1 } on { print } on && /^                }$/ { exit }' "$THEME/Main.qml")"

    assert_contains "$tile" 'NetworkStatus {' "the tile holds the network status"
    assert_contains "$tile" 'active: !root.firstInput' "it polls only while the card is shown"
    assert_not_contains "$tile" 'RandomQuote' "the quote is gone from this tile"
}

test_polling_follows_the_active_switch_and_samples_at_once() {
    local timer
    timer="$(awk '/^    Timer \{/ { on = 1 } on { print } on && /^    }$/ { exit }' "$NET")"

    assert_contains "$timer" 'running: root.active' "stopped while the card is hidden"
    assert_contains "$timer" 'triggeredOnStart: true' "no two second wait for the first answer"
}

run_tests
