class ContactsController < ApplicationController
  before_action :set_contact, only: %i[ show update destroy merge add_note block unblock ]

  # GET /contacts
  def index
    if current_user&.role == 'admin' || current_user&.role == 'empresa' || current_user&.permissions&.dig('view_all_contacts')
      @contacts = Contact.all
    else
      @contacts = Contact.where(user_id: current_user.id)
    end

    render json: @contacts
  end

  # GET /contacts/1
  def show
    @contact = Contact.includes(conversations: :messages, notes: :user).find(@contact.id)
    render json: @contact.as_json(include: {
      conversations: {
        include: :messages
      },
      notes: {
        include: :user
      }
    })
  end

  # POST /contacts
  def create
    @contact = Contact.new(contact_params)
    @contact.user_id ||= current_user.id

    if @contact.save
      render json: @contact, status: :created, location: @contact
    else
      render json: @contact.errors, status: :unprocessable_content
    end
  end

  # PATCH/PUT /contacts/1
  def update
    if @contact.update(contact_params)
      render json: @contact
    else
      render json: @contact.errors, status: :unprocessable_content
    end
  end

  # DELETE /contacts/1
  def destroy
    @contact.destroy!
    head :no_content
  end

  # POST /contacts/1/merge
  def merge
    target_contact = Contact.find_by(id: params[:target_contact_id])
    if target_contact.nil? || target_contact.id == @contact.id
      return render json: { error: 'Invalid target contact' }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      @contact.conversations.update_all(contact_id: target_contact.id)
      @contact.destroy!
    end

    render json: { message: 'Contacts merged successfully', contact: target_contact }
  end

  # POST /contacts/1/add_note
  def add_note
    note = @contact.notes.new(content: params[:content])
    note.account_id = @contact.account_id
    note.user_id = current_user.id if respond_to?(:current_user) && current_user
    
    # Just in case we don't have current_user properly mapped yet
    note.user_id ||= User.first.id

    if note.save
      render json: note.as_json(include: :user), status: :created
    else
      render json: note.errors, status: :unprocessable_entity
    end
  end

  def block
    @contact.update!(status: 'blocked')
    # Pausa a IA permanentemente para esse contato
    jid = @contact.jid.presence || @contact.phone
    inbox = current_user.account.inboxes.first
    Rails.cache.write("ai_paused_#{inbox&.id}_#{jid}", Time.current.to_i) if inbox && jid
    render json: { message: 'Contato bloqueado com sucesso', status: 'blocked' }
  end

  def unblock
    @contact.update!(status: 'active')
    jid = @contact.jid.presence || @contact.phone
    inbox = current_user.account.inboxes.first
    Rails.cache.delete("ai_paused_#{inbox&.id}_#{jid}") if inbox && jid
    render json: { message: 'Contato desbloqueado com sucesso', status: 'active' }
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_contact
      @contact = Contact.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def contact_params
      params.require(:contact).permit(
      :name, :email, :phone, :jid, :avatar_url, :status, :account_id, 
      :first_name, :last_name, :city, :country, :bio, :company_name, 
      :temperature, :source, :intention,
      :cpf, :birth_date, :profession, :gross_income, :down_payment, :fgts_balance, :dependents,
      :cep, :street, :neighborhood, :state, :address_number, :address_complement,
      custom_attributes: {}
    )
    end
end
