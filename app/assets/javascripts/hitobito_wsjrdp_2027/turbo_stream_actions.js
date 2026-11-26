Turbo.StreamActions.redirect = function() {
    console.log("Turbo.StreamActions.redirect")
    const url = this.getAttribute("url")
    const frame = this.getAttribute("frame") || "_self"
    Turbo.visit(url, { frame: frame })
}

Turbo.StreamActions.redirect_top = function() {
    console.log("Turbo.StreamActions.redirect")
    const url = this.getAttribute("url")
    Turbo.visit(url, { frame: "_top" })
}

Turbo.StreamActions.location_reload = function() {
    console.log("Turbo.StreamActions.location_reload")
    window.location.reload()
}

Turbo.StreamActions.reload_frames = function() {
    this.targetElements.forEach((frame) => {
        if (typeof frame.reload === "function") frame.reload()
    })
}

// For a change a morph cannot follow, e.g. list rows that move.
Turbo.StreamActions.reload_keep_scroll = function() {
    try { sessionStorage.setItem("wsjrdp.exptbl.scroll", String(window.scrollY || 0)) } catch (e) {}
    window.location.reload()
}

// An open form survives a morphing refresh, except the one answering its own
// submit. A kept form then gets the event "wsjrdp:kept".
if (!window.wsjrdpKeepOnRefresh) {
    window.wsjrdpKeepOnRefresh = true
    const MARK = "[data-wsjrdp-keep-on-refresh]"
    const kept = []
    document.addEventListener("turbo:submit-start", (event) => {
        event.target.closest(MARK)?.setAttribute("data-wsjrdp-submitting", "")
    })
    document.addEventListener("turbo:submit-end", (event) => {
        const form = event.target.closest(MARK)
        if (!form) return
        if (!event.detail.success) form.removeAttribute("data-wsjrdp-submitting")
        // A save answered without a refresh must not close the form at a later one.
        else setTimeout(() => form.removeAttribute("data-wsjrdp-submitting"), 10000)
    })
    document.addEventListener("turbo:before-render", (event) => {
        if (event.detail.renderMethod !== "morph") return
        document.querySelectorAll(MARK).forEach((form) => {
            const isFrame = form.tagName === "TURBO-FRAME"
            if (form.hasAttribute("data-wsjrdp-submitting")) {
                form.removeAttribute("data-wsjrdp-submitting")
                // Turbo 8.0 reloads src when a morph drops "complete".
                if (isFrame) {
                    form.removeAttribute("src")
                    form.removeAttribute("complete")
                }
                return
            }
            if (isFrame && !form.hasAttribute("src")) return
            const holder = isFrame ? form : form.parentElement
            if (!holder?.id || holder.hasAttribute("data-turbo-permanent")) return
            holder.setAttribute("data-turbo-permanent", "")
            kept.push({holder, form})
        })
    })
    document.addEventListener("turbo:render", () => {
        kept.splice(0).forEach(({holder, form}) => {
            holder.removeAttribute("data-turbo-permanent")
            if (form.isConnected) form.dispatchEvent(new CustomEvent("wsjrdp:kept"))
        })
    })
}

// A morph leaves the focused element alone, so a clicked link or button
// would keep its old label.
if (!window.wsjrdpBlurOnMorph) {
    window.wsjrdpBlurOnMorph = true
    document.addEventListener("turbo:before-render", (event) => {
        if (event.detail.renderMethod !== "morph") return
        const active = document.activeElement
        if (active instanceof HTMLElement && active.matches("a, button, input[type=submit], input[type=button]")) active.blur()
    })
}
