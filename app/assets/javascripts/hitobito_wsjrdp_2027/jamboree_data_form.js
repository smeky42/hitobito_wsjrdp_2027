//  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
//
//  This file is part of hitobito_wsjrdp_2027 and licensed under the
//  Affero General Public License version 3 or later. See the COPYING
//  file at the top-level directory or at
//  https://github.com/smeky42/hitobito_wsjrdp_2027

// The Zusatzdaten form (person/jamboree_data/edit): a block marked
// data-jamboree-dependent-on="<checkbox id>" shows only while that box is
// ticked; hidden, its fields are disabled, so they are not sent. And it
// writes out the language level chosen with a numbered button.
(function () {
  const FORM = 'form[data-jamboree-data-form="true"]'

  function syncDependent(wrapper) {
    const dependency = document.getElementById(wrapper.getAttribute("data-jamboree-dependent-on"))
    const visible = !!(dependency && dependency.checked)
    wrapper.hidden = !visible
    wrapper.querySelectorAll("input, select, textarea").forEach(function (field) {
      field.disabled = !visible
    })
  }

  function syncForm(form) {
    form.querySelectorAll("[data-jamboree-dependent-on]").forEach(syncDependent)
  }

  function syncAll() {
    document.querySelectorAll(FORM).forEach(syncForm)
  }

  // The level buttons show numbers; the text beside them names the chosen
  // level.
  function syncLevelValue(radio) {
    const group = radio.closest(".wsjrdp-level-group")
    const value = group && group.parentElement.querySelector(".wsjrdp-level-value")
    const label = radio.form.querySelector('label[for="' + radio.id + '"]')
    if (value && label && radio.checked) value.textContent = label.getAttribute("data-level-label")
  }

  function onChange(event) {
    const form = event.target && event.target.form
    if (!form || !form.matches(FORM)) return
    syncForm(form)
    if (event.target.matches('.wsjrdp-level-group input[type="radio"]')) syncLevelValue(event.target)
  }

  // The listeners once per page life; the script runs again on every Turbo
  // visit to the form.
  if (!window.wsjrdpJamboreeDataFormBound) {
    window.wsjrdpJamboreeDataFormBound = true
    document.addEventListener("change", onChange)
    document.addEventListener("input", onChange)
    document.addEventListener("turbo:load", syncAll)
  }
  syncAll()
})()
