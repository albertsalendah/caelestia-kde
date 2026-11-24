#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$REPO_ROOT/shell/services/WallhavenSearcher.qml"
TAB="$REPO_ROOT/shell/modules/dashboard/WallhavenTab.qml"

# The Wallhaven page used to show nothing until a word was typed. An empty search now browses (the API
# answers /search without q), the page loads the latest wallpapers when it opens, and dropdowns for the
# mode, the toplist period, the category and a topic start the search. The service's real functions run
# in node; the tab is read as text (no QML runtime here).

have_node() {
    command -v node >/dev/null 2>&1
}

# service_js <javascript>: the service's real buildUrl, searchParams, search and runSearch, with the
# annotations removed, run against a context that stands in for the singleton's properties.
service_js() {
    local code name
    code=""
    for name in buildUrl searchParams search runSearch; do
        code="$code
$(awk -v n="$name" '$0 ~ "^    function " n "\\(" { on = 1 } on { print } on && /^    }$/ { exit }' "$SERVICE" \
            | sed -E '/^    function /{s/\(([^)]*)\): [a-z]+ \{/(\1) {/; s/(\w+): (string|int|var|bool|real)/\1/g}')"
    done
    node -e "
        const Logger = { log() {} };
        const encode = encodeURIComponent;
        const ctx = {
            apiBase: 'https://wallhaven.cc/api/v1', apiKey: '', lastQuery: 'old', currentPage: 9, hasSearched: false,
            requestSerial: 0, results: [], lastPage: 1, lastSeed: '', sent: [], answers: [], completed: [],
            filters: { categories: '111', purity: '100', sorting: 'date_added', order: 'desc', topRange: '1M',
                       atleast: '', resolutions: '', ratios: '', colors: '' },
            Logger, Requests: { get(url, ok, fail) { ctx.sent.push(url); ctx.answers.push({ ok, fail }); } },
            searchComplete(results) { ctx.completed.push(results); },
            encodeURIComponent: encode
        };
        with (ctx) {
            $code
            ctx.buildUrl = buildUrl; ctx.searchParams = searchParams; ctx.search = search; ctx.runSearch = runSearch;
            ctx.runSearch = function (url) { runSearch.call(ctx, url); };
        }
        $1
    "
}

test_an_empty_search_browses_the_latest_wallpapers() {
    have_node || return 0
    local url
    url="$(service_js "ctx.search(''); console.log(ctx.sent[0]);")"
    assert_contains "$url" "sorting=date_added" "the default mode is the latest"
    assert_contains "$url" "page=1" "first page"
    assert_not_contains "$url" "q=" "no empty q parameter is sent"
    assert_not_contains "$url" "topRange" "no period outside the toplist"
    assert_eq "true|" "$(service_js "ctx.search(''); console.log(ctx.hasSearched + '|' + ctx.lastQuery);")" "it counts as a search, with an empty query"
}

test_the_toplist_sends_its_period_and_nothing_else_does() {
    have_node || return 0
    assert_contains "$(service_js "ctx.filters.sorting='toplist'; ctx.filters.topRange='1w'; ctx.search(''); console.log(ctx.sent[0]);")" "topRange=1w" "the toplist carries its period"
    assert_not_contains "$(service_js "ctx.filters.sorting='hot'; ctx.filters.topRange='1w'; ctx.search(''); console.log(ctx.sent[0]);")" "topRange" "hot does not"
}

test_a_word_and_a_category_are_sent_with_the_mode() {
    have_node || return 0
    local url
    url="$(service_js "ctx.filters.categories='010'; ctx.search('cars', 2); console.log(ctx.sent[0]);")"
    assert_contains "$url" "q=cars" "the word"
    assert_contains "$url" "categories=010" "the category"
    assert_contains "$url" "sorting=date_added" "the mode stays"
    assert_contains "$url" "page=2" "the page"
}

test_only_the_newest_answer_is_used() {
    have_node || return 0
    # Two searches start; the first one's answer arrives last and must be dropped.
    assert_eq "1|new" "$(service_js "
        ctx.search('a'); ctx.search('b');
        ctx.answers[1].ok(JSON.stringify({ data: ['new'], meta: { last_page: 1 } }));
        ctx.answers[0].ok(JSON.stringify({ data: ['old'], meta: { last_page: 1 } }));
        console.log(ctx.completed.length + '|' + ctx.completed[0][0]);
    ")" "one answer reaches the page, the newest"
    assert_eq "0" "$(service_js "ctx.search('a'); ctx.search('b'); ctx.answers[0].fail(); console.log(ctx.completed.length);")" "an old failure is ignored too"
}

