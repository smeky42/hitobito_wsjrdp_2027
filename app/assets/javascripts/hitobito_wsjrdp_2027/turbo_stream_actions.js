
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
