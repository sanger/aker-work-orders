require 'lims_client'
require 'event_message'
require 'securerandom'

# A work order, either in the progress of being defined (pending),
# or fully defined and waiting to be completed (active),
# or one that has been completed or cancelled (closed).
class WorkOrder < ApplicationRecord
  include AkerPermissionGem::Accessible

  belongs_to :product, optional: true
  has_many :work_order_module_choice, dependent: :destroy

  before_validation :sanitise_owner
  before_save :sanitise_owner

  after_initialize :create_uuid
  after_create :set_default_permission_email

  validates :owner_email, presence: true

  def create_uuid
    self.work_order_uuid ||= SecureRandom.uuid
  end

  def set_default_permission_email
    set_default_permission(owner_email)
  end

  # The work order is in the 'active' state when it has been ordered
  #  and the order has yet to be completed or cancelled.
  def self.ACTIVE
    'active'
  end

  # The work order is in the 'broken' state when processing some operation
  # on it failed, and the correct state could not be recovered.
  # A broken work order can only be fixed by manual intervention.
  def self.BROKEN
    'broken'
  end

  def self.COMPLETED
    'completed'
  end

  def self.CANCELLED
    'cancelled'
  end

  scope :for_user, -> (owner) { where(owner_email: owner.email) }
  scope :active, -> { where(status: WorkOrder.ACTIVE) }
  # status is either set, product, proposal
  scope :pending, -> { where('status NOT IN (?)', not_pending_status_list)}
  scope :completed, -> { where(status: WorkOrder.COMPLETED) }
  scope :cancelled, -> { where(status: WorkOrder.CANCELLED) }

  def materials
    SetClient::Set.find_with_materials(set_uuid).first.materials
  end

  def has_materials?(uuids)
    return true if uuids.empty?
    return false if set_uuid.nil?
    uuids_from_work_order_set = SetClient::Set.find_with_materials(set_uuid).first.materials.map(&:id)
    uuids.all? do |uuid|
      uuids_from_work_order_set.include?(uuid)
    end
  end

  def self.not_pending_status_list
    [WorkOrder.ACTIVE, WorkOrder.BROKEN, WorkOrder.COMPLETED, WorkOrder.CANCELLED]
  end

  def pending?
    # Returns true if the work order wizard has not yet been completed
    WorkOrder.not_pending_status_list.exclude?(status)
  end

  def active?
    status == WorkOrder.ACTIVE
  end

  def closed?
    status == WorkOrder.COMPLETED || status == WorkOrder.CANCELLED
  end

  def broken!
    update_attributes(status: WorkOrder.BROKEN)
  end

  def sanitise_owner
    if owner_email
      sanitised = owner_email.strip.downcase
      if sanitised != owner_email
        self.owner_email = sanitised
      end
    end
  end

  def proposal
  	return nil unless proposal_id
    return @proposal if @proposal&.id==proposal_id
	  @proposal = StudyClient::Node.find(proposal_id).first
  end

  def original_set
    return nil unless original_set_uuid
    return @original_set if @original_set&.uuid==original_set_uuid
    @original_set = SetClient::Set.find(original_set_uuid).first
  end

  def original_set=(orig_set)
    self.original_set_uuid = orig_set&.uuid
    @original_set = orig_set
  end

  def set
    return nil unless set_uuid
    return @set if @set&.uuid==set_uuid
    @set = SetClient::Set.find(set_uuid).first
  end

  def set=(set)
    self.set_uuid = set&.uuid
    @set = set
  end

  def finished_set
    return nil unless finished_set_uuid
    return @finished_set if @finished_set&.uuid==finished_set_uuid
    @finished_set = SetClient::Set.find(finished_set_uuid).first
  end

  def num_samples
    self.set && self.set.meta['size']
  end

  # Create a locked set from this work order's original set.
  def create_locked_set
    self.set = original_set.create_locked_clone("Work Order #{id}")
    save!
  end

  def name
    "Work Order #{id}"
  end

  def send_to_lims
    lims_url = product.catalogue.url
    LimsClient::post(lims_url, lims_data)
  end

  def all_results(result_set)
    results = result_set.to_a
    while result_set.has_next? do
      result_set = result_set.next
      results += result_set.to_a
    end
    results
  end

  def lims_data_for_get
    data = lims_data
    unless data[:work_order].nil?
      data[:work_order][:status] = status
    end
    data
  end

  # This method returns a JSON description of the order that will be sent to a LIMS to order work.
  # It includes information that must be loaded from other services (study, set, etc.).
  def lims_data
    material_ids = SetClient::Set.find_with_materials(set_uuid).first.materials.map{|m| m.id}
    materials = all_results(MatconClient::Material.where("_id" => {"$in" => material_ids}).result_set)

    unless materials.all? { |m| m.attributes['available'] }
      raise "Some of the specified materials are not available."
    end

    material_data = materials.map do |m|
          {
            _id: m.id,
            is_tumour: m.attributes['is_tumour'],
            supplier_name: m.attributes['supplier_name'],
            taxon_id: m.attributes['taxon_id'],
            tissue_type: m.attributes['tissue_type'],
            container: nil,
            gender: m.attributes['gender'],
            donor_id: m.attributes['donor_id'],
            phenotype: m.attributes['phenotype'],
            scientific_name: m.attributes['scientific_name'],
            available: m.attributes['available']
          }
    end
    describe_containers(material_ids, material_data)

    if proposal.subproject?
      project = StudyClient::Node.find(proposal.parent_id).first
    else
      project = proposal
    end

    {
      work_order: {
        product_name: product.name,
        product_version: product.product_version,
        work_order_id: id,
        comment: comment,
        project_uuid: project.node_uuid,
        project_name: project.name,
        data_release_uuid: project.data_release_uuid,
        cost_code: proposal.cost_code,
        desired_date: desired_date,
        materials: material_data,
        modules: module_choices,
      }
    }
  end

  def describe_containers(material_ids, material_data)
    containers = MatconClient::Container.where("slots.material" => { "$in" => material_ids}).result_set
    material_map = material_data.each_with_object({}) { |t,h| h[t[:_id]] = t }
    while containers do
      containers.each do |container|
        container.slots.each do |slot|
          if material_ids.include? slot.material_id
            unless material_map[slot.material_id][:container]
              container_data = { barcode: container.barcode }
              container_data[:num_of_rows] = container.num_of_rows
              container_data[:num_of_cols] = container.num_of_cols
              container_data[:address] = slot.address
              material_map[slot.material_id][:container] = container_data
            end
          end
        end
      end
      containers = (containers.has_next? ? containers.next : nil)
    end
  end

  def generate_completed_and_cancel_event
    if closed?
      message = EventMessage.new(work_order: self, status: status)
      EventService.publish(message)
      BillingFacadeClient.send_event(self, status)
    else
      raise 'You cannot generate an event from a work order that has not been completed.'
    end
  end

  def generate_submitted_event
    if active?
      message = EventMessage.new(work_order: self, status: 'submitted')
      EventService.publish(message)
      BillingFacadeClient.send_event(self, 'submitted')
    else
      raise 'You cannot generate an submitted event from a work order that is not active.'
    end
  end

  def module_choices
    module_choices = []
    WorkOrderModuleChoice.where(work_order_id: id).order(:position).pluck(:aker_process_modules_id).each do |id|
      module_choices.push(Aker::ProcessModule.find(id).name)
    end
    module_choices
  end
end
