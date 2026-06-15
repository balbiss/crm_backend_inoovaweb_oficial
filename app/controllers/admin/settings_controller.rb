class Admin::SettingsController < Admin::BaseController
  def index
    # Retorna todas as configurações como um hash { "openai_api_key": "...", "openai_model": "..." }
    settings = GlobalSetting.all.each_with_object({}) do |setting, hash|
      hash[setting.key] = setting.value
    end
    render json: settings
  end

  def create
    # Recebe um JSON no formato: { settings: { openai_api_key: "...", openai_model: "..." } }
    params[:settings]&.each do |key, value|
      setting = GlobalSetting.find_or_initialize_by(key: key)
      setting.value = value
      setting.save!
    end
    
    render json: { message: "Configurações salvas com sucesso." }
  end
end
