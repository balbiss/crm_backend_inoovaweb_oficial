class ContactsController < ApplicationController
  before_action :set_contact, only: %i[ show update destroy merge add_note block unblock ]

  # GET /contacts
  def index
    base = current_user.account.contacts
    @contacts = if current_user.full_account_access?
      base
    elsif current_user.team_manager?
      base.where(user_id: current_user.team_scope_ids)
    elsif current_user.permissions&.dig('view_all_contacts')
      base
    else
      base.where(user_id: current_user.id)
    end

    page     = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 50).to_i.clamp(1, 200)
    @contacts = @contacts.order(created_at: :desc).offset((page - 1) * per_page).limit(per_page)

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
    @contact.account_id = current_user.account_id
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
    target_contact = current_user.account.contacts.find_by(id: params[:target_contact_id])
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
    note.user_id = current_user.id

    if note.save
      render json: note.as_json(include: :user), status: :created
    else
      render json: note.errors, status: :unprocessable_entity
    end
  end

  def block
    @contact.update!(status: 'blocked')
    # Pausa a IA permanentemente para esse contato, em cada inbox onde ele tem conversa
    jid = @contact.channel_identifier
    if jid.present?
      @contact.conversations.where.not(inbox_id: nil).distinct.pluck(:inbox_id).each do |inbox_id|
        Rails.cache.write("ai_paused_#{inbox_id}_#{jid}", Time.current.to_i)
      end
    end
    render json: { message: 'Contato bloqueado com sucesso', status: 'blocked' }
  end

  def unblock
    @contact.update!(status: 'active')
    jid = @contact.channel_identifier
    if jid.present?
      @contact.conversations.where.not(inbox_id: nil).distinct.pluck(:inbox_id).each do |inbox_id|
        Rails.cache.delete("ai_paused_#{inbox_id}_#{jid}")
      end
    end
    render json: { message: 'Contato desbloqueado com sucesso', status: 'active' }
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_contact
      @contact = current_user.account.contacts.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def contact_params
      params.require(:contact).permit(
      :name, :email, :phone, :jid, :avatar_url, :status,
      :first_name, :last_name, :city, :country, :bio, :company_name, 
      :temperature, :source, :intention,
      :cpf, :birth_date, :profession, :gross_income, :down_payment, :fgts_balance, :dependents,
      :cep, :street, :neighborhood, :state, :address_number, :address_complement,
      custom_attributes: {}
    )
    end
end
