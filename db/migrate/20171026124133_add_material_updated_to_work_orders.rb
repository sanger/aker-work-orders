class AddMaterialUpdatedToWorkOrders < ActiveRecord::Migration[5.0]
  def change
    add_column :work_orders, :material_updated, :boolean, default: false
  end
end
