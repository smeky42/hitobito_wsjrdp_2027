
// import { Turbo } from "@hotwired/turbo-rails"

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

// Reload every turbo frame the stream's `targets` selector matches, e.g. the
// already loaded detail frames of a record after a change in its row
// (Fin::MossBookingsController#respond_after_subject_link). A frame reloads
// its own src, so the detail stays its own request to its own controller.
Turbo.StreamActions.reload_frames = function() {
    this.targetElements.forEach((frame) => {
        if (typeof frame.reload === "function") frame.reload()
    })
}

// Reload the whole page and come back to the same scroll position: the
// position goes where the expandable tables' scroll keeper restores it from on
// load (shared/wsjrdp/_expandable_table_js); open rows travel in the URL. For a
// change whose page a morph cannot follow, e.g. a list whose rows move
// (Person::FeeReductionController#leave_form from the Reduktionen list).
Turbo.StreamActions.reload_keep_scroll = function() {
    try { sessionStorage.setItem("wsjrdp.exptbl.scroll", String(window.scrollY || 0)) } catch (e) {}
    window.location.reload()
}
