// The searchable selects of the dialog "Hauptgruppe/Rolle wechseln"
// (person/primary_role/show): TomSelect (global from the core pack) with
// option groups and chips. A select opts in with data-wsjrdp-chip-select;
// each option carries its number (data-number, shown light before the name,
// searched too), its chips (shown on the right) as data-chips='["..."]'
// and its full name (searched too, and shown small right after the short
// one) as data-full -- TomSelect takes an
// option's data attributes as its fields. An empty choice shows the select's
// placeholder (data-placeholder). TomSelect keeps the select and fires its
// change event, so the dialog's autosubmit still sees every choice.
//
// A chosen entry shows in the box in bold, with its heading (data-heading)
// small after it; the box is tinted while something is chosen. A select
// with data-wsjrdp-clearable gets a small "x" on the right that empties it
// and opens the list again once the dialog came back from the server.
//
// The search term is marked in the short and the full name only, not in the
// chips: TomSelect's own marking (which runs over the whole entry) is off,
// and the entries mark it themselves.
//
// The open list never reaches past the bottom of the window: its height is
// cut to the room left below the select (at least a few lines), so that it
// stays usable on a small screen.
//
// The dialog calls WsjrdpChipSelect.activate(root) on every render of its
// turbo frame.
//
// A turbo frame with data-wsjrdp-keep-scroll="<selector>" keeps the scroll
// position of that element inside it (the dialog's scrolling .modal) across
// a new rendering, so that a change on a phone does not jump back to the top.
(function () {
  function chips(data, escape) {
    let list = []
    try { list = JSON.parse(data.chips || "[]") } catch (e) {}
    if (!list.length) return ""
    const pills = list
      .map((chip) => `<span class="badge rounded-pill bg-light text-dark border fw-normal">${escape(chip)}</span>`)
      .join(" ")
    return `<span class="ms-auto text-nowrap ps-2">${pills}</span>`
  }

  // The text, escaped, with every word of the search term marked as
  // TomSelect marks it (span.highlight), ignoring case.
  function marked(text, query, escape) {
    const words = (query || "").trim().split(/\s+/).filter(Boolean)
      .map((word) => word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
    if (!words.length) return escape(text)
    const pattern = new RegExp(`(${words.join("|")})`, "gi")
    return text.split(pattern)
      .map((part, i) => (i % 2 ? `<span class="highlight">${escape(part)}</span>` : escape(part)))
      .join("")
  }

  // The number, small and light. In the list it stands right-aligned in a
  // column just as wide as the longest number (--wsjrdp-number-width, set
  // per select), so that numbers and names line up without wasting room;
  // in the box it stands just before the name.
  function number(data, query, escape, column) {
    if (!data.number) return ""
    const style = column
      ? ` style="min-width: var(--wsjrdp-number-width, 2ch); text-align: right; font-variant-numeric: tabular-nums;"` : ""
    return `<span class="small text-muted fw-light me-2"${style}>${marked(data.number, query, escape)}</span>`
  }

  // An entry of the list: the whole width, the chips pushed to the right.
  function option(data, escape) {
    const query = this.inputValue()
    const full = data.full
      ? `<span class="small text-muted fw-light ms-2">${marked(data.full, query, escape)}</span>` : ""
    return `<div class="d-flex align-items-baseline w-100">${number(data, query, escape, true)}<span>${marked(data.text, query, escape)}</span>${full}${chips(data, escape)}</div>`
  }

  // The chosen entry in the box: only as wide as its text, so that the
  // search input stays on the same line.
  function item(data, escape) {
    const heading = data.heading ? `<span class="small text-muted ms-2 text-nowrap">${escape(data.heading)}</span>` : ""
    return `<div class="d-inline-flex align-items-baseline">${number(data, "", escape, false)}<span class="fw-semibold wsjrdp-item-name" title="${escape(data.text)}">${escape(data.text)}</span>${heading}${chips(data, escape)}</div>`
  }

  // Emptied with the "x": the dialog reloads (autosubmit), so the wish to
  // see the list travels to the select's next instance by its id.
  const OPEN_AFTER_RELOAD = "wsjrdp.chipSelect.openAfterReload"

  function rememberOpen(select) {
    try { sessionStorage.setItem(OPEN_AFTER_RELOAD, select.id) } catch (e) {}
  }

  function openIfRemembered(tom, select) {
    let id = null
    try { id = sessionStorage.getItem(OPEN_AFTER_RELOAD) } catch (e) {}
    if (id !== select.id) return
    try { sessionStorage.removeItem(OPEN_AFTER_RELOAD) } catch (e) {}
    tom.focus()
    tom.open()
  }

  function markChosen(tom) {
    tom.wrapper.classList.toggle("wsjrdp-chosen", tom.getValue() !== "")
  }

  const MARGIN = 12
  const MIN_HEIGHT = 120

  function fitToWindow(tom) {
    const content = tom.dropdown_content
    const top = content.getBoundingClientRect().top
    const room = window.innerHeight - top - MARGIN
    content.style.maxHeight = `${Math.max(room, MIN_HEIGHT)}px`
  }

  window.WsjrdpChipSelect = {
    activate(root) {
      (root || document).querySelectorAll("select[data-wsjrdp-chip-select]").forEach((select) => {
        if (select.tomselect) return
        const clearable = select.dataset.wsjrdpClearable !== undefined
        const tom = new TomSelect(select, {
          plugins: clearable
            ? {clear_button: {title: select.dataset.wsjrdpClearable || "Auswahl löschen",
              html: (data) => `<div class="${data.className} wsjrdp-clear" title="${data.title}" aria-label="${data.title}">&times;</div>`}}
            : [],
          create: false,
          maxOptions: null,
          searchField: ["text", "full", "number"],
          highlight: false,
          placeholder: select.dataset.placeholder,
          render: {
            option: option,
            item: item,
            no_results: () => `<div class="no-results">Keine Treffer</div>`
          }
        })
        const longest = Math.max(0, ...Array.from(select.options, (o) => (o.dataset.number || "").length))
        tom.dropdown.style.setProperty("--wsjrdp-number-width", `${longest}ch`)
        markChosen(tom)
        tom.on("change", () => markChosen(tom))
        if (clearable) tom.on("clear", () => rememberOpen(select))
        tom.on("dropdown_open", () => fitToWindow(tom))
        // TomSelect keeps rendered entries; they depend on the search term.
        tom.on("type", () => {
          tom.clearCache("option")
          tom.refreshOptions(false)
          fitToWindow(tom)
        })
        if (clearable) openIfRemembered(tom, select)
      })
    }
  }
})()

;(function () {
  document.addEventListener("turbo:before-frame-render", (event) => {
    const frame = event.target
    const selector = frame.dataset && frame.dataset.wsjrdpKeepScroll
    if (!selector) return
    const scroller = frame.querySelector(selector)
    frame.wsjrdpScrollTop = scroller ? scroller.scrollTop : 0
  })

  document.addEventListener("turbo:frame-render", (event) => {
    const frame = event.target
    const selector = frame.dataset && frame.dataset.wsjrdpKeepScroll
    if (!selector || !frame.wsjrdpScrollTop) return
    const scroller = frame.querySelector(selector)
    if (scroller) scroller.scrollTop = frame.wsjrdpScrollTop
  })
})()