test_load_more_works_without_a_typed_word() {
    local body
    body="$(awk '/function searchNextPage\(/ { on = 1 } on { print } on && /^    }$/ { exit }' "$SERVICE")"
    assert_contains "$body" 'currentPage < lastPage && hasSearched' "it needs a search to have run, not a word"
    assert_not_contains "$body" '&& lastQuery' "the word is not required"
}

test_the_page_loads_when_it_opens_and_the_buttons_need_no_word() {
    local tab
    tab="$(cat "$TAB")"
    assert_contains "$tab" 'Component.onCompleted: root.load()' "the first page loads on open"
    assert_contains "$tab" 'Keys.onReturnPressed: root.load()' "Enter searches or browses"
    assert_not_contains "$tab" 'if (root.searchQuery.trim())' "no button waits for a word"
    assert_not_contains "$tab" 'WallhavenSearcher.searchRandom(' "the arrow picks the random mode instead"
    assert_contains "$tab" 'WallhavenSearcher.setSorting("random")' "the arrow picks the random mode"
}

test_the_dropdowns_offer_the_modes_the_categories_and_the_topics() {
    local tab value
    tab="$(cat "$TAB")"
    for value in date_added toplist hot random relevance; do
        assert_contains "$tab" "value: \"$value\"" "mode $value"
    done
    for value in 1d 3d 1w 1M 3M 6M 1y; do
        assert_contains "$tab" "value: \"$value\"" "period $value"
    done
    for value in 111 100 010 001; do
        assert_contains "$tab" "value: \"$value\"" "category $value"
    done
    assert_contains "$tab" 'visible: WallhavenSearcher.filters.sorting === "toplist"' "the period shows only for the toplist"
    assert_contains "$tab" 'searchField.text = item.value;' "a topic goes into the search box"
    assert_contains "$tab" 'WallhavenSearcher.setFilter("categories", item.value);' "the category dropdown sets the filter"
    assert_contains "$tab" 'WallhavenSearcher.setFilter("topRange", item.value);' "the period dropdown sets the filter"
}

test_the_grid_columns_follow_the_width_and_leave_no_strip() {
    have_node || return 0
    local cols cw ch
    cols="$(sed -n 's/^ *readonly property int columns: //p' "$TAB")"
    cw="$(sed -n 's/^ *cellWidth: //p' "$TAB")"
    ch="$(sed -n 's/^ *cellHeight: //p' "$TAB")"
    assert_eq "1" "$(printf '%s\n' "$cols" | wc -l | tr -d ' ')" "one columns line in the tab"
    # The file's own three expressions, evaluated for a width.
    grid() {
        node -e "
            const at = width => { const columns = $cols; const cellWidth = $cw; const cellHeight = $ch; return { columns, cellWidth, cellHeight }; };
            const r = at($1);
            console.log(r.columns + ' ' + r.cellWidth + ' ' + r.cellHeight);
        "
    }
    assert_eq "6 211 160" "$(grid 1270)" "a wide page gets six wider cells"
    assert_eq "7 185 141" "$(grid 1300)" "and a seventh column once it fits"
    assert_eq "2 150 114" "$(grid 300)" "a narrow page keeps two columns"
    assert_eq "1 0 0" "$(grid 0)" "an unsized grid is one empty column, not a division by zero"
    assert_eq "ok" "$(node -e "
        let bad = 0;
        for (let width = 100; width <= 2600; width++) {
            const columns = $cols; const cellWidth = $cw;
            if (width - columns * cellWidth >= columns || cellWidth < 100 || cellWidth > 400) bad++;
        }
        console.log(bad === 0 ? 'ok' : 'bad ' + bad);
    ")" "at every width the leftover is under a pixel per column and the cells stay between 100 and 400 px"
}

test_the_grid_takes_the_height_the_rows_above_leave() {
    have_node || return 0
    local expr
    expr="$(sed -n 's/^ *Layout.preferredHeight: //p' "$TAB")"
    assert_eq "1" "$(printf '%s\n' "$expr" | wc -l | tr -d ' ')" "one preferred height in the tab"
    run_height() {
        node -e "
            const o = h => ({ height: h });
            const heroRow = o(60), searchRow = o(40), filterFlow = o(30), statusRow = o(20);
            const mainLayout = { spacing: 10 }, mainFlickable = o($1);
            console.log($expr);
        "
    }
    assert_eq "610" "$(run_height 800)" "the window height minus each row above and the four gaps"
    assert_eq "400" "$(run_height 500)" "a small window keeps 400 and scrolls"
    assert_contains "$(cat "$TAB")" 'id: statusRow' "the rows it subtracts have ids"
}

test_both_default_filter_sets_start_on_the_latest() {
    assert_eq "2" "$(grep -c '"sorting": "date_added"' "$SERVICE")" "the property and resetFilters agree"
    assert_eq "0" "$(grep -c '"sorting": "relevance"' "$SERVICE")" "no default is left on relevance"
}

run_tests
