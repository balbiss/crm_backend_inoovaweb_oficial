class GlobalSetting < ApplicationRecord
  after_commit { Rails.cache.delete("global_setting:#{key}") }

  def self.fetch(key)
    Rails.cache.fetch("global_setting:#{key}", expires_in: 5.minutes) do
      find_by(key: key)&.value
    end
  end
end
