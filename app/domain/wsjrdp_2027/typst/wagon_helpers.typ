// Helpers the wagon's own templates share. wsjrdp2027.typ is kept verbatim in
// step with the scripts repository, so nothing of ours goes in there.

// Text somebody typed, placed as text and nothing else: it is never evaluated
// as markup. A blank line starts a paragraph, a single newline is a line
// break, and every piece is placed as a plain string.
#let plain_text(source) = {
    let blocks = source.split("\n\n").filter(block => block.trim() != "")
    for (index, block) in blocks.enumerate() {
        if index > 0 { parbreak() }
        let lines = block.split("\n")
        for (line_index, line) in lines.enumerate() {
            if line_index > 0 { linebreak() }
            line
        }
    }
}
