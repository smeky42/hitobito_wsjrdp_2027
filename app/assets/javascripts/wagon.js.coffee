do ->
  initialized = false

  syncDependentField = (wrapper) ->
    dependencyId = wrapper.getAttribute('data-jamboree-dependent-on')
    dependency = document.getElementById(dependencyId)
    visible = !!(dependency && dependency.checked)
    wrapper.hidden = !visible
    wrapper.querySelectorAll('input, select, textarea').forEach (field) ->
      field.disabled = !visible

  syncForm = (form) ->
    form.querySelectorAll('[data-jamboree-dependent-on]').forEach syncDependentField

  bind = ->
    return if initialized
    initialized = true

    document.querySelectorAll('form[data-jamboree-data-form="true"]').forEach (form) ->
      syncForm(form)

    document.addEventListener 'change', (event) ->
      form = event.target?.form
      return unless form && form.matches('form[data-jamboree-data-form="true"]')
      syncForm(form)

    document.addEventListener 'input', (event) ->
      form = event.target?.form
      return unless form && form.matches('form[data-jamboree-data-form="true"]')
      syncForm(form)

  document.addEventListener 'DOMContentLoaded', bind
  document.addEventListener 'turbo:load', bind