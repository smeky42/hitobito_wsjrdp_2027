module Wsjrdp2027::Sheet::BaseClass
  private

  def sheet_for_controller(view_context)
    sheet_class = controller_sheet_class(view_context.controller)
    if view_context.action_name == "index" ||
        (sheet_class.method_defined?(:always_render_parent) && sheet_class.always_render_parent)

      if sheet_class.parent_sheet
        sheet_class = sheet_class.parent_sheet
      end
    end
    sheet_class
  end
end
